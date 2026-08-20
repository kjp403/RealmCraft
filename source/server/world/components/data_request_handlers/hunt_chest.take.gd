extends DataRequestHandler
## Move Hunt Chest loot into the bag. Args: {[item: id], [amount], [all: bool]}.
## Omit `item` (or pass all=true) to empty as much of the chest as the bag holds;
## whatever doesn't fit stays in the chest.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var resource: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if resource == null:
		return {"error": 1, "ok": false, "message": "Couldn't find player."}

	var moved: int = 0
	var item_id: int = int(args.get("item", 0))
	if bool(args.get("all", false)) or item_id <= 0:
		moved = HuntChest.take_all_to_bag(resource)
	else:
		moved = HuntChest.take_to_bag(resource, item_id, int(args.get("amount", -1)))

	return {
		"error": 0,
		"ok": moved > 0,
		"moved": moved,
		"message": "" if moved > 0 else "Your bag is full.",
		"stacks": HuntChest.to_payload(resource),
		"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
		"capacity": HuntChest.MAX_STACKS,
	}
