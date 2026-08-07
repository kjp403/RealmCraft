extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	if not RateLimiter.check(peer_id, &"trade.accept", 8, 5_000):
		return {"ok": false, "reason": "rate_limited"}
	return TradeService.set_accepted(
		peer_id,
		instance,
		int(args.get("trade", 0)),
		bool(args.get("accepted", true))
	)
