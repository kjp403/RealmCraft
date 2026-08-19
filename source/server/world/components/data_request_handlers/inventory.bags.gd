extends DataRequestHandler
## Returns the player's unlocked inventory bag count and current active bag.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if player == null:
		return {"ok": false, "reason": "missing"}
	return {
		"ok": true,
		"bags": player.inventory_bags,
		"active_bag": player.active_inventory_bag,
	}
