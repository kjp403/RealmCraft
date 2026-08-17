extends DataRequestHandler
## Leave the story-boss arena and return to the giver.


func data_request_handler(peer_id: int, instance: ServerInstance, _args: Dictionary) -> Dictionary:
	if WorldServer.curr == null:
		return {"ok": false, "reason": "no_server"}
	if not QuestBossService.is_quest_boss_instance(instance):
		return {"ok": false, "reason": "not_in_fight"}
	var player: Player = instance.get_player(peer_id) as Player
	if player != null:
		player.restore_full()
	QuestBossService.eject_to_origin(peer_id)
	return {"ok": true}
