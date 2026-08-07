extends DataRequestHandler


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	return TradeService.leave(
		peer_id,
		instance,
		int(args.get("trade", 0))
	)
