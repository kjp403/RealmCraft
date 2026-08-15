extends DataRequestHandler
## Invite an online player into the caller's party (creates one if needed).
## Args: { id } (player_id) and/or { peer_id }.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	if not RateLimiter.check(peer_id, &"party.invite", 6, 10_000):
		return {"ok": false, "reason": "rate_limited"}
	var target_id: int = int(args.get("id", 0))
	if target_id <= 0:
		var target_peer: int = int(args.get("peer_id", 0))
		if target_peer > 0 and instance != null:
			var target: Player = instance.players_by_peer_id.get(target_peer)
			if target != null and target.player_resource != null:
				target_id = int(target.player_resource.player_id)
			elif WorldServer.curr != null:
				var res: PlayerResource = WorldServer.curr.connected_players.get(target_peer)
				if res != null:
					target_id = int(res.player_id)
	return PartyService.invite(peer_id, target_id)
