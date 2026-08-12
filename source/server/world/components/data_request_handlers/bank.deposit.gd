extends DataRequestHandler
## Move a bag stack (or part of it) into the personal bank. Capacity is
## [member PlayerResource.bank_slots]; stacking into an existing bank pile is
## allowed when full, but opening a new stack is rejected with reason "full".
## Currency (gold) is rejected — it stays in the currency pouch.


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
	var inventory: Dictionary = player.player_resource.inventory
	if slot_uid < 0 or not inventory.has(slot_uid):
		return {"ok": false, "reason": "missing"}

	var slot: Dictionary = inventory[slot_uid]
	var item_id: int = int(slot.get("id", 0))
	var have: int = int(slot.get("a", 0))
	if item_id <= 0 or have <= 0:
		return {"ok": false, "reason": "missing"}

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.is_currency:
		return {"ok": false, "reason": "currency"}

	var amount: int = int(args.get("amount", have))
	if amount <= 0:
		amount = have
	amount = mini(amount, have)

	var bank: Dictionary = player.player_resource.bank
	var capacity: int = maxi(BankInteraction.STARTING_SLOTS, player.player_resource.bank_slots)
	# Fill existing stacks / free slots only — never open past capacity.
	var fit: int = Inventory.max_fit(bank, item_id, capacity, true)
	amount = mini(amount, fit)
	if amount <= 0:
		return {
			"ok": false,
			"reason": "full",
			"inventory": inventory,
			"bank": bank,
			"bank_slots": capacity,
		}

	var removed: int = Inventory.remove_from_slot(inventory, slot_uid, amount)
	if removed <= 0:
		return {"ok": false, "reason": "missing"}

	Inventory.add_item(bank, item_id, removed, true)
	instance.world_server.database.save_player(player.player_resource)
	return {
		"ok": true,
		"inventory": player.player_resource.inventory,
		"bank": player.player_resource.bank,
		"bank_slots": capacity,
	}
