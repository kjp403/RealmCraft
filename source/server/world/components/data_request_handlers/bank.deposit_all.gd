extends DataRequestHandler
## Deposit every non-currency bag stack into the personal bank in one request.
## Gold stays in the currency pouch (same rule as [code]bank.deposit[/code]).


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var inventory: Dictionary = player.player_resource.inventory
	var bank: Dictionary = player.player_resource.bank
	# Snapshot keys — remove_from_slot mutates the dictionary.
	var uids: Array = inventory.keys()
	var stacks: int = 0
	var units: int = 0
	for uid_variant: Variant in uids:
		var slot_uid: int = int(uid_variant)
		if not inventory.has(slot_uid):
			continue
		var slot: Dictionary = inventory[slot_uid]
		var item_id: int = int(slot.get("id", 0))
		var have: int = int(slot.get("a", 0))
		if item_id <= 0 or have <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item != null and item.is_currency:
			continue
		var removed: int = Inventory.remove_from_slot(inventory, slot_uid, have)
		if removed <= 0:
			continue
		Inventory.add_item(bank, item_id, removed)
		stacks += 1
		units += removed

	if stacks > 0:
		instance.world_server.database.save_player(player.player_resource)

	return {
		"ok": true,
		"stacks": stacks,
		"units": units,
		"inventory": player.player_resource.inventory,
		"bank": player.player_resource.bank,
	}
