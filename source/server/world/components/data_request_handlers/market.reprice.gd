extends DataRequestHandler
## Changes the asking price on one of the caller's own live listings.
##
## Re-pricing moves NO stock — the escrow row keeps exactly the units it already
## held — so a seller can chase the market as often as they like without pulling
## the stall down and re-listing (which would bounce their stock through the
## mailbox for nothing). See [Market].


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false, "reason": "no_player"}

	var listing_id: int = int(args.get("listing_id", 0))
	var unit_price: int = int(args.get("unit_price", 0))
	if listing_id <= 0:
		return {"ok": false, "reason": "missing"}

	var market: MarketStore = instance.world_server.database.market_store
	var row: Dictionary = market.listing(listing_id)
	if row.is_empty() or int(row.get("seller_id", 0)) != pr.player_id:
		return {"ok": false, "reason": "missing"}
	if int(row.get("state", -1)) != Market.State.ACTIVE:
		return {"ok": false, "reason": "gone"}

	# Same price bounds the original listing had to clear, re-checked here rather
	# than trusted from the client.
	var item: Item = ContentRegistryHub.load_by_id(&"items", int(row.get("item_id", 0))) as Item
	var min_price: int = maxi(1, item.market_minimum_price if item != null else 1)
	if unit_price < min_price:
		return {"ok": false, "reason": "min_price", "min_price": min_price}
	if unit_price > Market.MAX_UNIT_PRICE:
		return {"ok": false, "reason": "max_price", "max_price": Market.MAX_UNIT_PRICE}

	if not market.reprice(listing_id, pr.player_id, unit_price):
		return {"ok": false, "reason": "gone"}

	MarketService.broadcast_change(&"reprice", listing_id)
	ServerLog.info(
		"Market: player #%d (%s) re-priced listing #%d %s -> %s."
		% [
			pr.player_id, pr.display_name, listing_id,
			MarketService.format_gold(int(row.get("unit_price", 0))),
			MarketService.format_gold(unit_price),
		]
	)
	return {"ok": true, "listing_id": listing_id, "unit_price": unit_price}
