class_name TradeService
## Server-authoritative private player-to-player trade sessions.
##
## Invitations expire, both participants must remain nearby in the same instance,
## every offer change clears both confirmations, and both inventories are rechecked
## immediately before a single in-memory exchange + database transaction.

const INVITE_TTL_MS: int = 30_000
const CONFIRM_COUNTDOWN_MS: int = 5_000
const INVITE_DISTANCE: float = 128.0
const SESSION_DISTANCE: float = 192.0
const MAX_OFFER_ITEMS: int = 6

static var _next_invite_id: int = 1
static var _next_session_id: int = 1
static var _invites: Dictionary[int, Dictionary] = {}
static var _sessions: Dictionary[int, Dictionary] = {}


static func request_trade(
	peer_id: int,
	instance: ServerInstance,
	target_peer_id: int
) -> Dictionary:
	_purge_expired_invites()
	if peer_id <= 0 or target_peer_id <= 0 or peer_id == target_peer_id:
		return {"ok": false, "reason": "invalid"}
	var actor: Player = instance.players_by_peer_id.get(peer_id, null)
	var target: Player = instance.players_by_peer_id.get(target_peer_id, null)
	if actor == null or target == null:
		return {"ok": false, "reason": "unavailable"}
	if actor.is_dead or target.is_dead or actor.is_in_combat() or target.is_in_combat():
		return {"ok": false, "reason": "combat"}
	if actor.global_position.distance_to(target.global_position) > INVITE_DISTANCE:
		return {"ok": false, "reason": "too_far"}
	if _session_for_peer(peer_id) > 0 or _session_for_peer(target_peer_id) > 0:
		return {"ok": false, "reason": "busy"}
	if _has_pending_invite(peer_id) or _has_pending_invite(target_peer_id):
		return {"ok": false, "reason": "busy"}

	var invite_id: int = _next_invite_id
	_next_invite_id += 1
	_invites[invite_id] = {
		"from": peer_id,
		"to": target_peer_id,
		"instance_id": instance.get_instance_id(),
		"expires": Time.get_ticks_msec() + INVITE_TTL_MS,
	}
	_push(target_peer_id, &"trade.invite", {
		"invite": invite_id,
		"from_peer": peer_id,
		"from_name": actor.display_name,
		"expires_in": int(INVITE_TTL_MS / 1000),
	})
	_expire_invite_after_ttl(instance.get_tree(), invite_id)
	return {"ok": true, "invite": invite_id}


static func respond_to_invite(
	peer_id: int,
	instance: ServerInstance,
	invite_id: int,
	accepted: bool
) -> Dictionary:
	_purge_expired_invites()
	var invite: Dictionary = _invites.get(invite_id, {})
	if invite.is_empty() or int(invite.get("to", 0)) != peer_id:
		return {"ok": false, "reason": "expired"}
	_invites.erase(invite_id)
	var from_peer: int = int(invite.get("from", 0))
	var recipient: Player = instance.players_by_peer_id.get(peer_id, null)
	var requester: Player = instance.players_by_peer_id.get(from_peer, null)
	if not accepted:
		_push(from_peer, &"trade.invite_result", {
			"accepted": false,
			"reason": "declined",
			"name": recipient.display_name if recipient != null else "Player",
		})
		return {"ok": true, "accepted": false}
	if int(invite.get("instance_id", 0)) != instance.get_instance_id() \
			or requester == null or recipient == null:
		_notify_invite_failed(from_peer, "unavailable")
		return {"ok": false, "reason": "unavailable"}
	if requester.is_dead or recipient.is_dead \
			or requester.is_in_combat() or recipient.is_in_combat():
		_notify_invite_failed(from_peer, "combat")
		return {"ok": false, "reason": "combat"}
	if requester.global_position.distance_to(recipient.global_position) > INVITE_DISTANCE:
		_notify_invite_failed(from_peer, "too_far")
		return {"ok": false, "reason": "too_far"}
	if _session_for_peer(from_peer) > 0 or _session_for_peer(peer_id) > 0:
		_notify_invite_failed(from_peer, "busy")
		return {"ok": false, "reason": "busy"}

	_erase_invites_for_peer(from_peer)
	_erase_invites_for_peer(peer_id)
	var trade_id: int = _next_session_id
	_next_session_id += 1
	_sessions[trade_id] = {
		"instance_id": instance.get_instance_id(),
		"peers": [from_peer, peer_id],
		"offers": [_empty_offer(), _empty_offer()],
		"accepted": [false, false],
		"locked": false,
		"revision": 0,
		"countdown_until": 0,
	}
	for participant_peer: int in [from_peer, peer_id]:
		var other_peer: int = peer_id if participant_peer == from_peer else from_peer
		var other: Player = instance.players_by_peer_id.get(other_peer, null)
		_push(participant_peer, &"trade.open", {
			"trade": trade_id,
			"name": other.display_name if other != null else "Player",
		})
	_broadcast(instance, trade_id)
	return {"ok": true, "accepted": true, "trade": trade_id}


