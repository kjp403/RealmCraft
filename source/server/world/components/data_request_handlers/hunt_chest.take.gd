extends DataRequestHandler
## Move Hunt Chest loot into the bag. Args: {[item: id], [amount], [all: bool]}.
## Omit `item` (or pass all=true) to empty as much of the chest as the bag holds;
## whatever doesn't fit stays in the chest.
##
## WHY THIS CANNOT DOUBLE-CLAIM
## The withdrawal is one synchronous pair — take from the chest array, add to the
## bag — with no await between them, and data requests are handled sequentially
## on the main thread. A player spamming Take All therefore has their second
## request see a chest the first already emptied, and it moves 0 rather than
## paying out twice. The amount is never trusted from the client either:
## HuntChest clamps every move to what the chest actually holds AND to what the
## destination can actually fit, so an inflated `amount` cannot mint items.
##
## Both piles live on the same PlayerResource, so the save below is atomic across
## them — there is no window where the items exist in the bag but not yet gone
## from the chest.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var resource: PlayerResource = instance.world_server.connected_players.get(peer_id)
	if resource == null:
		return {"error": 1, "ok": false, "message": "Couldn't find player."}
	# Storage is character-wide, but a corpse should not be sorting its stash —
	# same gate chest.open_item and chest.loot_bank apply.
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player != null and player.is_dead:
		return {"error": 1, "ok": false, "message": "Not while you're dead."}

	var moved: int = 0
	var item_id: int = int(args.get("item", 0))
	if bool(args.get("all", false)) or item_id <= 0:
		moved = HuntChest.take_all_to_bag(resource)
	else:
		moved = HuntChest.take_to_bag(resource, item_id, int(args.get("amount", -1)))

	# Persist the move rather than waiting on the 60s autosave. Not a dupe guard
	# (a crash would roll BOTH piles back together), but a withdrawal the player
	# watched happen should survive an unclean shutdown.
	if moved > 0:
		instance.world_server.database.save_player(resource)

	return {
		"error": 0,
		"ok": moved > 0,
		"moved": moved,
		"message": "" if moved > 0 else "Your bag is full.",
		"stacks": HuntChest.to_payload(resource),
		"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
		"capacity": HuntChest.MAX_STACKS,
	}
