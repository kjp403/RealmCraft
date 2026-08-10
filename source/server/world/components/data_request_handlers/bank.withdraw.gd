extends DataRequestHandler
## Move a bank stack (or part of it) back into the bag. No storage cap.
## Currency stacks that somehow landed in the vault are purged back to the pouch.


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

	var slot_uid: int = int(args.get("uid", -1))
	var bank: Dictionary = player.player_resource.bank
	if slot_uid < 0 or not bank.has(slot_uid):
		return {"ok": false, "reason": "missing"}

	var slot: Dictionary = bank[slot_uid]
	var item_id: int = int(slot.get("id", 0))
	var have: int = int(slot.get("a", 0))
	if item_id <= 0 or have <= 0:
		return {"ok": false, "reason": "missing"}

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.is_currency:
		var purged: int = Inventory.remove_from_slot(bank, slot_uid, have)
		if purged > 0:
			Inventory.add_item(player.player_resource.inventory, item_id, purged)
			instance.world_server.database.save_player(player.player_resource)
		return {
			"ok": false,
			"reason": "currency",
			"inventory": player.player_resource.inventory,
			"bank": player.player_resource.bank,
		}

	var amount: int = int(args.get("amount", have))
	if amount <= 0:
		amount = have
	amount = mini(amount, have)

	if not Inventory.can_add(player.player_resource.inventory, item_id, amount):
		return {"ok": false, "reason": "inventory_full"}

	var removed: int = Inventory.remove_from_slot(bank, slot_uid, amount)
	if removed <= 0:
		return {"ok": false, "reason": "missing"}

	if not Inventory.try_add_item(player.player_resource.inventory, item_id, removed):
		# Restore to bank if the bag somehow rejected the stack.
		Inventory.add_item(bank, item_id, removed)
		return {"ok": false, "reason": "inventory_full"}
	instance.world_server.database.save_player(player.player_resource)
	return {
		"ok": true,
		"inventory": player.player_resource.inventory,
		"bank": player.player_resource.bank,
	}
