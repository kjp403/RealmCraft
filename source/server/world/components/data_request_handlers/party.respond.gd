extends DataRequestHandler
## Accept or decline a pending party invite. Args: { invite, accepted }.


func data_request_handler(
	peer_id: int,
	_instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	if not RateLimiter.check(peer_id, &"party.respond", 8, 10_000):
		return {"ok": false, "reason": "rate_limited"}
	return PartyService.respond(
		peer_id,
		int(args.get("invite", 0)),
		bool(args.get("accepted", false))
	)
