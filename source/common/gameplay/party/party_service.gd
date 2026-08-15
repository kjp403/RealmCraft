class_name PartyService
## Session-scoped overworld PARTIES (max 4). Independent of dungeon GroupService
## so queuing for a run does not dissolve an overworld party. Party members are
## allies (CombatHit.are_allied) regardless of guild, share kill XP when nearby,
## and receive ally heals. Membership is keyed by persistent player_id; disconnect
## drops the seat. Server-authoritative; clients mirror the roster via party.roster.

const MAX_SIZE: int = 4
const INVITE_TTL_MS: int = 60_000
const XP_SHARE_RADIUS: float = 480.0
const HEAL_STEER_RADIUS: float = 280.0

# party_id -> { "members": Array[int] player_ids, "leader": int }
static var _parties: Dictionary[int, Dictionary] = {}
# player_id -> party_id
static var _player_to_party: Dictionary[int, int] = {}
static var _next_party_id: int = 1
# invite_id -> { from, to, expires_ms }
static var _invites: Dictionary[int, Dictionary] = {}
static var _next_invite_id: int = 1


static func are_partied(peer_a: int, peer_b: int) -> bool:
	if peer_a <= 0 or peer_b <= 0 or peer_a == peer_b:
		return false
	var id_a: int = _player_id_of_peer(peer_a)
	var id_b: int = _player_id_of_peer(peer_b)
	if id_a <= 0 or id_b <= 0:
		return false
	var party: int = _player_to_party.get(id_a, 0)
	return party != 0 and party == _player_to_party.get(id_b, 0)


static func party_of_player(player_id: int) -> int:
	return _player_to_party.get(player_id, 0)


static func party_of_peer(peer_id: int) -> int:
	return party_of_player(_player_id_of_peer(peer_id))


static func members_of(party_id: int) -> Array:
	return _parties.get(party_id, {}).get("members", [])


static func leader_of(party_id: int) -> int:
	return int(_parties.get(party_id, {}).get("leader", 0))


static func is_leader(player_id: int) -> bool:
	var party_id: int = party_of_player(player_id)
	return party_id != 0 and leader_of(party_id) == player_id


## Nearby living party members of [param player] (same instance, within radius).
## Does not include [param player] itself.
static func nearby_members(player: Player, radius: float) -> Array[Player]:
	var out: Array[Player] = []
	if player == null or player.player_resource == null:
		return out
	var party_id: int = party_of_player(int(player.player_resource.player_id))
	if party_id == 0:
		return out
	var container: Node = player.get_parent()
	if container == null:
		return out
	for node: Node in container.get_children():
		if node == player or node is not Player:
			continue
		var other: Player = node as Player
		if other.is_dead or other.player_resource == null:
			continue
		if party_of_player(int(other.player_resource.player_id)) != party_id:
			continue
		if player.global_position.distance_to(other.global_position) <= radius:
			out.append(other)
	return out


static func most_wounded_nearby(caster: Player, radius: float) -> Player:
	var best: Player = null
	var best_missing: float = 0.0
	for other: Player in nearby_members(caster, radius):
		var sc: StatsComponent = other.stats_component
		if sc == null:
			continue
		var hp: float = sc.get_stat(Stat.HEALTH)
		var hp_max: float = sc.get_stat(Stat.HEALTH_MAX)
		var missing: float = hp_max - hp
		if missing > best_missing:
			best_missing = missing
			best = other
	return best


static func invite(from_peer: int, target_player_id: int) -> Dictionary:
	var from: PlayerResource = _resource_of_peer(from_peer)
	if from == null:
		return {"ok": false, "reason": "no_player"}
	if target_player_id <= 0 or target_player_id == from.player_id:
		return {"ok": false, "reason": "invalid"}
	if WorldServer.curr == null:
		return {"ok": false, "reason": "offline"}
	var target_peer: int = int(WorldServer.curr.player_id_to_peer_id.get(target_player_id, 0))
	if target_peer <= 0:
		return {"ok": false, "reason": "offline"}
	var target: PlayerResource = WorldServer.curr.connected_players.get(target_peer)
	if target == null:
		return {"ok": false, "reason": "offline"}
	if party_of_player(target_player_id) != 0:
		return {"ok": false, "reason": "in_party"}
	var party_id: int = party_of_player(from.player_id)
	if party_id != 0 and members_of(party_id).size() >= MAX_SIZE:
		return {"ok": false, "reason": "full"}
	if party_id != 0 and not is_leader(from.player_id):
		return {"ok": false, "reason": "not_leader"}
	_expire_invites()
	for invite_id: int in _invites.keys():
		var existing: Dictionary = _invites[invite_id]
		if int(existing.get("from", 0)) == from.player_id \
				and int(existing.get("to", 0)) == target_player_id:
			return {"ok": true, "invite": invite_id, "resent": true}
	var invite_id: int = _next_invite_id
	_next_invite_id += 1
	_invites[invite_id] = {
		"from": from.player_id,
		"to": target_player_id,
		"expires_ms": Time.get_ticks_msec() + INVITE_TTL_MS,
	}
	WorldServer.curr.data_push.rpc_id(target_peer, &"notification", {
		"topic": "party.invite",
		"invite": invite_id,
		"from_name": from.display_name,
		"from_id": from.player_id,
	})
	return {"ok": true, "invite": invite_id}


