extends DataRequestHandler
## Returns the player's skilling daily board: three slots, each either OFFERED
## (with its three difficulty choices and their exact targets) or ACTIVE /
## COMPLETE / CLAIMED with live progress.
##
## Generating the board is a read — the three skills are a pure function of
## (player_id, UTC day), so opening the board is idempotent and cannot reroll
## anything. The payload shape is shared with the live `daily.progress` push
## (DailyQuestManager.build_board_payload).


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	return DailyQuestManager.build_board_payload(player.player_resource)
