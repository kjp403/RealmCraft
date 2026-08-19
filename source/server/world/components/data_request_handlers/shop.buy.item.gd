extends DataRequestHandler

## Sanity cap on a single buy: a client could send a huge `amount` that overflows `price *
## amount` (int64) into a negative total, slip past the currency check, then run an unbounded
## add loop. No legitimate purchase needs more than this in one transaction.
const MAX_BUY_AMOUNT: int = 9999


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var shop_key: StringName = StringName(str(args.get("shop_key", "")))
	var item_id: int = int(args.get("id", 0))
	var amount: int = int(args.get("amount", 1))
	if item_id <= 0 or amount <= 0 or amount > MAX_BUY_AMOUNT:
		return {"ok": false, "reason": "bad_args"}

	# Resolve the shop from a merchant present in the player's map (authoritative +
	# verifies the player is at the shop's map), not from a client-trusted id.
	var shop: ShopResource = instance.instance_map.get_shop(shop_key)
	if not shop or not shop.allows_buying():
		return {"ok": false, "reason": "no_shop"}

	var entry: Dictionary = shop.entry_for(item_id)
	if entry.is_empty():
		# Key resolved to a shop, but that shop doesn't sell this item — the
		# signature of a shop-key collision (two merchants sharing one key).
		return {"ok": false, "reason": "not_sold_here"}

	var inventory: Dictionary = player.player_resource.inventory
	var active_bag: int = player.player_resource.active_inventory_bag
	var bag_count: int = player.player_resource.inventory_bags
	var currency_id: int = int(entry.get("currency_id", 0))
	var total: int = int(entry.get("price", 0)) * amount
	# Pay with the currency item (gold by default). currency_id 0 means the items
	# registry failed to resolve gold — surface that separately from a real shortfall.
	if currency_id <= 0:
		return {"ok": false, "reason": "no_currency"}
	if not Inventory.can_add(
		inventory, item_id, amount, Inventory.MAX_SLOTS, false,
		active_bag, bag_count
	):
		return {"ok": false, "reason": "inventory_full"}

	var paid_slayer_points: bool = Economy.is_slayer_points_id(currency_id)
	if paid_slayer_points:
		if player.player_resource.slayer_points < total:
			return {"ok": false, "reason": "cant_afford"}
		player.player_resource.slayer_points -= total
	elif not Inventory.remove_amount_by_id(inventory, currency_id, total):
		return {"ok": false, "reason": "cant_afford"}

	# Add one at a time so stackable items merge and non-stackable get separate slots.
	for i: int in amount:
		if not Inventory.try_add_item(
			inventory, item_id, 1, Inventory.MAX_SLOTS, false,
			active_bag, bag_count
		):
			# Shouldn't happen after can_add — refund remaining currency for safety.
			var refund: int = int(entry.get("price", 0)) * (amount - i)
			if refund > 0:
				if paid_slayer_points:
					player.player_resource.slayer_points += refund
				else:
					Inventory.add_item(
						inventory, currency_id, refund, false,
						active_bag, bag_count
					)
			return {"ok": false, "reason": "inventory_full"}

	# Silent quest refresh: a bought item may satisfy a "Bring N item" (COLLECT)
	# objective, which has no advance event of its own. Empty messages = no toast,
	# just a HUD tracker re-fetch.
	WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": []})
	var balance: int = (
		player.player_resource.slayer_points
		if paid_slayer_points
		else Inventory.count(inventory, currency_id)
	)
	return {"ok": true, "currency_balance": balance}
