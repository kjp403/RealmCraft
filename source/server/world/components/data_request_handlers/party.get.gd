extends DataRequestHandler
## Current party roster for the caller (empty members if ungrouped).


func data_request_handler(
	peer_id: int,
	_instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var snap: Dictionary = PartyService.snapshot_for(peer_id)
	snap["ok"] = true
	return snap
