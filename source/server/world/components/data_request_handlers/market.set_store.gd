extends DataRequestHandler
## Creates / renames / opens / closes the caller's own market stall.
##
## Closing only takes the stall off the board — the escrowed stock stays put and
## the owner keeps seeing it in My Store. Nothing here can move an item, so a
## mis-click on Close can't cost anyone anything. See [Market].


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false, "reason": "no_player"}

	var market: MarketStore = instance.world_server.database.market_store
	var existing: Dictionary = market.store_for(pr.player_id)

	# Omitted fields keep whatever the store already has, so "just toggle open"
	# and "just rename" are both one-field requests.
	var raw_name: String = str(args.get("name", str(existing.get("store_name", ""))))
	var store_name: String = Market.sanitize_store_name(raw_name, pr.display_name)
	var is_open: bool = bool(args.get("open", int(existing.get("is_open", 1)) == 1))

	var store_id: int = market.upsert_store(pr.player_id, store_name, is_open)
	if store_id <= 0:
		return {"ok": false, "reason": "failed"}

	MarketService.broadcast_change(&"store")
	ServerLog.info(
		"Market: player #%d (%s) set stall '%s' %s."
		% [pr.player_id, pr.display_name, store_name, "open" if is_open else "closed"]
	)
	return {
		"ok": true,
		"store_id": store_id,
		"store_name": store_name,
		"is_open": is_open,
	}