static func state_for(
	peer_id: int,
	instance: ServerInstance,
	trade_id: int
) -> Dictionary:
	var session: Dictionary = _valid_session(peer_id, instance, trade_id)
	if session.is_empty():
		return {}
	return _build_session_state(instance, trade_id, session)


static func set_offer(
	peer_id: int,
	instance: ServerInstance,
	trade_id: int,
	requested_items: Dictionary,
	requested_gold: int
) -> Dictionary:
	var session: Dictionary = _valid_session(peer_id, instance, trade_id)
	if session.is_empty():
		return {"ok": false, "reason": "missing"}
	if bool(session.get("locked", false)):
		return {"ok": false, "reason": "locked"}
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null:
		return {"ok": false, "reason": "missing"}
	var inventory: Dictionary = player.player_resource.inventory
	var items: Dictionary = {}
	for raw_id: Variant in requested_items:
		var item_id: int = int(raw_id)
		var amount: int = int(requested_items[raw_id])
		if item_id <= 0 or amount <= 0 or item_id == Economy.gold_id():
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item == null or not item.can_trade:
			return {"ok": false, "reason": "untradeable"}
		if Inventory.count(inventory, item_id) < amount:
			return {"ok": false, "reason": "items"}
		items[item_id] = amount
	if items.size() > MAX_OFFER_ITEMS:
		return {"ok": false, "reason": "too_many"}
	var gold: int = maxi(0, requested_gold)
	if Inventory.count(inventory, Economy.gold_id()) < gold:
		return {"ok": false, "reason": "gold"}

	var index: int = _peer_index(session, peer_id)
	var offers: Array = session["offers"]
	offers[index] = {"items": items, "gold": gold}
	session["offers"] = offers
	session["accepted"] = [false, false]
	session["revision"] = int(session.get("revision", 0)) + 1
	session["countdown_until"] = 0
	_sessions[trade_id] = session
	_broadcast(instance, trade_id)
	return {"ok": true}


static func set_accepted(
	peer_id: int,
	instance: ServerInstance,
	trade_id: int,
	accepted: bool
) -> Dictionary:
	var session: Dictionary = _valid_session(peer_id, instance, trade_id)
	if session.is_empty():
		return {"ok": false, "reason": "missing"}
	if bool(session.get("locked", false)):
		return {"ok": false, "reason": "locked"}
	var flags: Array = session["accepted"]
	flags[_peer_index(session, peer_id)] = accepted
	session["accepted"] = flags
	session["revision"] = int(session.get("revision", 0)) + 1
	if bool(flags[0]) and bool(flags[1]):
		session["locked"] = true
		session["countdown_until"] = (
			Time.get_ticks_msec() + CONFIRM_COUNTDOWN_MS
		)
	if bool(session.get("locked", false)):
		# Decline BEFORE the countdown starts when either bag is too small for what
		# it is about to receive. The swap itself used to add straight past capacity,
		# so a 15-slot offer into 10 free squares completed and the overflow was gone.
		var blocked: Array = _peers_without_room(instance, session)
		if not blocked.is_empty():
			_close_full_inventory(instance, trade_id, blocked)
			return {"ok": false, "reason": "inventory_full"}

	_sessions[trade_id] = session
	_broadcast(instance, trade_id)
	if bool(session.get("locked", false)):
		_complete_after_countdown(
			instance,
			trade_id,
			int(session["revision"])
		)
	return {"ok": true}


