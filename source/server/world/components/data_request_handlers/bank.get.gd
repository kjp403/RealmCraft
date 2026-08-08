extends DataRequestHandler
## Return the player's bag + bank vault for the bank UI.
## Any currency stacks that previously landed in the vault are moved back into
## the inventory pouch so gold never shows as a bankable item.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "missing"}
	if _purge_currency_from_bank(player):
		instance.world_server.database.save_player(player)
	return {
		"ok": true,
		"inventory": player.inventory,
		"bank": player.bank,
	}


func _purge_currency_from_bank(player: PlayerResource) -> bool:
	var changed: bool = false
	var uids: Array = player.bank.keys()
	for uid: Variant in uids:
		var slot: Dictionary = player.bank[uid]
		var item_id: int = int(slot.get("id", 0))
		var amount: int = int(slot.get("a", 0))
		if item_id <= 0 or amount <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item == null or not item.is_currency:
			continue
		var removed: int = Inventory.remove_from_slot(player.bank, int(uid), amount)
		if removed > 0:
			Inventory.add_item(player.inventory, item_id, removed)
			changed = true
	return changed
