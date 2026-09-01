extends Node
## Autoload. Owns the Traveling Peddler's appearances: when one opens, where it
## opens, and tearing it down again.
##
## SERVER-ONLY BEHAVIOUR. This is an autoload, so it also boots on every client
## and inside every render tool — and a tool that mounts OfflineMultiplayerPeer
## reads as a server to [code]multiplayer.is_server()[/code]. The gate here is
## [method GameMode.is_world_server], which reads the launch mode rather than the
## peer, so a client never ticks this and a preview tool never spawns a cart into
## a screenshot.
##
## THE CYCLE is wall-clock UTC ([PeddlerSchedule]), not uptime. A world that
## restarts at 03:58 rejoins the 00:00 window with two minutes left on it rather
## than starting a fresh half hour — players plan around "the four-o'clock
## peddler", and that promise has to survive a deploy.
##
## SPAWNING IS OPPORTUNISTIC. Biome instances are charged on demand, so the map
## the Peddler is due in may not be loaded when the window opens. The biome is
## still DECIDED at that moment (so the window can say where they are), and the
## cart is placed on the first tick the instance exists. The alternative —
## charging the instance ourselves — would keep an empty biome resident for half
## an hour every four hours purely to host an NPC nobody is looking at.

## How often the window state is re-evaluated. Coarse on purpose: nothing here is
## time-critical, and a 30-minute window makes a few seconds of slop invisible.
const TICK_S: float = 5.0

## The cycle currently standing, or -1 when nothing is.
var _active_cycle: int = -1
## Biome instance_name this cycle is assigned to (set even before placement).
var _active_biome: StringName = &""
## This cycle's full biome order, and how far down it we have had to walk. Only
## a biome that cannot host the cart advances the index — see [method _skip_biome].
var _rotation: Array[StringName] = []
var _rotation_index: int = 0
## Live prop ids, so teardown never has to search the map for its own nodes.
var _peddler_prop_id: int = -1
var _vault_prop_id: int = -1
var _active_instance: ServerInstance = null
## True once this cycle's arrival has been announced, so a biome that loads late
## does not re-announce it.
var _announced: bool = false
## Cycle whose OPENING has been pushed to the website, so the "due but not
## standing" snapshot goes out once rather than every five seconds.
var _open_exported_cycle: int = -1
## UTC date of the last snapshot pushed to the website. The daily stock rolls at
## UTC midnight with no event of its own — nothing spawns, nothing despawns, the
## three wares simply become different ones — so the only way to notice is to
## compare the date on the tick we are already running.
var _exported_date: String = ""


func _ready() -> void:
	if not GameMode.is_world_server():
		return
	var timer: Timer = Timer.new()
	timer.wait_time = TICK_S
	timer.autostart = true
	timer.timeout.connect(_tick)
	add_child(timer)


# --- Read-only state, for the handlers and the verify tool ---

## The cycle that is open right now, or -1 between windows.
func active_cycle() -> int:
	return _active_cycle


## Biome instance_name the Peddler is assigned to this window (&"" when closed).
## Set as soon as the window opens, even if the cart is not placed yet.
func active_biome() -> StringName:
	return _active_biome


## True when the cart is actually standing in a loaded instance.
func is_spawned() -> bool:
	return (
		_peddler_prop_id >= 0
		and _active_instance != null
		and is_instance_valid(_active_instance)
	)


## The live Peddler NPC node, or null.
func peddler_node() -> Node:
	if not is_spawned():
		return null
	var container: ReplicatedPropsContainer = _container(_active_instance)
	if container == null:
		return null
	return container.dynamic_nodes.get(_peddler_prop_id, null)


# --- Cycle driving ---

