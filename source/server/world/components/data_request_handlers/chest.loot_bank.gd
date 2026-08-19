extends DataRequestHandler
## Move staged chest loot into the personal bank (capacity-capped).
## Args: { "id": item_id, "amount": optional } — omit id to Bank All.
## Stacking into existing piles still works when full; new stacks are skipped.


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
	var capacity: int = maxi(BankInteraction.STARTING_SLOTS, resource.bank_slots)
	var item_id: int = int(args.get("id", 0))
	var moved: int = 0
	if item_id > 0:
		var amount: int = int(args.get("amount", -1))
		var had: int = PendingChestLoot.count(resource.pending_chest_loot, item_id)
		moved = PendingChestLoot.bank(resource, item_id, amount)
		if moved <= 0 and had > 0:
			return {
				"ok": false,
				"reason": "full",
				"moved": 0,
				"pending": PendingChestLoot.to_payload(resource.pending_chest_loot),
				"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
				"bank": resource.bank,
				"bank_slots": capacity,
			}
	else:
		moved = PendingChestLoot.flush_to_bank(resource)

	instance.world_server.database.save_player(resource)
	return {
		"ok": true,
		"moved": moved,
		"pending": PendingChestLoot.to_payload(resource.pending_chest_loot),
		"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
		"bank": resource.bank,
		"bank_slots": capacity,
	}
