extends DataRequestHandler
## Pick the difficulty for one board slot, which accepts the task and stamps its
## target. Server-authoritative: the client sends only a slot index and a
## difficulty, and the target quantity is rolled here from the seeded
## (player, day, slot, difficulty) stream — never taken from the request. A
## client that sends its own target is ignored.
##
## The choice is final for the day (DailyQuestManager.accept). Re-picking would
## let a player ride a Hard counter to 290/300 and then switch to Easy.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var resource: PlayerResource = player.player_resource

	# int() on a missing key yields 0, a valid slot AND a valid difficulty, so
	# both are checked for presence before coercion rather than after.
	if not args.has("slot") or not args.has("difficulty"):
		return {"ok": false, "reason": "bad_args"}
	var slot: int = int(args.get("slot", -1))
	var difficulty: int = int(args.get("difficulty", -1))

	var result: Dictionary = DailyQuestManager.accept(resource, slot, difficulty)
	if not bool(result.get("ok", false)):
		return result

	# Return the whole board, not just the accepted slot: the card that was
	# showing three choices has to be replaced by a progress card, and the client
	# already has the reflow path for a full board payload.
	var board: Dictionary = DailyQuestManager.build_board_payload(resource)
	board["accepted_slot"] = slot
	return board
