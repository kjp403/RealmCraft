extends DataRequestHandler


func data_request_handler(
	_peer_id: int,
	_instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	# Retained as an explicit tombstone for older clients. Public table trading was
	# removed in favour of private, invited player-to-player sessions.
	return {"ok": false, "reason": "retired"}
