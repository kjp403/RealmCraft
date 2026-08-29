class_name OssuranGateService
## The ready-up lobby behind the Ossuran portal (Fire Forge). A player walks into
## the portal, the client opens the gate panel, and everyone standing at the
## portal readies up; the leader Enters and the whole party is moved together into
## a FRESH private copy of `ossuran_arena` — never the shared charged instance.
##
## Trimmed from BossHuntService's lobby: no gold, no clock, no board. Just
## join / leave / ready / start + a private instance. Server-only (static state).

## The arena the portal leads into.
const ARENA_INSTANCE: StringName = &"ossuran_arena"
## Arrival warper id inside ossuran_arena.tscn (the portal's target_id).
const ARENA_ENTRANCE_ID: int = 58
## Max party for one run.
const PARTY_SIZE: int = 5
## How close to the portal a player must be to act on the lobby.
const PORTAL_RANGE: float = 220.0
## The portal node's name in fire_forge.tscn — used for the range check.
const PORTAL_NODE: String = "OssuranPortal"

## fire_forge instance name -> { members: Array[int], ready: Dictionary[int, bool], leader: int }
static var _lobbies: Dictionary = {}
## Live private arena instance name -> group_id, so on_player_left / disconnect
## can dissolve the co-op group when its run empties (and the instance can free).
static var _groups: Dictionary = {}


## Entry point for the `ossuran.gate` request handler. Returns a lobby snapshot
## for the caller, or {ok:false, reason} on a rejected action.
static func handle_request(instance: Node, peer_id: int, action: String) -> Dictionary:
	if instance == null or WorldServer.curr == null:
		return {"ok": false, "reason": "no_server"}
	var player: Player = instance.get_player(peer_id) as Player
	if player == null:
		return {"ok": false, "reason": "no_player"}
	if GroupService.group_of(peer_id) != 0:
		return {"ok": false, "reason": "in_run"}

	var portal: Node2D = instance.instance_map.get_node_or_null(NodePath(PORTAL_NODE)) as Node2D
	if portal != null and player.global_position.distance_to(portal.global_position) > PORTAL_RANGE:
		return {"ok": false, "reason": "too_far"}

	var key: String = str(instance.name)
	var lobby: Dictionary = _prune(instance, _lobbies.get(key, _fresh_lobby()))
	var members: Array = lobby["members"]
	var ready: Dictionary = lobby["ready"]

	match action:
		"join":
			if not members.has(peer_id):
				if members.size() >= PARTY_SIZE:
					return {"ok": false, "reason": "full"}
				members.append(peer_id)
				ready[peer_id] = false
				if members.size() == 1:
					lobby["leader"] = peer_id
		"leave":
			_remove(lobby, peer_id)
		"ready":
			if not members.has(peer_id):
				return {"ok": false, "reason": "not_in_lobby"}
			ready[peer_id] = true
		"unready":
			if members.has(peer_id):
				ready[peer_id] = false
		"start":
			if lobby["leader"] != peer_id:
				return {"ok": false, "reason": "not_leader"}
			if members.is_empty():
				return {"ok": false, "reason": "empty"}
			for m: int in members:
				if not bool(ready.get(m, false)):
					return {"ok": false, "reason": "not_ready"}
			var party: Array = members.duplicate()
			_lobbies.erase(key)
			if not _enter(party):
				return {"ok": false, "reason": "no_arena",
					"message": "Ossuran's Ruin would not open. Try again."}
			return {"ok": true, "started": true}
		_:
			return {"ok": false, "reason": "bad_action"}

	if members.is_empty():
		_lobbies.erase(key)
	else:
		_lobbies[key] = lobby
	_broadcast(instance, key)
	return _snapshot(instance, key, peer_id)


## Disconnect sweep — called from world_server alongside the other lobby
## services. Drops the peer from any gate lobby AND from a live Ossuran group.
static func on_peer_disconnected(peer_id: int) -> void:
	for key: String in _lobbies.keys():
		var lobby: Dictionary = _lobbies[key]
		if lobby["members"].has(peer_id):
			_remove(lobby, peer_id)
			if lobby["members"].is_empty():
				_lobbies.erase(key)
			# No _broadcast here — the disconnect sweep has no live instance
			# handle; the next interaction re-snapshots.
	var group_id: int = GroupService.group_of(peer_id)
	if group_id != 0 and _groups.values().has(group_id):
		GroupService.leave(peer_id)
		if GroupService.members_of(group_id).is_empty():
			_forget_group(group_id)


## A peer left an Ossuran run instance (exit warp, death return, recall, jail).
## Wired from InstanceManager.player_switch_instance. No-op for any other map.
static func on_player_left(peer_id: int, left_instance: Node) -> void:
	if left_instance == null:
		return
	var group_id: int = _groups.get(str(left_instance.name), 0)
	if group_id == 0:
		return
	GroupService.leave(peer_id)
	if GroupService.members_of(group_id).is_empty():
		_forget_group(group_id)


