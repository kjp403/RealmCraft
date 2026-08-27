extends DataRequestHandler
## Recent completed sales — the Trading Post's price signal.
##
## With no args: the whole market's latest trades (the board ticker). With
## {"item_id": N}: that item's own history, which is what a seller reads before
## setting an ask and what a buyer reads to know whether a price is fair.
##
## Read-only and public: what something sold for is exactly the information a
## player-run economy needs in the open. See [Market].


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false, "reason": "no_player"}

	var market: MarketStore = instance.world_server.database.market_store
	var item_id: int = int(args.get("item_id", 0))
	var rows: Array = (
		market.trades_for_item(item_id, Market.MAX_ITEM_TRADES)
		if item_id > 0
		else market.recent_trades(Market.MAX_RECENT_TRADES)
	)

	var trades: Array = []
	for row: Dictionary in rows:
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
		"item_id": item_id,
		"trades": trades,
		"stats": market.price_stats(Market.PRICE_WINDOW_MS),
		"window_ms": Market.PRICE_WINDOW_MS,
		"now_ms": int(Time.get_unix_time_from_system() * 1000.0),
	}