func _tick() -> void:
	var now: int = PeddlerSchedule.now_s()
	var cycle: int = PeddlerSchedule.cycle_index(now)
	var open: bool = PeddlerSchedule.is_active(now)

	# Window closed, or the clock rolled into a new cycle while the old cart was
	# still up. Either way what is standing belongs to a window that is over.
	if (not open or cycle != _active_cycle) and _active_cycle != -1:
		_teardown()

	if not open:
		return

	if _active_cycle != cycle:
		_open_cycle(cycle)

	if not is_spawned():
		_try_place()

	# STILL NOTHING STANDING. The biome is decided but has no loaded instance, so
	# the cart cannot be placed until somebody walks in. Say so once per cycle:
	# the snapshot carries is_active = false AND the assigned zone, which is what
	# lets the site read "due in The Desert" rather than describing the previous
	# window for four hours. Deliberately AFTER _try_place, so a window that
	# places on its first tick sends only the spawn — two POSTs racing in one
	# frame could land out of order and leave the site saying "due" over a cart
	# that is already up.
	if not is_spawned() and _open_exported_cycle != _active_cycle:
		_open_exported_cycle = _active_cycle
		_export("window open, awaiting biome")

	# The daily roll: same window, different wares. Checked after placement so a
	# midnight spawn exports once with the cart already up rather than twice.
	var today: String = PeddlerSchedule.utc_date(now)
	if today != _exported_date:
		_export("daily stock roll")


## Decide (but do not necessarily place) this cycle's Peddler.
func _open_cycle(cycle: int) -> void:
	_active_cycle = cycle
	_rotation = PeddlerSites.rotation_for_cycle(cycle)
	_rotation_index = 0
	_active_biome = _rotation[0] if not _rotation.is_empty() else &""
	_announced = false
	if _active_biome == &"":
		push_error("PeddlerManager: no biome instances to pick from — cart cannot open.")


## Give up on the current biome for this cycle and take the next one in the
## rotation. Only for a biome that STRUCTURALLY cannot host the cart — never for
## one that merely is not loaded yet, which is the ordinary case and is handled by
## retrying. Advancing on "not loaded" would concentrate the Peddler in whichever
## biomes happen to be busy, which is the opposite of the design.
func _skip_biome(reason: String) -> void:
	push_error("PeddlerManager: %s cannot host the cart (%s) — trying the next biome." % [
		_active_biome, reason
	])
	_rotation_index += 1
	if _rotation_index >= _rotation.size():
		push_error("PeddlerManager: no biome in the rotation can host the cart.")
		_active_biome = &""
		return
	_active_biome = _rotation[_rotation_index]


## Place the cart if the assigned biome has a loaded instance. Retried every tick
## until it succeeds or the window closes.
func _try_place() -> void:
	if _active_biome == &"":
		return
	var instance: ServerInstance = _first_charged(_active_biome)
	if instance == null or instance.instance_map == null:
		return
	var container: ReplicatedPropsContainer = _container(instance)
	if container == null:
		# The map is loaded and genuinely cannot carry a dynamic prop — its
		# container was never scripted or wired (deep_shoals is one today). Move
		# to the next biome rather than spending the whole window failing here,
		# and keep shouting so the map bug gets found.
		_skip_biome("no replicated props container")
		return

	var spot: Dictionary = PeddlerSites.pick_spot(instance.instance_map, _active_cycle)
	# The node NAME rides the spawn INIT, not a post-spawn assignment. The client
	# instantiates its own copy from the same packed scene and would otherwise
	# call it "NPC"; the window sends that name back for the server's range check,
	# so the two ends naming it differently is a cart that refuses every request
	# with "closed". Init is applied identically on both sides, before add_child.
	var peddler: Node = container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_NPC,
		container.to_local(spot["peddler"]),
		{"name": PeddlerNames.NODE_NAME, "npc_slug": PeddlerNames.NPC_SLUG}
	)
	if peddler == null:
		return
	_peddler_prop_id = container.child_id_of_node(peddler)
	_active_instance = instance

	# The vault is resolved by prop id, not by name, so its name is only for
	# anyone reading the remote scene tree.
	var vault: Node = container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_PEDDLER_VAULT,
		container.to_local(spot["vault"]),
		{"name": PeddlerNames.VAULT_NODE_NAME}
	)
	if vault != null:
		_vault_prop_id = container.child_id_of_node(vault)

	if not _announced:
		_announced = true
		_announce()
	_export("spawn")


