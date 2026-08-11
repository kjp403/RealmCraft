extends DataRequestHandler
## Lightweight Slayer snapshot for the HUD tracker. Unlike slayer.status this
## does NOT require standing near a master — players need to see their active
## task / points / streak while out in the world.


func data_request_handler(peer_id: int, instance: ServerInstance, _args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}
	var payload: Dictionary = SlayerTaskService.status_payload(player.player_resource)
	payload["ok"] = true
	return payload
