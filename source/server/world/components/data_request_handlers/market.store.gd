extends DataRequestHandler
## One stall's stock, for the store detail view. Only OPEN stores are readable by
## anyone but their owner — closing a stall has to actually take it off the board.
## See [Market].


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false, "reason": "no_player"}

	var store_id: int = int(args.get("store_id", 0))
	if store_id <= 0:
		return {"ok": false, "reason": "missing"}

	var market: MarketStore = instance.world_server.database.market_store
	instance.world_server.database.db.query_with_bindings(
		"SELECT store_id, owner_id, store_name, is_open FROM market_stores WHERE store_id = ?;",
		[store_id]
	)
	var rows: Array = instance.world_server.database.db.query_result
	if rows.is_empty():
		return {"ok": false, "reason": "missing"}
	var store: Dictionary = rows[0]
	var owner_id: int = int(store.get("owner_id", 0))
	if int(store.get("is_open", 0)) != 1 and owner_id != pr.player_id:
		return {"ok": false, "reason": "closed"}

	var listings: Array = []
	for row: Dictionary in market.listings_of_store(store_id):
		listings.append({
			"listing_id": int(row.get("listing_id", 0)),
			"store_id": store_id,
			"store_name": str(store.get("store_name", "")),
			"seller_id": int(row.get("seller_id", 0)),
			"seller_name": str(row.get("seller_name", "")),
			"item_id": int(row.get("item_id", 0)),
			"amount": int(row.get("amount", 0)),
			"unit_price": int(row.get("unit_price", 0)),
		})

	return {
		"ok": true,
		"store_id": store_id,
		"store_name": str(store.get("store_name", "")),
		"owner_id": owner_id,
		"is_mine": owner_id == pr.player_id,
		"listings": listings,
		"gold": Inventory.count(pr.inventory, Economy.gold_id()),
	}
