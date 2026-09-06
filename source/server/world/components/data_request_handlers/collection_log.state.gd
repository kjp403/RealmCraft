extends DataRequestHandler
## Collection Log contents for the requesting player.
##
## The payload shape is owned by [CollectionLogManager.build_payload], not spelled
## out here, so the menu and the writer cannot drift apart — the same arrangement
## dailies_json has with DailyQuestManager.
##
## Read-only. There is deliberately no collection_log.* mutation handler: the ONLY
## thing that may write a log is the boss loot pipeline in [RewardService]. A
## client-callable write, however well intentioned, is a request a modified client
## can forge — and a forged one would hand out a green-log title for a boss the
## player never fought.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player or player.player_resource == null:
		return {"ok": false}
	var payload: Dictionary = CollectionLogManager.build_payload(player.player_resource)
	payload["ok"] = true
	return payload
