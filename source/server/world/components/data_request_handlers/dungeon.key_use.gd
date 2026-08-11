extends DataRequestHandler
## Use a [DungeonKeyItem]: spend one stack, add one bonus dungeon reward charge.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null:
		return {"ok": false, "reason": "player"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var item_id: int = int(args.get("id", 0))
	if item_id <= 0:
		return {"ok": false, "reason": "missing"}

	var inventory: Dictionary = player.player_resource.inventory
	if not Inventory.has_item(inventory, item_id):
		return {"ok": false, "reason": "missing"}

	var key_item: DungeonKeyItem = ContentRegistryHub.load_by_id(
		&"items",
		item_id
	) as DungeonKeyItem
	if key_item == null:
		return {"ok": false, "reason": "not_key"}

	if not Inventory.remove_amount_by_id(inventory, item_id, 1):
		return {"ok": false, "reason": "missing"}

	var left: int = DungeonService.add_bonus_charge(player.player_resource, 1)
	if peer_id > 0 and WorldServer.curr != null:
		WorldServer.curr.data_push.rpc_id(peer_id, &"dungeon.key_used", {
			"charges_left": left,
		})
		WorldServer.curr.chat_service.push_system_to_player(
			instance,
			player.player_resource.player_id,
			"Dungeon Key used. Reward charges left today: %d." % left
		)

	return {"ok": true, "charges_left": left}
