extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	if not RateLimiter.check(peer_id, &"trade.state", 12, 5_000):
		return {}
	return TradeService.state_for(
		peer_id,
		instance,
		int(args.get("trade", 0))
	)
