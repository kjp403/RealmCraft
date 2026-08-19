extends DataRequestHandler
## Drop a bag stack onto the ground as a pickable GroundItem.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var slot_uid: int = int(args.get("uid", -1))
	var inventory: Dictionary = player.player_resource.inventory
	if slot_uid < 0 or not inventory.has(slot_uid):
		return {"ok": false, "reason": "missing"}

	var slot: Dictionary = inventory[slot_uid]
	var item_id: int = int(slot.get("id", 0))
	var have: int = int(slot.get("a", 0))
	if item_id <= 0 or have <= 0:
		return {"ok": false, "reason": "missing"}

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item == null or not item.can_drop():
		return {"ok": false, "reason": "cant_drop"}

	# Drop the whole stack unless a positive amount is requested.
	var amount: int = int(args.get("amount", have))
	if amount <= 0:
		amount = have
	amount = mini(amount, have)

	var map: Map = instance.instance_map
	if map == null or map.replicated_props_container == null:
		return {"ok": false, "reason": "no_map"}

	var removed: int = Inventory.remove_from_slot(inventory, slot_uid, amount)
	if removed <= 0:
		return {"ok": false, "reason": "missing"}

	# If this stack was referenced in the hand (legacy holdable materials), clear it.
	var hand_id: int = int(player.equipment_component.slots.values.get(&"weapon", 0))
	if hand_id == item_id and not item is GearItem:
		player.equipment_component.unequip(&"weapon")
		player.player_resource.equipment.erase(&"weapon")

	var container: ReplicatedPropsContainer = map.replicated_props_container
	var offset := Vector2(randf_range(-18.0, 18.0), randf_range(-10.0, 10.0))
	var drop_global: Vector2 = player.global_position + offset
	var drop_local: Vector2 = container.to_local(drop_global)
	var ground: Node = container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_GROUND_ITEM,
		drop_local,
		{
			"item_id": item_id,
			"amount": removed,
			"position": drop_local,
		}
	)
	if ground == null:
		# Refund — spawn failed.
		Inventory.add_item(inventory, item_id, removed, false, player.player_resource.active_inventory_bag, player.player_resource.inventory_bags)
		return {"ok": false, "reason": "spawn_failed"}

	return {
		"ok": true,
		"id": item_id,
		"amount": removed,
		"name": String(item.item_name),
	}
