class_name BossHuntService
## Server-only orchestration of a BOSS HUNT: a party of up to
## [constant PARTY_SIZE] buys a 30-minute private arena for one boss of their
## choice, farms it on a fast respawn, and is sent home to the Guild Hall when
## the clock runs out. Every drop is banked straight into each participant's
## Hunt Chest (see HuntChest / RewardService), so the wrap-up is "go empty your
## chest", not a scramble for loot on the floor at second 1799.
##
## Structurally this is DungeonService's sibling: same lobby-at-a-station shape,
## same private-instance lifecycle (prepare_instance -> player_switch_instance ->
## unload_unused_instances reclaims it), same recall-to-hub eject, and the same
## shared-lives idea as a HARD run. What differs is that there is no clear
## condition — the arena keeps respawning its boss — so a contract ends only two
## ways: the clock runs out (_end_hunt, the party keeps everything) or the party
## burns all [constant CONTRACT_LIVES] lives (_fail_hunt). The pool is a flat 3
## rather than DungeonService's per-member sizing; see the constant.
##
## Server-authoritative; common-side state with direct WorldServer access, like
## DungeonService and SparringService.

## Instance_name of the arena InstanceResource every hunt is run in.
const ARENA_INSTANCE: StringName = &"boss_hunt_arena"
## Contract length. The whole session is paid for up front, so short of everyone
## walking out this and [constant CONTRACT_LIVES] are the only things that end a
## hunt.
const HUNT_DURATION_S: float = 1800.0
## Max party per contract, matching a dungeon run.
const PARTY_SIZE: int = 4
## How close to the broker you must stand to use the lobby.
const QUEUE_RANGE: float = 120.0
## Seconds the "contract complete" banner shows before the party is sent home.
const EJECT_DELAY_S: float = 8.0
## Seconds the "contract failed" banner shows before the party is sent home.
## Shorter than EJECT_DELAY_S: there is nothing to read but the bad news.
const FAIL_EJECT_DELAY_S: float = 6.0
## Remaining-time marks (seconds) that get a chat warning.
const WARN_AT_S: Array[int] = [600, 300, 60]
## Lives shared by the WHOLE party for the whole contract. Deliberately a flat
## number and not one-per-member the way DungeonService.SOLO_REVIVES scales: a
## contract buys three deaths whether one hunter or four walk through the door,
## so bringing friends buys you damage, not durability. Each death spends one;
## the death that spends the LAST one fails the contract on the spot.
const CONTRACT_LIVES: int = 3

# group_id -> the private arena ServerInstance running for that party.
static var _hunts: Dictionary[int, Node] = {}
# private instance node name -> group_id, so a leave/kill can find its hunt.
static var _instance_to_group: Dictionary[String, int] = {}
# group_id -> ticks_msec the contract expires at.
static var _end_at_ms: Dictionary[int, int] = {}
# group_id -> the contract being farmed.
static var _targets: Dictionary[int, BossHuntTarget] = {}
# group_id -> bosses killed so far (for the wrap-up).
static var _kills: Dictionary[int, int] = {}
# group_id -> CONTRACT_LIVES left on the contract, shared by the whole party.
static var _lives: Dictionary[int, int] = {}
# group_ids being auto-ejected at expiry, so on_player_left can tell that from a
# voluntary walk-out (which gets its own toast).
static var _ejecting: Dictionary[int, bool] = {}
# lobby key (instance_name::station) -> Array[int] of queued peer ids.
static var _lobbies: Dictionary[String, Array] = {}
# lobby key -> the contract id the party has selected.
static var _lobby_choice: Dictionary[String, StringName] = {}


# --- lobby (contract board at the Hunt Broker) ------------------------------