static func respond(peer_id: int, invite_id: int, accepted: bool) -> Dictionary:
	_expire_invites()
	var invite: Dictionary = _invites.get(invite_id, {})
	if invite.is_empty():
		return {"ok": false, "reason": "expired"}
	var accepter: PlayerResource = _resource_of_peer(peer_id)
	if accepter == null or int(invite.get("to", 0)) != accepter.player_id:
		return {"ok": false, "reason": "not_yours"}
	_invites.erase(invite_id)
	var from_id: int = int(invite.get("from", 0))
	var from_peer: int = _peer_of_player(from_id)
	if not accepted:
		if from_peer > 0 and WorldServer.curr != null:
			WorldServer.curr.data_push.rpc_id(from_peer, &"party.invite_result", {
				"accepted": false,
				"reason": "declined",
				"name": accepter.display_name,
			})
		return {"ok": true, "accepted": false}
	if party_of_player(accepter.player_id) != 0:
		return {"ok": false, "reason": "in_party"}
	if from_peer <= 0:
		return {"ok": false, "reason": "offline"}
	var from: PlayerResource = _resource_of_peer(from_peer)
	if from == null:
		return {"ok": false, "reason": "offline"}
	var party_id: int = party_of_player(from.player_id)
	if party_id == 0:
		party_id = _create_party(from.player_id)
	if members_of(party_id).size() >= MAX_SIZE:
		return {"ok": false, "reason": "full"}
	_attach(accepter.player_id, party_id)
	_broadcast_roster(party_id)
	_toast_party(party_id, "%s joined the party." % accepter.display_name)
	return {"ok": true, "accepted": true, "party": party_id}


static func leave(peer_id: int) -> Dictionary:
	var res: PlayerResource = _resource_of_peer(peer_id)
	if res == null:
		return {"ok": false, "reason": "no_player"}
	var party_id: int = party_of_player(res.player_id)
	if party_id == 0:
		return {"ok": false, "reason": "not_in_party"}
	_remove_member(res.player_id, "%s left the party." % res.display_name)
	return {"ok": true}


static func kick(leader_peer: int, target_player_id: int) -> Dictionary:
	var leader: PlayerResource = _resource_of_peer(leader_peer)
	if leader == null:
		return {"ok": false, "reason": "no_player"}
	if not is_leader(leader.player_id):
		return {"ok": false, "reason": "not_leader"}
	var party_id: int = party_of_player(leader.player_id)
	if party_id == 0 or party_of_player(target_player_id) != party_id:
		return {"ok": false, "reason": "not_in_party"}
	if target_player_id == leader.player_id:
		return {"ok": false, "reason": "self"}
	var name: String = _display_name(target_player_id)
	_remove_member(target_player_id, "%s was removed from the party." % name)
	return {"ok": true}


static func on_peer_disconnected(peer_id: int) -> void:
	# Takeover detaches the resource first — keep the party seat so the new
	# session re-joins the same roster. A true logout still has the resource.
	var res: PlayerResource = _resource_of_peer(peer_id)
	if res == null:
		return
	var name: String = res.display_name
	_remove_member(res.player_id, "%s left the party." % name)
	_drop_invites_for_player(res.player_id)


static func on_spawn(peer_id: int) -> void:
	var party_id: int = party_of_peer(peer_id)
	if party_id != 0:
		_broadcast_roster(party_id)


static func snapshot_for(peer_id: int) -> Dictionary:
	var res: PlayerResource = _resource_of_peer(peer_id)
	if res == null:
		return {"members": [], "leader": 0}
	var party_id: int = party_of_player(res.player_id)
	if party_id == 0:
		return {"members": [], "leader": 0}
	return _roster_payload(party_id)


static func _create_party(leader_id: int) -> int:
	var party_id: int = _next_party_id
	_next_party_id += 1
	_parties[party_id] = {"members": [leader_id], "leader": leader_id}
	_player_to_party[leader_id] = party_id
	return party_id