static func _forget_group(group_id: int) -> void:
	for key: String in _groups.keys():
		if _groups[key] == group_id:
			_groups.erase(key)
	GroupService.dissolve(group_id)


# --- internals -------------------------------------------------------------

static func _fresh_lobby() -> Dictionary:
	return {"members": [], "ready": {}, "leader": 0}


## Strip members who have left the instance, and keep the leader valid.
static func _prune(instance: Node, lobby: Dictionary) -> Dictionary:
	var members: Array = lobby["members"]
	var ready: Dictionary = lobby["ready"]
	for m: int in members.duplicate():
		if instance.get_player(m) == null or GroupService.group_of(m) != 0:
			members.erase(m)
			ready.erase(m)
	if not members.has(lobby.get("leader", 0)):
		lobby["leader"] = members[0] if not members.is_empty() else 0
	return lobby


static func _remove(lobby: Dictionary, peer_id: int) -> void:
	lobby["members"].erase(peer_id)
	lobby["ready"].erase(peer_id)
	if lobby.get("leader", 0) == peer_id:
		lobby["leader"] = lobby["members"][0] if not lobby["members"].is_empty() else 0


## Snapshot for one caller (the request response).
static func _snapshot(instance: Node, key: String, peer_id: int) -> Dictionary:
	var lobby: Dictionary = _lobbies.get(key, _fresh_lobby())
	var members: Array = lobby["members"]
	var ready: Dictionary = lobby["ready"]
	var roster: Array = []
	for m: int in members:
		var p: Player = instance.get_player(m) as Player
		roster.append({
			"name": p.player_resource.display_name if p != null and p.player_resource != null else "?",
			"ready": bool(ready.get(m, false)),
			"leader": lobby.get("leader", 0) == m,
		})
	return {
		"ok": true,
		"capacity": PARTY_SIZE,
		"in_lobby": members.has(peer_id),
		"is_leader": lobby.get("leader", 0) == peer_id,
		"all_ready": not members.is_empty() and members.all(func(m: int) -> bool: return bool(ready.get(m, false))),
		"members": roster,
	}


## Push the snapshot to every lobby member.
static func _broadcast(instance: Node, key: String) -> void:
	if WorldServer.curr == null:
		return
	var lobby: Dictionary = _lobbies.get(key, null)
	if lobby == null:
		return
	for m: int in lobby["members"]:
		WorldServer.curr.data_push.rpc_id(m, &"ossuran.gate.update", _snapshot(instance, key, m))


## The shared arena InstanceResource from the collection (its charged_instances
## list is where prepare_instance appends the fresh private copy).
static func _arena_resource() -> InstanceResource:
	if WorldServer.curr == null:
		return null
	return WorldServer.curr.instance_manager.instance_collection.get(ARENA_INSTANCE, null)


## Form the group, spin a FRESH private arena, move everyone in once it loads.
static func _enter(members: Array) -> bool:
	var arena: InstanceResource = _arena_resource()
	if arena == null or members.is_empty():
		return false
	var clean: Array = []
	for m: Variant in members:
		if int(m) > 0 and not clean.has(int(m)):
			clean.append(int(m))
	if clean.is_empty():
		return false

	var group_id: int = GroupService.create_group(clean, clean[0])
	var instance_manager: Node = WorldServer.curr.instance_manager
	var instance: Node = instance_manager.prepare_instance(arena)
	# Keyed in _move_in (after add_child, so instance.name is final). The gap
	# before ready is a few frames where nobody can leave yet.
	instance.ready.connect(func() -> void: _move_in(instance, clean, group_id), CONNECT_ONE_SHOT)
	instance_manager.add_child(instance, true)
	return true


static func _move_in(instance: Node, members: Array, group_id: int) -> void:
	if instance == null or WorldServer.curr == null:
		return
	_groups[str(instance.name)] = group_id
	var instance_manager: Node = WorldServer.curr.instance_manager
	for peer: int in members:
		var current: Node = instance_manager.find_instance_for_peer(peer)
		if current == null:
			continue
		var player: Player = current.get_player(peer) as Player
		if player != null:
			instance_manager.player_switch_instance(instance, ARENA_ENTRANCE_ID, player, current)
			player.restore_full() # enter the hardest fight in the game topped up
	# Delayed so it lands after the clients finish loading the arena.
	WorldServer.curr.get_tree().create_timer(1.5).timeout.connect(
		func() -> void:
			for peer: int in members:
				WorldServer.curr.data_push.rpc_id(peer, &"ossuran.gate.entered", {})
	, CONNECT_ONE_SHOT)