## select / join / leave / start a hunt lobby (boss_hunt.queue handler). One
## shared queue per broker; the starter pays and launches the whole queue.
## Server-only.
static func handle_lobby_request(
	instance: Node,
	peer_id: int,
	station: String,
	action: String,
	args: Dictionary
) -> Dictionary:
	if not _station_is_broker(instance, station):
		return {"ok": false, "reason": "no_broker"}
	var node: Node2D = instance.instance_map.get_node_or_null(NodePath(station)) as Node2D
	var player: Player = instance.get_player(peer_id) as Player
	if player == null:
		return {"ok": false, "reason": "no_player"}
	if node != null and player.global_position.distance_to(node.global_position) > QUEUE_RANGE:
		return {"ok": false, "reason": "too_far"}
	if GroupService.group_of(peer_id) != 0:
		return {"ok": false, "reason": "in_run"} # already on a contract / in a dungeon

	var key: String = _lobby_key(str(instance.name), station)
	var queue: Array = _lobbies.get(key, [])
	match action:
		"select":
			# Anyone in the lobby may re-pick; the board is a shared choice and the
			# payer sees the price before they commit.
			var contract_id: StringName = StringName(str(args.get("contract", "")))
			if BossHuntCatalog.find(contract_id) == null:
				return {"ok": false, "reason": "no_contract"}
			_lobby_choice[key] = contract_id
			_broadcast_lobby(instance, station, queue, contract_id)
			return lobby_status(instance, peer_id, station)
		"join":
			if queue.size() >= PARTY_SIZE:
				return {"ok": false, "reason": "full"}
			if not queue.has(peer_id):
				queue.append(peer_id)
			_lobbies[key] = queue
			_broadcast_lobby(instance, station, queue, _lobby_choice.get(key, &""))
			return lobby_status(instance, peer_id, station)
		"leave":
			queue.erase(peer_id)
			_lobbies[key] = queue
			_broadcast_lobby(instance, station, queue, _lobby_choice.get(key, &""))
			return lobby_status(instance, peer_id, station)
		"start":
			var target: BossHuntTarget = BossHuntCatalog.find(_lobby_choice.get(key, &""))
			if target == null:
				return {"ok": false, "reason": "no_contract"}
			# The STARTER pays the whole contract; everyone else rides free.
			var charged: Dictionary = _charge(player, target.cost)
			if not bool(charged.get("ok", false)):
				return charged
			# Payer FIRST, then the queue up to capacity. Appending them instead
			# would push them past the cap on a full queue — and drop the one
			# person who actually paid out of their own contract.
			var party: Array = [peer_id]
			for queued: int in queue:
				if party.size() >= PARTY_SIZE:
					break
				if not party.has(queued):
					party.append(queued)
			_lobbies.erase(key)
			_lobby_choice.erase(key)
			_broadcast_lobby(instance, station, [], &"")
			if not start_hunt(party, target, peer_id):
				_refund(player, target.cost)
				return {"ok": false, "reason": "no_arena",
					"message": "The broker couldn't open a room. You weren't charged."}
			return {"ok": true, "started": true, "paid": target.cost}
		_:
			return {"ok": false, "reason": "bad_action"}


## Board + lobby snapshot for the caller (boss_hunt.info handler).
static func lobby_status(instance: Node, peer_id: int, station: String) -> Dictionary:
	if not _station_is_broker(instance, station):
		return {"ok": false, "reason": "no_broker"}
	var key: String = _lobby_key(str(instance.name), station)
	var queue: Array = _lobbies.get(key, [])
	var gold: int = 0
	var player: Player = instance.get_player(peer_id) as Player
	if player != null and player.player_resource != null and Economy.gold_id() > 0:
		gold = Inventory.count(player.player_resource.inventory, Economy.gold_id())
	return {
		"ok": true,
		"station": station,
		"contracts": BossHuntCatalog.to_payload(),
		"selected": String(_lobby_choice.get(key, &"")),
		"members": _names(instance, queue),
		"in_queue": queue.has(peer_id),
		"capacity": PARTY_SIZE,
		"gold": gold,
		"duration_s": int(HUNT_DURATION_S),
	}


## Charge [param cost] gold to [param player]. Returns {"ok": true} or a reason
## the caller can hand straight back to the client.
static func _charge(player: Player, cost: int) -> Dictionary:
	if cost <= 0:
		return {"ok": true}
	var resource: PlayerResource = player.player_resource
	var gold_id: int = Economy.gold_id()
	if resource == null or gold_id <= 0:
		return {"ok": false, "reason": "no_gold"}
	if Inventory.count(resource.inventory, gold_id) < cost:
		return {"ok": false, "reason": "poor", "message": "You need %d gold for that contract." % cost}
	if not Inventory.remove_amount_by_id(resource.inventory, gold_id, cost):
		return {"ok": false, "reason": "poor", "message": "You need %d gold for that contract." % cost}
	return {"ok": true}


