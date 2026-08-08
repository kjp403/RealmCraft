extends DataRequestHandler
## Character renames are disabled. Horizon used to offer this for a gold fee;
## names are now permanent and unique, so the handler always rejects.


func data_request_handler(
	_peer_id: int,
	_instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	return {"ok": false, "reason": "disabled"}
