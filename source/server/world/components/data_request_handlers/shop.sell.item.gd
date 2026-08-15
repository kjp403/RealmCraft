extends DataRequestHandler
## Generic vendor sell: pay [method ShopResource.buyback_gold] per unit (junk
## vendor_value, or 75% of a gold shop's potion buy price). Specialty ShopTrade
## rates still go through shop.trade.item. Equipped gear counts as owned: we
## strip matching equipment slots first (without requiring a free bag square)
## so smithing products can be sold while worn.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var shop_key: StringName = StringName(str(args.get("shop_key", "")))
	var shop: ShopResource = instance.instance_map.get_shop(shop_key)
	if shop == null:
		return {"ok": false, "reason": "no_shop"}

	var item_id: int = int(args.get("id", 0))
	var amount: int = maxi(1, int(args.get("amount", 1)))
	if item_id <= 0:
		return {"ok": false}

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item == null or not shop.can_vendor_buy(item):
		return {"ok": false, "reason": "not_sellable"}
	var unit_price: int = shop.buyback_gold(item)
	if unit_price <= 0:
		return {"ok": false, "reason": "not_sellable"}

	# Prefer specialty trades when this shop lists the item — client shouldn't
	# offer generic sell for those, but reject here too.
	if shop.accepted_trades != null:
		for trade: ShopTrade in shop.accepted_trades:
			if trade != null and trade.item != null and int(trade.item.get_meta(&"id", 0)) == item_id:
				return {"ok": false, "reason": "use_trade"}

	var inventory: Dictionary = player.player_resource.inventory
	var available: int = Inventory.count(inventory, item_id) + _equipped_count(player, item_id)
	if available < amount:
		return {"ok": false, "reason": "not_enough"}

	var remaining: int = amount
	# Take from the bag first, then strip matching worn pieces (sold directly —
	# never bounced through the inventory, so a full bag can't block the sell).
	var from_bag: int = mini(remaining, Inventory.count(inventory, item_id))
	if from_bag > 0:
		if not Inventory.remove_amount_by_id(inventory, item_id, from_bag):
			return {"ok": false, "reason": "not_enough"}
		remaining -= from_bag
	if remaining > 0:
		var stripped: int = _strip_equipped(player, item_id, remaining)
		if stripped < remaining:
			return {"ok": false, "reason": "not_enough"}

	Inventory.add_item(inventory, Economy.gold_id(), unit_price * amount)
	return {"ok": true, "amount": amount, "paid": unit_price * amount}


## How many copies of [param item_id] are currently worn.
func _equipped_count(player: Player, item_id: int) -> int:
	var count: int = 0
	for slot: StringName in player.player_resource.equipment:
		if int(player.player_resource.equipment[slot]) == item_id:
			count += 1
	return count


## Unequip up to [param amount] worn copies of [param item_id], discarding them
## into the sell (not the bag). Returns how many were stripped.
func _strip_equipped(player: Player, item_id: int, amount: int) -> int:
	var stripped: int = 0
	var slots: Array = player.player_resource.equipment.keys()
	for slot_variant: Variant in slots:
		if stripped >= amount:
			break
		var slot: StringName = slot_variant as StringName
		if int(player.player_resource.equipment.get(slot, 0)) != item_id:
			continue
		if slot == &"weapon":
			BattleFormState.cancel_on(player)
		player.equipment_component.unequip(slot)
		player.player_resource.equipment.erase(slot)
		stripped += 1
	return stripped