static func leave(
	peer_id: int,
	instance: ServerInstance,
	trade_id: int
) -> Dictionary:
	var session: Dictionary = _valid_session(peer_id, instance, trade_id)
	if session.is_empty():
		return {"ok": true}
	_close_session(instance, trade_id, "The other player cancelled the trade.")
	return {"ok": true}


static func on_peer_left(instance: ServerInstance, peer_id: int) -> void:
	_erase_invites_for_peer(peer_id)
	var trade_id: int = _session_for_peer(peer_id)
	if trade_id > 0:
		_close_session(instance, trade_id, "The other player left the area.")


static func _complete_after_countdown(
	instance: ServerInstance,
	trade_id: int,
	revision: int
) -> void:
	await instance.get_tree().create_timer(
		float(CONFIRM_COUNTDOWN_MS) / 1000.0
	).timeout
	if not is_instance_valid(instance) or not _sessions.has(trade_id):
		return
	var session: Dictionary = _sessions[trade_id]
	if int(session.get("revision", -1)) != revision \
			or not bool(session.get("locked", false)):
		return
	var peers: Array = session["peers"]
	var first: Player = instance.players_by_peer_id.get(int(peers[0]), null)
	var second: Player = instance.players_by_peer_id.get(int(peers[1]), null)
	if not _participants_can_finish(first, second, session):
		_close_session(instance, trade_id, "Trade failed because the offer changed or a player moved away.")
		return

	# Space can vanish during the 5s countdown (a chest opened, loot picked up), so
	# the last word on capacity is here, immediately before the exchange.
	var blocked: Array = _peers_without_room(instance, session)
	if not blocked.is_empty():
		_close_full_inventory(instance, trade_id, blocked)
		return

	var offers: Array = session["offers"]
	var received: Array = [
		_describe_offer(offers[1]),
		_describe_offer(offers[0]),
	]
	var first_inventory: Dictionary = first.player_resource.inventory
	var second_inventory: Dictionary = second.player_resource.inventory
	var first_snapshot: Dictionary = first_inventory.duplicate(true)
	var second_snapshot: Dictionary = second_inventory.duplicate(true)
	var store: WorldStoreSqlite = instance.world_server.database.store
	if not store.begin():
		push_error(
			"Trade %d could not begin persistence: %s" % [
				trade_id,
				store.db.error_message,
			]
		)
		_fail_completion(trade_id, peers, "persistence")
		return
	_transfer_offer(
		first_inventory,
		second_inventory,
		second.player_resource,
		offers[0]
	)
	_transfer_offer(
		second_inventory,
		first_inventory,
		first.player_resource,
		offers[1]
	)

	# Persist both players in one transaction. A failed statement or COMMIT restores
	# both in-memory inventories before reporting failure, so neither side can keep
	# half an exchange or reconnect into a different result.
	var persisted: bool = store.save_player(first.player_resource)
	if persisted:
		persisted = store.save_player(second.player_resource)
	if persisted:
		persisted = store.commit()
	if not persisted:
		var persistence_error: String = store.db.error_message
		store.rollback()
		first.player_resource.inventory = first_snapshot
		second.player_resource.inventory = second_snapshot
		push_error(
			"Trade %d rolled back after persistence failure: %s" % [
				trade_id,
				persistence_error,
			]
		)
		_fail_completion(trade_id, peers, "persistence")
		return

	_sessions.erase(trade_id)
	for i: int in 2:
		_push(int(peers[i]), &"trade.result", {
			"ok": true,
			"trade": trade_id,
			"received": received[i],
		})


