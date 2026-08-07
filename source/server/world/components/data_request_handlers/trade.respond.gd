extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	if not RateLimiter.check(peer_id, &"trade.respond", 6, 10_000):
		return {"ok": false, "reason": "rate_limited"}
	return TradeService.respond_to_invite(
		peer_id,
		instance,
		int(args.get("invite", 0)),
		bool(args.get("accepted", false))
	)
