extends DataRequestHandler
## Read the caller's Hunt Chest — the persistent Guild Hall stash Boss Hunt loot
## is banked into. Args: none. Returns the stacks plus the free bag slots, so the
## UI can say what will actually fit before the player hits Take.


func data_request_handler(peer_id: int, instance: ServerInstance, _args: Dictionary) -> Dictionary:
	var resource: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if resource == null:
		return {"error": 1, "ok": false, "message": "Couldn't find player."}
	return {
		"error": 0,
		"ok": true,
		"stacks": HuntChest.to_payload(resource),
		"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
		"capacity": HuntChest.MAX_STACKS,
	}
