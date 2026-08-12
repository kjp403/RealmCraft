extends DataRequestHandler
## Authorizes opening a shop. The catalog is static and rendered client-side from the
## local ShopResource; purchases are validated in shop.buy.item. Returns the
## player's balance for the shop's display currency (inventory gold/tokens, or
## PlayerResource.slayer_points when the shop trades in Slayer Points).


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var shop_key: StringName = StringName(str(args.get("shop_key", "")))

	# Authorization: the shop must be sold by a merchant present in the player's own
	# map — not just a valid key anywhere. Later, tighten to radius proximity via the
	# merchant's Area2D (body_entered presence). Faction/quest gating slots in here.
	var shop: ShopResource = instance.instance_map.get_shop(shop_key)
	if shop == null:
		return {"ok": false}

	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false}

	var currency_id: int = shop.display_currency_id()
	var balance: int = 0
	if Economy.is_slayer_points_id(currency_id):
		balance = player.player_resource.slayer_points
	elif currency_id > 0:
		balance = Inventory.count(player.player_resource.inventory, currency_id)

	return {"ok": true, "currency_id": currency_id, "currency_balance": balance}
