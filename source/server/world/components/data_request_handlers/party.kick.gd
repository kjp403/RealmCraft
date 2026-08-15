extends DataRequestHandler
## Leader-only: remove a member. Args: { id } (player_id).


func data_request_handler(
	peer_id: int,
	_instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	return PartyService.kick(peer_id, int(args.get("id", 0)))
