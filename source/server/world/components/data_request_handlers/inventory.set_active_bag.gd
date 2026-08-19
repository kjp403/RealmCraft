extends DataRequestHandler
## Set which inventory bag tab the client has open. Used by loot pickup to place
## items in the active bag first, with overflow to the next unlocked bag.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}

	var bag: int = int(args.get("bag", 0))
	player.player_resource.active_inventory_bag = clampi(bag, 0, maxi(1, player.player_resource.inventory_bags) - 1)
	return {"ok": true, "active_bag": player.player_resource.active_inventory_bag}