## Hand the fee back when a charged contract fails to open. Gold is a currency
## item, so it always fits — no capacity check needed.
static func _refund(player: Player, cost: int) -> void:
	if cost <= 0 or player == null or player.player_resource == null:
		return
	var gold_id: int = Economy.gold_id()
	if gold_id > 0:
		Inventory.add_item(player.player_resource.inventory, gold_id, cost, false, player.player_resource.active_inventory_bag, player.player_resource.inventory_bags)


# --- run lifecycle -----------------------------------------------------------

## Open a contract for [param peers] on [param target], paid for by
## [param payer]. Spins up a PRIVATE arena instance (one per party — the same
## reason DungeonService can't use queue_charge_instance: that dedupes by
## resource) and moves everyone in when it's loaded.
##
## Returns false if the contract could not be opened at all. The caller has
## already taken the payer's gold by then, so a false here MUST be refunded.
static func start_hunt(peers: Array, target: BossHuntTarget, payer: int) -> bool:
	if WorldServer.curr == null or peers.is_empty() or target == null:
		return false
	var arena: InstanceResource = _arena_resource()
	if arena == null:
		push_warning("BossHuntService: no '%s' instance resource — contract aborted." % ARENA_INSTANCE)
		return false
	var members: Array = []
	for p: Variant in peers:
		if int(p) > 0 and not members.has(int(p)):
			members.append(int(p))
	if members.is_empty():
		return false

	var group_id: int = GroupService.create_group(members, payer if members.has(payer) else members[0])
	_targets[group_id] = target
	_kills[group_id] = 0
	_lives[group_id] = CONTRACT_LIVES
	_end_at_ms[group_id] = Time.get_ticks_msec() + int(HUNT_DURATION_S * 1000.0)

	var instance_manager: Node = WorldServer.curr.instance_manager
	var instance: Node = instance_manager.prepare_instance(arena)
	_hunts[group_id] = instance
	_instance_to_group[str(instance.name)] = group_id
	instance.ready.connect(func() -> void: _enter_hunt(group_id, members), CONNECT_ONE_SHOT)
	instance_manager.add_child(instance, true)
	return true


## Once the arena is loaded, move every member in, start the farm loop, and arm
## the expiry + warning timers.
static func _enter_hunt(group_id: int, members: Array) -> void:
	var instance: Node = _hunts.get(group_id, null)
	if instance == null or WorldServer.curr == null:
		return
	var instance_manager: Node = WorldServer.curr.instance_manager
	for peer: int in members:
		var current: Node = instance_manager.find_instance_for_peer(peer)
		if current == null:
			continue
		var player: Player = current.get_player(peer) as Player
		if player != null:
			instance_manager.player_switch_instance(instance, 0, player, current)
			player.restore_full() # start the contract topped up, like a dungeon run

	var target: BossHuntTarget = _targets.get(group_id, null)
	# Delayed so it lands after the clients finish loading the arena (the switch is
	# still in flight this frame) — and so the first boss isn't already swinging
	# when the screen fades in.
	WorldServer.curr.get_tree().create_timer(1.5).timeout.connect(
		func() -> void:
			var arena_node: BossHuntArena = _arena_node(instance)
			if arena_node != null and target != null:
				arena_node.begin(target)
			for peer: int in GroupService.members_of(group_id):
				WorldServer.curr.data_push.rpc_id(peer, &"boss_hunt.entered", {
					"boss": target.title() if target != null else "the boss",
					"minutes": int(HUNT_DURATION_S / 60.0),
					"lives": CONTRACT_LIVES,
				})
			_push_hud(group_id),
		CONNECT_ONE_SHOT
	)

	# Expiry + the countdown warnings. One-shot timers rather than a per-frame
	# poll: nothing else in a hunt needs a tick, and each fires at most once.
	var tree: SceneTree = WorldServer.curr.get_tree()
	tree.create_timer(HUNT_DURATION_S).timeout.connect(
		func() -> void: _end_hunt(group_id), CONNECT_ONE_SHOT)
	for mark: int in WARN_AT_S:
		if float(mark) >= HUNT_DURATION_S:
			continue
		tree.create_timer(HUNT_DURATION_S - float(mark)).timeout.connect(
			func() -> void: _warn(group_id, mark), CONNECT_ONE_SHOT)


