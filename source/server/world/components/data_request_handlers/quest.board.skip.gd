extends DataRequestHandler
## Reroll one daily the player can't complete, spending one of the day's three
## skips. Everything is validated server-side in DailyQuestService.skip (the entry
## is really in today's set, isn't already claimed, and a budget is left), so a
## crafted client can't reroll for free or past the cap.
##
## Returns the FULL refreshed board on success — the board is what the client
## renders, and handing it back in one round trip keeps the replaced card from
## flickering through a stale state before the follow-up info fetch lands.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var resource: PlayerResource = player.player_resource

	var template_id: int = int(args.get("template_id", 0))
	if template_id <= 0:
		return {"ok": false, "reason": "bad_args"}

	var result: Dictionary = DailyQuestService.skip(resource, template_id)
	if not bool(result.get("ok", false)):
		return result

	var board: Dictionary = DailyQuestService.build_board_payload(resource)
	board["skipped"] = true
	return board