static func _fail_completion(
	trade_id: int,
	peers: Array,
	reason: String
) -> void:
	_sessions.erase(trade_id)
	for raw_peer: Variant in peers:
		_push(int(raw_peer), &"trade.result", {
			"ok": false,
			"trade": trade_id,
			"reason": reason,
		})


static func _participants_can_finish(
	first: Player,
	second: Player,
	session: Dictionary
) -> bool:
	if first == null or second == null:
		return false
	if first.is_dead or second.is_dead or first.is_in_combat() or second.is_in_combat():
		return false
	if first.global_position.distance_to(second.global_position) > SESSION_DISTANCE:
		return false
	var offers: Array = session["offers"]
	return (
		_can_afford(first.player_resource.inventory, offers[0])
		and _can_afford(second.player_resource.inventory, offers[1])
	)


## Which participants cannot hold what the other side is offering them. Returns
## rows of { "index", "peer", "name", "missing" } — empty when the swap fits both
## bags. Each side is measured against the inventory it will have AFTER its own
## offer leaves, so trading 15 slots for 15 slots is not reported as full.
static func _peers_without_room(
	instance: ServerInstance,
	session: Dictionary
) -> Array:
	var peers: Array = session.get("peers", [])
	var offers: Array = session.get("offers", [])
	if peers.size() < 2 or offers.size() < 2:
		return []
	var blocked: Array = []
	for i: int in 2:
		var peer_id: int = int(peers[i])
		var player: Player = instance.players_by_peer_id.get(peer_id, null)
		if player == null or player.player_resource == null:
			continue
		var resource: PlayerResource = player.player_resource
		var missing: int = InventorySpace.missing_slots_for(
			resource.inventory,
			offers[1 - i].get("items", {}),
			offers[i].get("items", {}),
			resource.active_inventory_bag,
			resource.inventory_bags
		)
		if missing > 0:
			blocked.append({
				"index": i,
				"peer": peer_id,
				"name": player.display_name,
				"missing": missing,
			})
	return blocked


## Close a trade that would have overflowed a bag, telling each side whose bag is
## the problem — the player who is full gets "free up N slots", their partner gets
## the name, so neither is left guessing why nothing happened.
static func _close_full_inventory(
	instance: ServerInstance,
	trade_id: int,
	blocked: Array
) -> void:
	var session: Dictionary = _sessions.get(trade_id, {})
	if session.is_empty():
		return
	var peers: Array = session.get("peers", [])
	var reasons: Array = ["", ""]
	for row: Dictionary in blocked:
		var index: int = int(row["index"])
		var missing: int = int(row["missing"])
		var slots: String = "slot" if missing == 1 else "slots"
		reasons[index] = (
			"Trade declined — your inventory is too full. Free up %d more %s."
			% [missing, slots]
		)
		var other: int = 1 - index
		if reasons[other].is_empty():
			reasons[other] = (
				"Trade declined — %s doesn't have enough inventory space (needs %d more %s)."
				% [str(row["name"]), missing, slots]
			)
	_sessions.erase(trade_id)
	for i: int in peers.size():
		var reason: String = str(reasons[i]) if i < reasons.size() else ""
		_push(int(peers[i]), &"trade.closed", {
			"trade": trade_id,
			"reason": reason if not reason.is_empty() else "Trade declined — an inventory was too full.",
		})