## The contract clock ran out: tell the party what they earned, then send them
## home to the Guild Hall (where their Hunt Chest is waiting).
static func _end_hunt(group_id: int) -> void:
	if not _hunts.has(group_id) or WorldServer.curr == null:
		return # already dissolved (everyone walked out early)
	var instance: Node = _hunts[group_id]
	var arena_node: BossHuntArena = _arena_node(instance)
	if arena_node != null:
		arena_node.stop()
	var target: BossHuntTarget = _targets.get(group_id, null)
	var kills: int = _kills.get(group_id, 0)
	for peer: int in GroupService.members_of(group_id):
		WorldServer.curr.data_push.rpc_id(peer, &"boss_hunt.complete", {
			"boss": target.title() if target != null else "the boss",
			"kills": kills,
			"seconds": int(HUNT_DURATION_S),
		})
	_hide_hud(group_id)
	WorldServer.curr.get_tree().create_timer(EJECT_DELAY_S).timeout.connect(
		func() -> void: _eject_hunt(group_id), CONNECT_ONE_SHOT)


## Recall every remaining member to the hub. on_player_left dissolves the group
## as they go, and the empty arena is reclaimed by unload_unused_instances.
static func _eject_hunt(group_id: int) -> void:
	if WorldServer.curr == null:
		return
	_ejecting[group_id] = true
	var instance_manager: Node = WorldServer.curr.instance_manager
	var instance: Node = _hunts.get(group_id, null)
	for peer: int in GroupService.members_of(group_id).duplicate():
		if instance != null:
			var player: Player = instance.get_player(peer) as Player
			if player != null:
				player.restore_full()
		instance_manager.recall_player(peer)


## A player left a hunt arena (exit door, recall, or the expiry eject). Drop them
## from the party; when it empties, forget the contract. No-op for a switch out
## of any non-hunt instance. Server-only.
static func on_player_left(peer_id: int, left_instance: Node) -> void:
	if left_instance == null:
		return
	var key: String = str(left_instance.name)
	var group_id: int = _instance_to_group.get(key, 0)
	if group_id == 0:
		return # not a hunt — ordinary warp / recall / jail
	if WorldServer.curr != null:
		if not _ejecting.get(group_id, false):
			WorldServer.curr.data_push.rpc_id(peer_id, &"boss_hunt.left", {})
		WorldServer.curr.data_push.rpc_id(peer_id, &"boss_hunt.hud", {"active": false})
	GroupService.leave(peer_id)
	if GroupService.members_of(group_id).is_empty():
		_forget(group_id, key)


## Sweep a disconnecting peer out of any lobby AND out of a live contract,
## mirroring DungeonService. Wired from WorldServer._on_peer_disconnected.
static func on_peer_disconnected(peer_id: int) -> void:
	for key: String in _lobbies.keys():
		var queue: Array = _lobbies[key]
		if not queue.has(peer_id):
			continue
		queue.erase(peer_id)
		_lobbies[key] = queue
		var parts: PackedStringArray = key.rsplit("::", true, 1)
		if WorldServer.curr != null and parts.size() == 2:
			var instance: Node = WorldServer.curr.instance_manager.get_instance_server_by_id(parts[0])
			if instance != null and instance.instance_map != null:
				_broadcast_lobby(instance, parts[1], queue, _lobby_choice.get(key, &""))
	var group_id: int = GroupService.group_of(peer_id)
	if group_id != 0 and _hunts.has(group_id):
		var inst: Node = _hunts[group_id]
		GroupService.leave(peer_id)
		if GroupService.members_of(group_id).is_empty():
			_forget(group_id, str(inst.name) if inst != null else "")


## Drop every trace of a finished/abandoned contract. The now-empty private
## instance is collected by unload_unused_instances.
static func _forget(group_id: int, instance_key: String) -> void:
	var instance: Node = _hunts.get(group_id, null)
	var arena_node: BossHuntArena = _arena_node(instance)
	if arena_node != null:
		arena_node.stop()
	if not instance_key.is_empty():
		_instance_to_group.erase(instance_key)
	_hunts.erase(group_id)
	_end_at_ms.erase(group_id)
	_targets.erase(group_id)
	_kills.erase(group_id)
	_lives.erase(group_id)
	_ejecting.erase(group_id)


