extends DataRequestHandler
## Just the headcount of players connected to this world, for the Settings
## panels. The /players command's roster push (players_command.gd) carries names
## and zones; this is the cheap poll for surfaces that only want the number.


func data_request_handler(
	_peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var world: WorldServer = instance.world_server
	if world == null:
		return {"ok": false, "count": 0}

	var count: int = 0
	for pid: int in world.connected_players:
		if world.connected_players[pid] != null:
			count += 1

	return {"ok": true, "count": count}