static func _can_afford(inventory: Dictionary, offer: Dictionary) -> bool:
	if Inventory.count(inventory, Economy.gold_id()) < int(offer.get("gold", 0)):
		return false
	var items: Dictionary = offer.get("items", {})
	for raw_id: Variant in items:
		var item_id: int = int(raw_id)
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item == null or not item.can_trade \
				or Inventory.count(inventory, item_id) < int(items[raw_id]):
			return false
	return true


## [param to_resource] owns [param to_inventory] — needed so received items land
## in the RECEIVER's active bag and overflow through their unlocked bags.
static func _transfer_offer(
	from_inventory: Dictionary,
	to_inventory: Dictionary,
	to_resource: PlayerResource,
	offer: Dictionary
) -> void:
	var to_bag: int = to_resource.active_inventory_bag if to_resource != null else 0
	var to_bags: int = to_resource.inventory_bags if to_resource != null else 1
	var gold: int = int(offer.get("gold", 0))
	if gold > 0:
		Inventory.remove_amount_by_id(from_inventory, Economy.gold_id(), gold)
		Inventory.add_item(to_inventory, Economy.gold_id(), gold, false, to_bag, to_bags)
	var items: Dictionary = offer.get("items", {})
	for raw_id: Variant in items:
		var item_id: int = int(raw_id)
		var amount: int = int(items[raw_id])
		Inventory.remove_amount_by_id(from_inventory, item_id, amount)
		for _copy: int in amount:
			Inventory.add_item(to_inventory, item_id, 1, false, to_bag, to_bags)


static func _broadcast(instance: ServerInstance, trade_id: int) -> void:
	var session: Dictionary = _sessions.get(trade_id, {})
	if session.is_empty():
		return
	var state: Dictionary = _build_session_state(instance, trade_id, session)
	for raw_peer: Variant in session["peers"]:
		_push(int(raw_peer), &"trade.state", state)


static func _build_session_state(
	instance: ServerInstance,
	trade_id: int,
	session: Dictionary
) -> Dictionary:
	var seats: Array = []
	var peers: Array = session["peers"]
	var offers: Array = session["offers"]
	var accepted: Array = session["accepted"]
	for i: int in 2:
		var player: Player = instance.players_by_peer_id.get(int(peers[i]), null)
		seats.append({
			"name": player.display_name if player != null else "Player",
			"id": player.player_resource.player_id if player != null else 0,
			"peer": int(peers[i]),
			"accepted": bool(accepted[i]),
			"gold": int(offers[i].get("gold", 0)),
			"items": _items_view(offers[i].get("items", {})),
		})
	var countdown: int = 0
	var until: int = int(session.get("countdown_until", 0))
	if until > 0:
		countdown = maxi(
			0,
			int(ceil(float(until - Time.get_ticks_msec()) / 1000.0))
		)
	return {
		"id": trade_id,
		"seats": seats,
		"countdown": countdown,
		"locked": bool(session.get("locked", false)),
	}


static func _close_session(
	instance: ServerInstance,
	trade_id: int,
	reason: String
) -> void:
	var session: Dictionary = _sessions.get(trade_id, {})
	if session.is_empty():
		return
	_sessions.erase(trade_id)
	for raw_peer: Variant in session["peers"]:
		_push(int(raw_peer), &"trade.closed", {
			"trade": trade_id,
			"reason": reason,
		})


static func _valid_session(
	peer_id: int,
	instance: ServerInstance,
	trade_id: int
) -> Dictionary:
	var session: Dictionary = _sessions.get(trade_id, {})
	if session.is_empty():
		return {}
	if int(session.get("instance_id", 0)) != instance.get_instance_id():
		return {}
	if not (session.get("peers", []) as Array).has(peer_id):
		return {}
	return session


static func _peer_index(session: Dictionary, peer_id: int) -> int:
	return (session["peers"] as Array).find(peer_id)


static func _session_for_peer(peer_id: int) -> int:
	for trade_id: int in _sessions:
		if (_sessions[trade_id].get("peers", []) as Array).has(peer_id):
			return trade_id
	return 0