# --- arena callbacks ---------------------------------------------------------

## True when [param instance] is a live boss-hunt arena. Read by Player.die to
## keep a death inside the paid arena instead of recalling to the hub.
static func is_hunt_instance(instance: Node) -> bool:
	return instance != null and _instance_to_group.has(str(instance.name))


## True while [param player] is on a contract that still has a life to spend.
## The read-only twin of [method register_hunt_death], for the paths that need to
## know where a death lands WITHOUT charging one — Player.maybe_unstick_death
## stands up a body whose respawn coroutine never finished, and must not bill the
## party a second time for the same death.
static func has_life_left(player: Node) -> bool:
	if player == null or player.player_resource == null:
		return false
	var group_id: int = GroupService.group_of(int(player.player_resource.current_peer_id))
	if group_id == 0 or not _hunts.has(group_id) or _ejecting.get(group_id, false):
		return false
	return _lives.get(group_id, 0) > 0


## A player died on a contract. Spends one of the party's CONTRACT_LIVES; the
## death that spends the LAST one fails the contract for everyone (three lives
## means three deaths, not three plus a free one).
##
## Returns true when the death STAYS in the arena — the caller (Player.die) then
## skips its Guild Hall recall, so the hunter respawns on the entrance pad with
## the clock still running and the party still together. False for a death this
## service does not own, and false for the one that ends the contract: that
## hunter goes home like everyone else, just via _fail_hunt's eject. Server-only.
static func register_hunt_death(player: Node) -> bool:
	if player == null or player.player_resource == null:
		return false
	var group_id: int = GroupService.group_of(int(player.player_resource.current_peer_id))
	if group_id == 0 or not _hunts.has(group_id):
		return false # not on a contract — ordinary open-world death
	if _ejecting.get(group_id, false):
		return false # already failing / wrapping up; a second death changes nothing
	var left: int = maxi(0, _lives.get(group_id, 0) - 1)
	_lives[group_id] = left
	if left <= 0:
		_fail_hunt(group_id)
		return false
	_toast(group_id, "A hunter has fallen. %d %s left on the contract."
		% [left, "life" if left == 1 else "lives"])
	_push_hud(group_id)
	return true


## The contract's lives are spent: it FAILS. Stop the farm loop, stand up anyone
## still at 0 HP so they arrive home alive rather than as a corpse, then eject.
## Whatever already banked into each Hunt Chest is theirs — what is lost is the
## rest of the clock and the fee. Server-only.
static func _fail_hunt(group_id: int) -> void:
	if not _hunts.has(group_id) or WorldServer.curr == null:
		return
	if _ejecting.get(group_id, false):
		return
	_ejecting[group_id] = true # marks the eject non-voluntary (no "Left the hunt" toast)
	var instance: Node = _hunts[group_id]
	var arena_node: BossHuntArena = _arena_node(instance)
	if arena_node != null:
		arena_node.stop()
	var target: BossHuntTarget = _targets.get(group_id, null)
	var kills: int = _kills.get(group_id, 0)
	for peer: int in GroupService.members_of(group_id):
		# Always stand up a downed body: Player.die is mid-await here, and a
		# second death while ejecting would otherwise leave a corpse in the arena.
		var member: Player = instance.get_player(peer) as Player if instance != null else null
		if member != null and member.stats_component.get_stat(Stat.HEALTH) <= 0.0:
			member.revive()
		WorldServer.curr.data_push.rpc_id(peer, &"boss_hunt.failed", {
			"boss": target.title() if target != null else "the boss",
			"kills": kills,
			"eject_in": int(FAIL_EJECT_DELAY_S),
		})
	_hide_hud(group_id) # stop the countdown immediately, ahead of the eject
	WorldServer.curr.get_tree().create_timer(FAIL_EJECT_DELAY_S).timeout.connect(
		func() -> void: _eject_hunt(group_id), CONNECT_ONE_SHOT)


## The arena announced a fresh boss — refresh the party's HUD so the boss name
## and kill count stay current for anyone who joined the view late.
static func on_boss_spawned(instance: Node, _npc: Node) -> void:
	var group_id: int = _instance_to_group.get(str(instance.name), 0) if instance != null else 0
	if group_id != 0:
		_push_hud(group_id)


