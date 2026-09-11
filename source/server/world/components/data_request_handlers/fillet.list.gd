extends DataRequestHandler
## The raw fish the Fillet panel lists. Read-only; the panel re-asks after every
## conversion rather than patching its own rows, so what it shows is always what
## the server would act on.


func data_request_handler(peer_id: int, instance: ServerInstance, _args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}
	if not FilletService.has_knife(player.player_resource):
		return {"ok": false, "reason": "no_knife"}

	return {
		"ok": true,
		"rows": FilletService.filletable(player.player_resource),
		"bait_id": BaitBucket.bait_id(),
	}
