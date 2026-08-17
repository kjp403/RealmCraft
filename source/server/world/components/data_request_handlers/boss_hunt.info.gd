extends DataRequestHandler
## Contract board + lobby snapshot for a Hunt Broker. Args: {station}.
## Returns the full roster (BossHuntCatalog), the party's current pick, who's
## queued, and the caller's gold so the board can grey out what they can't buy.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	return BossHuntService.lobby_status(instance, peer_id, str(args.get("station", "")))
