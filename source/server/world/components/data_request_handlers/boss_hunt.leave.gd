extends DataRequestHandler
## Walk out of a boss hunt early: recall the caller to the Guild Hall and drop
## them from the party (recall_player -> player_switch_instance ->
## BossHuntService.on_player_left). Args: none. Loot already banked into the
## Hunt Chest stays there — leaving early forfeits the rest of the clock, not
## the haul.


func data_request_handler(peer_id: int, instance: ServerInstance, _args: Dictionary) -> Dictionary:
	if WorldServer.curr == null:
		return {"ok": false, "reason": "no_server"}
	var player: Player = instance.get_player(peer_id) as Player
	if player != null:
		player.restore_full()
	WorldServer.curr.instance_manager.recall_player(peer_id)
	return {"ok": true}
