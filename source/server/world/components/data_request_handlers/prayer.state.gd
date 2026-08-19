extends DataRequestHandler
## Snapshot for the prayer book: points, pool, level, and what's switched on.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	var payload: Dictionary = PrayerService.status(player)
	payload["ok"] = true
	return payload