static func _has_pending_invite(peer_id: int) -> bool:
	for invite: Dictionary in _invites.values():
		if int(invite.get("from", 0)) == peer_id \
				or int(invite.get("to", 0)) == peer_id:
			return true
	return false


static func _erase_invites_for_peer(peer_id: int) -> void:
	for invite_id: int in _invites.keys():
		var invite: Dictionary = _invites[invite_id]
		if int(invite.get("from", 0)) == peer_id \
				or int(invite.get("to", 0)) == peer_id:
			_invites.erase(invite_id)


static func _purge_expired_invites() -> void:
	var now: int = Time.get_ticks_msec()
	for invite_id: int in _invites.keys():
		var invite: Dictionary = _invites[invite_id]
		if int(invite.get("expires", 0)) > now:
			continue
		_expire_invite(invite_id)


static func _expire_invite_after_ttl(
	tree: SceneTree,
	invite_id: int
) -> void:
	await tree.create_timer(
		float(INVITE_TTL_MS) / 1000.0
	).timeout
	_expire_invite(invite_id)


static func _expire_invite(invite_id: int) -> void:
	var invite: Dictionary = _invites.get(invite_id, {})
	if invite.is_empty():
		return
	_invites.erase(invite_id)
	var requester: int = int(invite.get("from", 0))
	var recipient: int = int(invite.get("to", 0))
	_notify_invite_failed(requester, "expired")
	if recipient > 0:
		_push(recipient, &"trade.invite_result", {
			"invite": invite_id,
			"incoming": true,
			"accepted": false,
			"reason": "expired",
		})


static func _notify_invite_failed(peer_id: int, reason: String) -> void:
	if peer_id <= 0:
		return
	_push(peer_id, &"trade.invite_result", {
		"accepted": false,
		"reason": reason,
	})


static func _push(peer_id: int, type: StringName, payload: Dictionary) -> void:
	if peer_id <= 0 or WorldServer.curr == null:
		return
	var multiplayer_api: MultiplayerAPI = WorldServer.curr.multiplayer
	if multiplayer_api == null or not multiplayer_api.has_multiplayer_peer():
		return
	if peer_id not in multiplayer_api.get_peers():
		return
	WorldServer.curr.data_push.rpc_id(peer_id, type, payload)


static func _empty_offer() -> Dictionary:
	return {"items": {}, "gold": 0}


static func _items_view(items: Dictionary) -> Array:
	var out: Array = []
	for raw_id: Variant in items:
		var item_id: int = int(raw_id)
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		out.append({
			"id": item_id,
			"name": str(item.item_name) if item != null else "?",
			"amount": int(items[raw_id]),
		})
	return out


static func _describe_offer(offer: Dictionary) -> Dictionary:
	var items: Array = []
	for item: Dictionary in _items_view(offer.get("items", {})):
		items.append({"name": item["name"], "amount": item["amount"]})
	return {"items": items, "gold": int(offer.get("gold", 0))}


# Legacy table-state helpers remain so the reusable table asset still parses if a
# developer opens it directly. No production map instantiates trade tables now.
static func broadcast(instance: Node, table: TradeTable) -> void:
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"trade.table", build_state(table)),
		instance.name
	)


static func build_state(table: TradeTable) -> Dictionary:
	var seats: Array = []
	for i: int in 2:
		var occupant: Player = table.seat_players[i]
		if is_instance_valid(occupant):
			seats.append({
				"name": occupant.display_name,
				"id": occupant.player_resource.player_id,
				"accepted": table.seat_accepted[i],
				"gold": int(table.seat_offers[i].get("gold", 0)),
				"items": _items_view(table.seat_offers[i].get("items", {})),
			})
		else:
			seats.append({"name": "", "id": 0, "accepted": false, "gold": 0, "items": []})
	return {"id": table.table_id, "seats": seats, "countdown": 0, "join_cost": table.join_cost}
