extends DataRequestHandler
## Open a [LootChestItem] from the bag: spend one stack, grant the linked table.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null:
		return {"ok": false, "reason": "player"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var item_id: int = int(args.get("id", 0))
	if item_id <= 0:
		return {"ok": false, "reason": "missing"}

	var inventory: Dictionary = player.player_resource.inventory
	if not Inventory.has_item(inventory, item_id):
		return {"ok": false, "reason": "missing"}

	var chest_item: LootChestItem = ContentRegistryHub.load_by_id(
		&"items",
		item_id
	) as LootChestItem
	if chest_item == null:
		return {"ok": false, "reason": "not_chest"}

	var table: ChestResource = chest_item.resolve_table()
	if table == null:
		return {"ok": false, "reason": "missing"}

	# Spend the chest before granting so a failed remove can't duplicate loot.
	if not Inventory.remove_amount_by_id(inventory, item_id, 1):
		return {"ok": false, "reason": "missing"}

	var payout: Dictionary = table.roll_and_grant(player)
	if peer_id > 0 and WorldServer.curr != null:
		WorldServer.curr.data_push.rpc_id(peer_id, &"chest.opened", {
			"chest": str(payout.get("chest", chest_item.item_name)),
			"gold": int(payout.get("gold", 0)),
			"items": payout.get("items", []),
		})

	return {
		"ok": true,
		"chest": str(payout.get("chest", "")),
		"gold": int(payout.get("gold", 0)),
		"items": payout.get("items", []),
	}
