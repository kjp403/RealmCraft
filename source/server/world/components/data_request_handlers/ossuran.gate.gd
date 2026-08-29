extends DataRequestHandler
## The Ossuran portal ready-up lobby. Args: {action} — one of
## "join" / "leave" / "ready" / "unready" / "start". OssuranGateService owns the
## lobby state and the private-instance handoff; this is just the wire seam.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	return OssuranGateService.handle_request(instance, peer_id, str(args.get("action", "join")))
