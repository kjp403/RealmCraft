extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	if not RateLimiter.check(peer_id, &"trade.request", 3, 10_000):
		return {"ok": false, "reason": "rate_limited"}
	return TradeService.request_trade(
		peer_id,
		instance,
		int(args.get("peer_id", 0))
	)
