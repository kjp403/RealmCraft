extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	if not RateLimiter.check(peer_id, &"trade.offer", 20, 5_000):
		return {"ok": false, "reason": "rate_limited"}
	var requested_items: Variant = args.get("items", {})
	if requested_items is not Dictionary:
		return {"ok": false, "reason": "invalid"}
	var items: Dictionary = requested_items as Dictionary
	return TradeService.set_offer(
		peer_id,
		instance,
		int(args.get("trade", 0)),
		items,
		int(args.get("gold", 0))
	)
