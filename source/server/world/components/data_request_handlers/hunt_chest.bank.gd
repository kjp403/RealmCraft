extends DataRequestHandler
## Move Hunt Chest loot into the personal bank. Args:
## {[item: id], [amount], [all: bool]}. Omit `item` (or pass all=true) to push as
## much of the chest into the vault as its slots allow; the rest stays put.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var resource: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if resource == null:
		return {"error": 1, "ok": false, "message": "Couldn't find player."}

	var moved: int = 0
	var item_id: int = int(args.get("item", 0))
	if bool(args.get("all", false)) or item_id <= 0:
		moved = HuntChest.take_all_to_bank(resource)
	else:
		moved = HuntChest.take_to_bank(resource, item_id, int(args.get("amount", -1)))

	return {
		"error": 0,
		"ok": moved > 0,
		"moved": moved,
		"message": "" if moved > 0 else "Your bank vault is full.",
		"stacks": HuntChest.to_payload(resource),
		"free_slots": Inventory.free_slots(resource.inventory),
		"capacity": HuntChest.MAX_STACKS,
	}
