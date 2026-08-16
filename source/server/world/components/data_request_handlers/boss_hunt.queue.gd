extends DataRequestHandler
## Drive a Hunt Broker lobby. Args: {station, action, [contract]}.
## Actions: "select" (pick the boss), "join" / "leave" (the shared queue), and
## "start" — which charges the CALLER the contract's gold cost and launches the
## whole queue into a private 30-minute arena. BossHuntService owns the group +
## instance lifecycle.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	return BossHuntService.handle_lobby_request(
		instance,
		peer_id,
		str(args.get("station", "")),
		str(args.get("action", "join")),
		args
	)
