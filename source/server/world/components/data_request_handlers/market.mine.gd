extends DataRequestHandler
## The requesting character's own market stall: its name / open state, its active
## listings, and a fresh copy of their bag so the "list an item" picker never
## works from stale client data. See [Market].


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false, "reason": "no_player"}

	var market: MarketStore = instance.world_server.database.market_store
	var store: Dictionary = market.store_for(pr.player_id)
	var listings: Array = []
	for row: Dictionary in market.listings_of_seller(pr.player_id):
		listings.append({
			"listing_id": int(row.get("listing_id", 0)),
			"item_id": int(row.get("item_id", 0)),
			"amount": int(row.get("amount", 0)),
			"unit_price": int(row.get("unit_price", 0)),
			"created_at_ms": int(row.get("created_at_ms", 0)),
		})

	return {
		"ok": true,
		"me": pr.player_id,
		"has_store": not store.is_empty(),
		"store_id": int(store.get("store_id", 0)),
		"store_name": str(store.get("store_name", "")),
		"is_open": int(store.get("is_open", 0)) == 1,
		"default_name": Market.sanitize_store_name("", pr.display_name),
		"listings": listings,
		"max_listings": Market.MAX_LISTINGS_PER_STORE,
		"max_unit_price": Market.MAX_UNIT_PRICE,
		"inventory": pr.inventory,
		"gold": Inventory.count(pr.inventory, Economy.gold_id()),
	}
