class_name GatherNodeLedger
## Per-player gather pool state for [MineableNode], stored on the PLAYER rather
## than on the node.
##
## Why it does not live on the node: a [ServerInstance] is freed by
## `InstanceManager.unload_unused_instances` as soon as its last peer leaves,
## and that sweeper runs every 20 seconds. A biome with one player in it is
## therefore destroyed almost immediately after they log out, taking every
## node's charge dictionary with it. Logging back in charged a brand-new
## instance whose veins, trees, herbs and fishing holes were all full again —
## a relog was a free respawn, and players used it to out-gather the timers.
##
## Hanging the state off [PlayerResource] fixes all three leaks at once:
##   * instance unload — the resource outlives the instance,
##   * server restart — it is written to the players table by save_player,
##   * instance hopping — the key is the instance NAME, not the node instance,
##     so two live copies of a biome share one pool per player.
##
## Timestamps are WALL CLOCK (unix seconds), not [method Time.get_ticks_msec],
## which is process uptime and means nothing once the state can outlive both the
## instance and the process. The practical difference is that a pool now
## regenerates while its owner is logged out, which is the behaviour a player
## already expects from a respawn timer.
##
## Entry shape, keyed by [method node_key]:
##   {"c": charges left, "p": pool size rolled for this fill, "t": unix seconds}
## The meaning of "t" mirrors the old in-memory field: with charges > 0 it is
## the last trickle-regen tick, at 0 it is the moment the pool ran dry.

## Ceiling on stored entries per character. Only DRAINED nodes are ever kept
## (see [method save_state]), and those refill in minutes, so a normal player
## sits far below this. It exists so a session spent tapping every node in the
## world cannot grow the blob without bound.
const MAX_ENTRIES: int = 512


static func _now() -> int:
	return int(Time.get_unix_time_from_system())


## Stable identity for a node, across instance reloads AND across two live
## copies of the same biome. `instance_name` comes from the InstanceResource
## (e.g. "woodland"), not from the ServerInstance node, whose name is per-copy.
## The path is authored in the map scene and nothing renames harvestables at
## spawn, so it survives a reload unchanged.
static func node_key(instance_name: String, node_path: NodePath) -> String:
	return "%s|%s" % [instance_name, String(node_path)]


static func _roll_pool(data: MineableNodeResource) -> int:
	if data.min_charges > 0 and data.min_charges < data.max_charges:
		return randi_range(data.min_charges, data.max_charges)
	return data.max_charges


## Live {"c": charges, "p": pool} for this player on this node, with lazy regen
## already applied. Seeds a fresh full pool the first time a player works a node.
## Mutates and returns the stored entry, so callers can read it directly.
static func entry(resource: PlayerResource, key: String, data: MineableNodeResource) -> Dictionary:
	if resource == null or data == null:
		return {"c": 0, "p": 0}
	var store: Dictionary = resource.gather_nodes
	var e: Variant = store.get(key)
	if not (e is Dictionary):
		var pool: int = _roll_pool(data)
		var fresh: Dictionary = {"c": pool, "p": pool, "t": _now()}
		store[key] = fresh
		return fresh
	_regen(e as Dictionary, data)
	return e as Dictionary


static func charges(resource: PlayerResource, key: String, data: MineableNodeResource) -> int:
	return int(entry(resource, key, data).get("c", 0))


static func pool(resource: PlayerResource, key: String, data: MineableNodeResource) -> int:
	return int(entry(resource, key, data).get("p", data.max_charges if data != null else 0))


## Spend one charge. Mirrors the old `_consume_charge`: the clock is restamped
## when the pool empties (starting the long respawn) and when it first drops off
## full (starting the trickle), so a partly drained pool does not keep pushing
## its own regen deadline back on every swing.
static func consume(resource: PlayerResource, key: String, data: MineableNodeResource) -> void:
	var e: Dictionary = entry(resource, key, data)
	var size: int = int(e.get("p", 0))
	var left: int = int(e.get("c", 0)) - 1
	e["c"] = left
	if left == 0 or left == size - 1:
		e["t"] = _now()


