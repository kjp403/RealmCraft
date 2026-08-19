extends DataRequestHandler
## Move bank stacks of an item back into the bag. Starts from the selected bank
## slot, then continues draining other bank slots of the same item_id until
## [code]amount[/code] is satisfied or the bag can't hold more. That lets Max
## fill the inventory with many capped stacks (ores/logs/bars) instead of one.


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
	var active_bag: int = player.player_resource.active_inventory_bag
	var bag_count: int = player.player_resource.inventory_bags
	if item != null and item.is_currency:
		var purged: int = Inventory.remove_from_slot(bank, slot_uid, have)
		if purged > 0:
			Inventory.add_item(
				player.player_resource.inventory, item_id, purged, false,
				active_bag, bag_count
			)
			instance.world_server.database.save_player(player.player_resource)
		return {
			"ok": false,
			"reason": "currency",
			"inventory": player.player_resource.inventory,
			"bank": player.player_resource.bank,
		}

	var banked_total: int = Inventory.count(bank, item_id)
	var amount: int = int(args.get("amount", have))
	if amount <= 0:
		amount = banked_total
	amount = mini(amount, banked_total)
	# Never try to pull more than the bag can accept — fill as much as fits.
	var fit: int = Inventory.max_fit(
		player.player_resource.inventory, item_id, Inventory.MAX_SLOTS,
		false, active_bag, bag_count
	)
	amount = mini(amount, fit)
	if amount <= 0:
		return {"ok": false, "reason": "inventory_full"}

	var remaining: int = amount
	var total_removed: int = 0
	# Prefer the selected slot first, then any other pile of the same item.
	var order: Array[int] = [slot_uid]
	for other_uid in bank.keys():
		var ouid: int = int(other_uid)
		if ouid == slot_uid:
			continue
		if int(bank[ouid].get("id", 0)) == item_id:
			order.append(ouid)
	for uid: int in order:
		if remaining <= 0:
			break
		if not bank.has(uid):
			continue
		var removed: int = Inventory.remove_from_slot(bank, uid, remaining)
		remaining -= removed
		total_removed += removed

	if total_removed <= 0:
		return {"ok": false, "reason": "missing"}

	if not Inventory.try_add_item(
		player.player_resource.inventory, item_id, total_removed, Inventory.MAX_SLOTS,
		false, active_bag, bag_count
	):
		Inventory.add_item(bank, item_id, total_removed, true)
		return {"ok": false, "reason": "inventory_full"}
	instance.world_server.database.save_player(player.player_resource)
	return {
		"ok": true,
		"moved": total_removed,
		"item_id": item_id,
		"inventory": player.player_resource.inventory,
		"bank": player.player_resource.bank,
	}
