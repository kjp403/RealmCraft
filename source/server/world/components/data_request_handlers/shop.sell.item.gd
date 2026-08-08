extends DataRequestHandler
## Generic vendor sell: remove `amount` of an owned item with vendor_value > 0
## and pay `amount * item.vendor_value` gold. Specialty ShopTrade rates still
## go through shop.trade.item — this is the junk-sell path for gatherables.


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
	if shop == null or not shop.buys_vendor_priced:
		return {"ok": false, "reason": "no_shop"}

	var item_id: int = int(args.get("id", 0))
	var amount: int = maxi(1, int(args.get("amount", 1)))
	if item_id <= 0:
		return {"ok": false}

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item == null or item.is_currency or item.vendor_value <= 0:
		return {"ok": false, "reason": "not_sellable"}

	# Prefer specialty trades when this shop lists the item — client shouldn't
	# offer generic sell for those, but reject here too.
	if shop.accepted_trades != null:
		for trade: ShopTrade in shop.accepted_trades:
			if trade != null and trade.item != null and int(trade.item.get_meta(&"id", 0)) == item_id:
				return {"ok": false, "reason": "use_trade"}

	var inventory: Dictionary = player.player_resource.inventory
	if Inventory.count(inventory, item_id) < amount:
		return {"ok": false, "reason": "not_enough"}
	if not Inventory.remove_amount_by_id(inventory, item_id, amount):
		return {"ok": false}

	Inventory.add_item(inventory, Economy.gold_id(), item.vendor_value * amount)
	return {"ok": true, "amount": amount, "paid": item.vendor_value * amount}
