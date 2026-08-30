extends DataRequestHandler
## Move Hunt Chest loot into the personal bank. Args:
## {[item: id], [amount], [all: bool]}. Omit `item` (or pass all=true) to push as
## much of the chest into the vault as its slots allow; the rest stays put.
##
## Same anti-duplication reasoning as hunt_chest.take — see the header there.
##
## NOTE the deliberate difference from `chest.loot_bank`: that one cascades
## bank -> bag -> ground because pending chest loot is transient and must not be
## swallowed. The Hunt Chest is PERMANENT storage, so anything that fits nowhere
## simply stays in the chest. Dropping a player's stash on the floor to make room
## would be a far worse failure than leaving it where they can come back for it.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var resource: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if resource == null:
		return {"error": 1, "ok": false, "message": "Couldn't find player."}
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player != null and player.is_dead:
		return {"error": 1, "ok": false, "message": "Not while you're dead."}

	var moved: int = 0
	var item_id: int = int(args.get("item", 0))
	if bool(args.get("all", false)) or item_id <= 0:
		moved = HuntChest.take_all_to_bank(resource)
	else:
		moved = HuntChest.take_to_bank(resource, item_id, int(args.get("amount", -1)))

	if moved > 0:
		instance.world_server.database.save_player(resource)

	return {
		"error": 0,
		"ok": moved > 0,
		"moved": moved,
		"message": "" if moved > 0 else "Your bank vault is full.",
		"stacks": HuntChest.to_payload(resource),
		"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
		"capacity": HuntChest.MAX_STACKS,
	}