static func _attach(player_id: int, party_id: int) -> void:
	_detach(player_id)
	var members: Array = members_of(party_id)
	if not members.has(player_id):
		members.append(player_id)
	_player_to_party[player_id] = party_id


static func _detach(player_id: int) -> void:
	var party_id: int = _player_to_party.get(player_id, 0)
	if party_id == 0:
		return
	_player_to_party.erase(player_id)
	var members: Array = members_of(party_id)
	var idx: int = members.find(player_id)
	if idx != -1:
		members.remove_at(idx)


static func _remove_member(player_id: int, message: String) -> void:
	var party_id: int = party_of_player(player_id)
	if party_id == 0:
		return
	var was_leader: bool = is_leader(player_id)
	_detach(player_id)
	_push_roster_to_player(player_id, {"members": [], "leader": 0, "names": []})
	var remaining: Array = members_of(party_id)
	if remaining.is_empty():
		_parties.erase(party_id)
		return
	if was_leader:
		_parties[party_id]["leader"] = int(remaining[0])
	_broadcast_roster(party_id)
	if not message.is_empty():
		_toast_party(party_id, message)
	var leaver_peer: int = _peer_of_player(player_id)
	if leaver_peer > 0 and WorldServer.curr != null and not message.is_empty():
		WorldServer.curr.data_push.rpc_id(leaver_peer, &"party.notice", {"text": message})


static func _broadcast_roster(party_id: int) -> void:
	var payload: Dictionary = _roster_payload(party_id)
	for player_id: int in members_of(party_id):
		_push_roster_to_player(player_id, payload)


static func _roster_payload(party_id: int) -> Dictionary:
	var member_ids: Array = members_of(party_id)
	var peers: Array = []
	var names: Array = []
	for player_id: int in member_ids:
		var peer: int = _peer_of_player(player_id)
		if peer > 0:
			peers.append(peer)
		names.append({
			"id": player_id,
			"peer_id": peer,
			"name": _display_name(player_id),
			"leader": player_id == leader_of(party_id),
		})
	return {
		"members": peers,
		"leader": _peer_of_player(leader_of(party_id)),
		"names": names,
	}


static func _push_roster_to_player(player_id: int, payload: Dictionary) -> void:
	if WorldServer.curr == null:
		return
	var peer_id: int = _peer_of_player(player_id)
	if peer_id <= 0:
		return
	var mp: MultiplayerAPI = WorldServer.curr.multiplayer
	if mp == null or not mp.has_multiplayer_peer() or peer_id not in mp.get_peers():
		return
	WorldServer.curr.data_push.rpc_id(peer_id, &"party.roster", payload)


static func _toast_party(party_id: int, text: String) -> void:
	if WorldServer.curr == null or text.is_empty():
		return
	for player_id: int in members_of(party_id):
		var peer: int = _peer_of_player(player_id)
		if peer > 0:
			WorldServer.curr.data_push.rpc_id(peer, &"party.notice", {"text": text})


static func _expire_invites() -> void:
	var now: int = Time.get_ticks_msec()
	for invite_id: int in _invites.keys():
		if int(_invites[invite_id].get("expires_ms", 0)) <= now:
			_invites.erase(invite_id)


static func _drop_invites_for_player(player_id: int) -> void:
	for invite_id: int in _invites.keys():
		var invite: Dictionary = _invites[invite_id]
		if int(invite.get("from", 0)) == player_id or int(invite.get("to", 0)) == player_id:
			_invites.erase(invite_id)


static func _player_id_of_peer(peer_id: int) -> int:
	if peer_id <= 0 or WorldServer.curr == null:
		return 0
	var res: PlayerResource = WorldServer.curr.connected_players.get(peer_id)
	if res == null:
		return 0
	return int(res.player_id)


static func _peer_of_player(player_id: int) -> int:
	if player_id <= 0 or WorldServer.curr == null:
		return 0
	return int(WorldServer.curr.player_id_to_peer_id.get(player_id, 0))


static func _resource_of_peer(peer_id: int) -> PlayerResource:
	if peer_id <= 0 or WorldServer.curr == null:
		return null
	return WorldServer.curr.connected_players.get(peer_id)


static func _display_name(player_id: int) -> String:
	var peer: int = _peer_of_player(player_id)
	var res: PlayerResource = _resource_of_peer(peer)
	if res != null:
		return res.display_name
	if WorldServer.curr != null and WorldServer.curr.database != null:
		var name: String = WorldServer.curr.database.store.get_player_display_name(player_id)
		if not name.is_empty():
			return name
	return "Player"
