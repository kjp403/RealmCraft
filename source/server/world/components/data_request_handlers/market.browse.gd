extends DataRequestHandler
## The Trading Post board: every OPEN store that has stock, a flat feed of every
## active listing so a shopper can compare one item's price across sellers, the
## market's latest sales, and a rolling low/avg/high per item.
##
## The price data ships WITH the board rather than behind a second request: a row
## whose ask you cannot compare to what the item actually goes for is just a
## number, and asking per row would be an N+1 round trip. See [Market].
##
## Listing rows carry only ids — the client resolves names / icons from its own
## item registry, which keeps the payload small enough for a busy market.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false, "reason": "no_player"}

	var market: MarketStore = instance.world_server.database.market_store

	var stores: Array = []
	for row: Dictionary in market.open_stores():
		stores.append({
			"store_id": int(row.get("store_id", 0)),
			"store_name": str(row.get("store_name", "")),
			"owner_id": int(row.get("owner_id", 0)),
			"listing_count": int(row.get("listing_count", 0)),
			"units": int(row.get("units", 0)),
			"cheapest": int(row.get("cheapest", 0)),
		})

	var listings: Array = []
	for row: Dictionary in market.all_active_listings():
		if listings.size() >= Market.MAX_BROWSE_LISTINGS:
			break
		listings.append({
			"listing_id": int(row.get("listing_id", 0)),
			"store_id": int(row.get("store_id", 0)),
			"store_name": str(row.get("store_name", "")),
			"seller_id": int(row.get("seller_id", 0)),
			"seller_name": str(row.get("seller_name", "")),
			"item_id": int(row.get("item_id", 0)),
			"amount": int(row.get("amount", 0)),
			"unit_price": int(row.get("unit_price", 0)),
		})

	var trades: Array = []
	for row: Dictionary in market.recent_trades(Market.MAX_RECENT_TRADES):
		trades.append({
			"item_id": int(row.get("item_id", 0)),
			"amount": int(row.get("amount", 0)),
			"unit_price": int(row.get("unit_price", 0)),
			"total": int(row.get("total", 0)),
			"seller_name": str(row.get("seller_name", "")),
			"buyer_name": str(row.get("buyer_name", "")),
			"sold_at_ms": int(row.get("sold_at_ms", 0)),
		})

	return {
		"ok": true,
		"stores": stores,
		"listings": listings,
		"trades": trades,
		"stats": market.price_stats(Market.PRICE_WINDOW_MS),
		"window_ms": Market.PRICE_WINDOW_MS,
		"now_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"truncated": listings.size() >= Market.MAX_BROWSE_LISTINGS,
		"gold": Inventory.count(pr.inventory, Economy.gold_id()),
		"me": pr.player_id,
	}
