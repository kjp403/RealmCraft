extends DataRequestHandler
## Leave the caller's current party.


func data_request_handler(
	peer_id: int,
	_instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	return PartyService.leave(peer_id)
