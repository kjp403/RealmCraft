extends DataRequestHandler
## Move one bag slot ({"uid", "bag"}) to a different unlocked bag — the drag
## target when a player drops an item onto a bag tab in the compact dock.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}

	var pr: PlayerResource = player.player_resource
	var uid: int = int(args.get("uid", -1))
	var dest_bag: int = int(args.get("bag", -1))
	var bag_count: int = clampi(pr.inventory_bags, 1, Inventory.MAX_BAGS)
	if uid < 0 or dest_bag < 0 or dest_bag >= bag_count:
		return {"ok": false, "reason": "bad_bag"}
	# Distinguish "the item is simply gone" (deposited, sold, consumed, or
	# salvaged in the gap between the drag starting and the drop landing) from
	# "the bag is full" -- move_slot_to_bag returns false for both, and
	# collapsing them told players "Bag N is full" when the bag had plenty of
	# room and the real problem was a stale drag payload.
	if not pr.inventory.has(uid):
		return {"ok": false, "reason": "missing"}
	# Already in that bag: a no-op the UI shouldn't normally offer (the tab
	# already showing is excluded as a drop target), but a direct request could
	# still hit it -- succeed without a pointless save.
	if int((pr.inventory[uid] as Dictionary).get("bag", 0)) == dest_bag:
		return {"ok": true, "inventory": pr.inventory}

	if not Inventory.move_slot_to_bag(pr.inventory, uid, dest_bag, bag_count):
		return {"ok": false, "reason": "full"}

	instance.world_server.database.save_player(pr)
	return {"ok": true, "inventory": pr.inventory}