## A contracted boss died. Bump the tally and re-push the HUD.
static func on_boss_killed(instance: Node, kills: int) -> void:
	var group_id: int = _instance_to_group.get(str(instance.name), 0) if instance != null else 0
	if group_id == 0:
		return
	_kills[group_id] = kills
	_push_hud(group_id)


# --- HUD + chat --------------------------------------------------------------

## Push the countdown HUD (remaining time, boss, kills) to every member.
static func _push_hud(group_id: int) -> void:
	if WorldServer.curr == null:
		return
	var target: BossHuntTarget = _targets.get(group_id, null)
	var payload: Dictionary = {
		"active": true,
		"remaining_s": _remaining_s(group_id),
		"boss": target.title() if target != null else "",
		"kills": _kills.get(group_id, 0),
		"lives": _lives.get(group_id, CONTRACT_LIVES),
	}
	for peer: int in GroupService.members_of(group_id):
		WorldServer.curr.data_push.rpc_id(peer, &"boss_hunt.hud", payload)


static func _hide_hud(group_id: int) -> void:
	if WorldServer.curr == null:
		return
	for peer: int in GroupService.members_of(group_id):
		WorldServer.curr.data_push.rpc_id(peer, &"boss_hunt.hud", {"active": false})


static func _warn(group_id: int, remaining: int) -> void:
	var text: String = "%d seconds left on the contract." % remaining
	if remaining >= 60:
		var minutes: int = int(remaining / 60.0)
		text = "%d minute%s left on the contract." % [minutes, "" if minutes == 1 else "s"]
	_toast(group_id, text)


## One toast line to every member still on the contract — the countdown marks
## and the life-lost notice both ride this.
static func _toast(group_id: int, message: String) -> void:
	if not _hunts.has(group_id) or WorldServer.curr == null:
		return
	for peer: int in GroupService.members_of(group_id):
		WorldServer.curr.data_push.rpc_id(peer, &"boss_hunt.warn", {"message": message})


static func _remaining_s(group_id: int) -> float:
	var end_ms: int = _end_at_ms.get(group_id, 0)
	if end_ms == 0:
		return 0.0
	return maxf(0.0, float(end_ms - Time.get_ticks_msec()) / 1000.0)


# --- helpers -----------------------------------------------------------------

## True when [param station] names a map node that offers a BossHuntInteraction —
## the same resolve-by-node-name trick dungeon stations use (no manual ids).
static func _station_is_broker(instance: Node, station: String) -> bool:
	if instance == null or instance.instance_map == null or station.is_empty():
		return false
	var node: Node = instance.instance_map.get_node_or_null(NodePath(station))
	if node is not NPC or (node as NPC).npc_resource == null:
		return false
	for inter: NPCInteraction in (node as NPC).npc_resource.interactions:
		if inter is BossHuntInteraction:
			return true
	return false


static func _arena_resource() -> InstanceResource:
	if WorldServer.curr == null:
		return null
	return WorldServer.curr.instance_manager.instance_collection.get(ARENA_INSTANCE, null)


## The BossHuntArena node inside a hunt instance's map, or null.
static func _arena_node(instance: Node) -> BossHuntArena:
	if instance == null or instance.instance_map == null:
		return null
	for child: Node in instance.instance_map.get_children():
		if child is BossHuntArena:
			return child as BossHuntArena
	return null


static func _broadcast_lobby(
	instance: Node,
	station: String,
	queue: Array,
	contract_id: StringName
) -> void:
	if WorldServer.curr == null:
		return
	var target: BossHuntTarget = BossHuntCatalog.find(contract_id)
	var payload: Dictionary = {
		"station": station,
		"capacity": PARTY_SIZE,
		"members": _names(instance, queue),
		"selected": String(contract_id),
		"selected_name": target.title() if target != null else "",
		"cost": target.cost if target != null else 0,
	}
	for peer: int in queue:
		WorldServer.curr.data_push.rpc_id(peer, &"boss_hunt.lobby.update", payload)


static func _names(instance: Node, peers: Array) -> Array:
	var out: Array = []
	for peer: int in peers:
		var player: Player = instance.get_player(peer)
		if player != null and player.player_resource != null:
			out.append(player.player_resource.display_name)
	return out


static func _lobby_key(instance_name: String, station: String) -> String:
	return "%s::%s" % [instance_name, station]
