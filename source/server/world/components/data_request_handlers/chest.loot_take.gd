extends DataRequestHandler
## Claim staged chest loot into the bag (capacity-capped).
## Args: { "id": item_id, "amount": optional } — omit id to Take All.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var resource: PlayerResource = player.player_resource
	var item_id: int = int(args.get("id", 0))
	var moved: int = 0
	if item_id > 0:
		var amount: int = int(args.get("amount", -1))
		moved = PendingChestLoot.take_to_bag(resource, item_id, amount)
	else:
		moved = PendingChestLoot.take_all_to_bag(resource)

	instance.world_server.database.save_player(resource)
	return {
		"ok": true,
		"moved": moved,
		"pending": PendingChestLoot.to_payload(resource.pending_chest_loot),
		"free_slots": Inventory.free_slots(resource.inventory),
		"inventory": resource.inventory,
	}
