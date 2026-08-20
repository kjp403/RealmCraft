extends DataRequestHandler
## Unequip whatever is in a given gear slot (e.g. &"weapon", &"torso").


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var slot: StringName = StringName(str(args.get("slot", "")))
	if slot.is_empty():
		return {"ok": false}

	# Only act if the slot currently holds an item.
	var item_id: int = int(player.equipment_component.slots.values.get(slot, 0))
	if item_id <= 0:
		return {"ok": false}

	# Unequipping the tome must end Battle Form — staying titan-sized without the
	# book equipped was an exploit (form outlived the mastery bar that cast it).
	if slot == &"weapon":
		BattleFormState.cancel_on(player)

	# Gear returns to the bag — need a free square first. Ammo stays bag-resident
	# while slotted, so it never needs a free square on unequip.
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	var active_bag: int = player.player_resource.active_inventory_bag
	var bag_count: int = player.player_resource.inventory_bags
	if item is GearItem and item is not AmmoItem and not Inventory.can_add(
		player.player_resource.inventory, item_id, 1, Inventory.MAX_SLOTS,
		false, active_bag, bag_count
	):
		return {"ok": false, "reason": "inventory_full"}

	player.equipment_component.unequip(slot)
	# Return it to the bag only if it was bag-OWNED (gear/weapon). Consumables and
	# materials are REFERENCED while held — they never left the bag, so re-adding
	# would duplicate them. Ammo is also reference-slotted (stack stays in the bag).
	if item is GearItem and item is not AmmoItem:
		Inventory.try_add_item(
			player.player_resource.inventory, item_id, 1, Inventory.MAX_SLOTS,
			false, active_bag, bag_count
		)
	player.player_resource.equipment.erase(slot)
	return {"ok": true}