## Remove the standing cart and forget the cycle.
func _teardown() -> void:
	var container: ReplicatedPropsContainer = _container(_active_instance)
	if container != null:
		for prop_id: int in [_peddler_prop_id, _vault_prop_id]:
			if prop_id >= 0 and container.dynamic_nodes.has(prop_id):
				container.despawn_dynamic(prop_id)
	_peddler_prop_id = -1
	_vault_prop_id = -1
	_active_instance = null
	_active_cycle = -1
	_active_biome = &""
	_rotation = []
	_rotation_index = 0
	_announced = false
	_open_exported_cycle = -1
	# AFTER the state is cleared, so the snapshot says "gone" rather than
	# describing a cart that has already been taken down.
	_export("despawn")


## Push the current snapshot to the website. Fire-and-forget: the return value is
## deliberately ignored, because a website that is down must never change what
## the cart does. [param reason] is for the log only.
##
## Called on the three moments the site's display can go stale — the cart
## appearing, the cart leaving, and the wares rolling over at UTC midnight.
func _export(reason: String) -> void:
	_exported_date = PeddlerSchedule.utc_date()
	# The two integrations are independent: a server may run the website tracker
	# without Discord, or Discord without the tracker. Build the snapshot once,
	# then let each decide for itself whether it is configured.
	if not PeddlerWebExport.is_configured() and not PeddlerDiscord.is_configured():
		return # nothing configured (every dev machine) — stay silent
	var payload: Dictionary = PeddlerWebExport.build_payload(_active_biome, is_spawned())

	if PeddlerWebExport.post(self, payload):
		ServerLog.info("Peddler web export: %s (%s)." % [
			reason, "active" if payload["is_active"] else "roaming"
		])

	# SPAWN ONLY. A despawn or a midnight stock roll is not something a player
	# can act on, and a channel that pings for those is a channel people mute —
	# taking the one message that mattered with it.
	if reason == "spawn" and PeddlerDiscord.announce(self, payload):
		ServerLog.info("Peddler Discord announce: %s." % str(payload.get("current_zone", "")))


# --- Helpers ---

func _first_charged(instance_name: StringName) -> ServerInstance:
	var ws: WorldServer = WorldServer.curr
	if ws == null or ws.instance_manager == null:
		return null
	var res: InstanceResource = ws.instance_manager.instance_collection.get(
		String(instance_name), null
	)
	if res == null:
		return null
	for node: Node in res.charged_instances:
		if (
			node is ServerInstance
			and is_instance_valid(node)
			and (node as ServerInstance).instance_map != null
		):
			return node as ServerInstance
	return null


func _container(instance: ServerInstance) -> ReplicatedPropsContainer:
	if instance == null or not is_instance_valid(instance) or instance.instance_map == null:
		return null
	return instance.instance_map.replicated_props_container


## System line to every connected player — the cart is a server-wide event and
## the whole point of it is that people go. Mirrors EventService._announce.
func _announce() -> void:
	var ws: WorldServer = WorldServer.curr
	if ws == null or ws.instance_manager == null or ws.chat_service == null:
		return
	var res: InstanceResource = ws.instance_manager.instance_collection.get(
		String(_active_biome), null
	)
	var where: String = res.display_title() if res != null else String(_active_biome)
	var text: String = "A Traveling Peddler has set up in %s. They leave in %s." % [
		where, PeddlerSchedule.clock(PeddlerSchedule.seconds_remaining()),
	]
	for peer_id: int in ws.connected_players:
		var pr: PlayerResource = ws.connected_players[peer_id]
		if pr == null:
			continue
		var inst: ServerInstance = ws.instance_manager.find_instance_for_peer(peer_id)
		if inst != null:
			ws.chat_service.push_system_to_player(inst, pr.player_id, text)
