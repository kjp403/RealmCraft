extends DataRequestHandler
## Return the player's bag + bank vault for the bank UI.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "missing"}
	return {
		"ok": true,
		"inventory": player.inventory,
		"bank": player.bank,
	}