## Continuous regen while above 0, snap-refill at 0. Lazy — runs on access, so
## a drained pool costs nothing while nobody is looking at it. This is the same
## logic the node used to run in-memory, moved here and put on the wall clock.
static func _regen(e: Dictionary, data: MineableNodeResource) -> void:
	var left: int = int(e.get("c", 0))
	var size: int = int(e.get("p", data.max_charges))
	if left >= size:
		return
	var now: int = _now()
	var last: int = int(e.get("t", now))
	# A clock that jumped backwards (NTP correction, host clock edit) would
	# otherwise freeze the pool until real time caught up.
	if last > now:
		e["t"] = now
		return
	if left <= 0:
		if now - last >= int(data.depleted_recharge_seconds):
			var fresh: int = _roll_pool(data)
			e["p"] = fresh
			e["c"] = fresh
			e["t"] = now
		return
	# Random pools are all-or-nothing: work it out, then wait for the respawn.
	if data.min_charges > 0 and data.min_charges < data.max_charges:
		return
	var interval: int = int(data.charge_regen_seconds)
	if interval <= 0:
		return
	@warning_ignore("integer_division")
	var gained: int = (now - last) / interval
	if gained > 0:
		e["c"] = mini(size, left + gained)
		e["t"] = last + gained * interval


## Persistence shape: the raw key -> entry map, minus anything already back to
## full. A full pool is indistinguishable from a node the player has never
## touched, so storing it would only grow the row for nothing.
static func save_state(resource: PlayerResource) -> Dictionary:
	if resource == null:
		return {}
	var out: Dictionary = {}
	for key: Variant in resource.gather_nodes:
		var e: Variant = resource.gather_nodes[key]
		if not (e is Dictionary):
			continue
		var d: Dictionary = e as Dictionary
		if int(d.get("c", 0)) >= int(d.get("p", 0)):
			continue
		out[str(key)] = {"c": int(d.get("c", 0)), "p": int(d.get("p", 0)), "t": int(d.get("t", 0))}
	return out


## Rows written before this key existed parse as an empty ledger, which reads as
## "every node full" — the same state those characters were already logging in
## to, so the migration needs no backfill.
static func load_state(resource: PlayerResource, raw: Variant) -> void:
	if resource == null:
		return
	resource.gather_nodes = {}
	if not (raw is Dictionary):
		return
	var rows: Array = (raw as Dictionary).keys()
	# Keep the freshest entries if a row somehow exceeds the cap.
	if rows.size() > MAX_ENTRIES:
		rows.sort_custom(func(a: Variant, b: Variant) -> bool:
			var ea: Variant = (raw as Dictionary)[a]
			var eb: Variant = (raw as Dictionary)[b]
			var ta: int = int((ea as Dictionary).get("t", 0)) if ea is Dictionary else 0
			var tb: int = int((eb as Dictionary).get("t", 0)) if eb is Dictionary else 0
			return ta > tb)
		rows = rows.slice(0, MAX_ENTRIES)
	for key: Variant in rows:
		var e: Variant = (raw as Dictionary)[key]
		if not (e is Dictionary):
			continue
		var d: Dictionary = e as Dictionary
		var size: int = int(d.get("p", 0))
		if size <= 0:
			continue
		resource.gather_nodes[str(key)] = {
			"c": clampi(int(d.get("c", 0)), 0, size),
			"p": size,
			"t": int(d.get("t", 0)),
		}


## Drop the oldest entries once a session has piled up more than the cap. Called
## on write, so the in-memory dict cannot grow unbounded either.
static func trim(resource: PlayerResource) -> void:
	if resource == null or resource.gather_nodes.size() <= MAX_ENTRIES:
		return
	var keys: Array = resource.gather_nodes.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int((resource.gather_nodes[a] as Dictionary).get("t", 0)) \
			> int((resource.gather_nodes[b] as Dictionary).get("t", 0)))
	for key: Variant in keys.slice(MAX_ENTRIES):
		resource.gather_nodes.erase(key)
