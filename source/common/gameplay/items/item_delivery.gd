class_name ItemDelivery
extends RefCounted
## Hands a player items they have ALREADY earned, and never gives up until they
## have somewhere real to be.
##
## The "send to bank" buttons used to stop at the vault: whatever the bank could
## not hold simply did not move, and any path that added past a cap put items in
## squares the player could not see. This walks the whole ladder instead —
## bank → bag → the ground at the player's feet — and reports which rung each
## unit landed on so the UI can say so.
##
## A ground drop is the LAST resort: it is reserved to its owner but despawns
## after [member GroundItem.LIFETIME_S], so callers should surface it loudly.
## Anything that fits nowhere at all is reported as `stuck` and left where the
## caller staged it, so nothing is ever destroyed on the player's behalf.
##
## Server-only.


## Move [param amount] of [param item_id] into the bank, then the bag, then the
## ground. Returns { "bank", "bag", "ground", "stuck" } unit counts.
##
## [param instance] supplies the map for the ground drop; pass null to stop the
## ladder at the bag.
static func deliver_to_bank(
	instance: ServerInstance,
	player: Player,
	item_id: int,
	amount: int
) -> Dictionary:
	var out: Dictionary = {"bank": 0, "bag": 0, "ground": 0, "stuck": 0}
	if player == null or player.player_resource == null or item_id <= 0 or amount <= 0:
		out["stuck"] = maxi(0, amount)
		return out
	var resource: PlayerResource = player.player_resource
	var remaining: int = amount

	var capacity: int = maxi(BankInteraction.STARTING_SLOTS, resource.bank_slots)
	var to_bank: int = mini(remaining, Inventory.max_fit(resource.bank, item_id, capacity, true))
	if to_bank > 0:
		Inventory.add_item(resource.bank, item_id, to_bank, true)
		out["bank"] = to_bank
		remaining -= to_bank

	if remaining > 0:
		var to_bag: int = mini(remaining, Inventory.max_fit(
			resource.inventory, item_id, Inventory.MAX_SLOTS,
			false, resource.active_inventory_bag, resource.inventory_bags
		))
		if to_bag > 0:
			Inventory.add_item(
				resource.inventory, item_id, to_bag, false,
				resource.active_inventory_bag, resource.inventory_bags
			)
			out["bag"] = to_bag
			remaining -= to_bag

	if remaining > 0:
		var dropped: int = drop_at_feet(instance, player, item_id, remaining)
		out["ground"] = dropped
		remaining -= dropped

	out["stuck"] = remaining
	return out


## Spawn [param amount] of [param item_id] as a GroundItem at [param player]'s
## feet, reserved to them. Returns the amount that made it onto the map (0 when
## there is no map to drop onto — the caller keeps those units).
static func drop_at_feet(
	instance: ServerInstance,
	player: Player,
	item_id: int,
	amount: int
) -> int:
	if instance == null or player == null or item_id <= 0 or amount <= 0:
		return 0
	var map: Map = instance.instance_map
	if map == null or map.replicated_props_container == null:
		return 0
	var container: ReplicatedPropsContainer = map.replicated_props_container
	var offset := Vector2(randf_range(-18.0, 18.0), randf_range(-10.0, 10.0))
	var drop_local: Vector2 = container.to_local(player.global_position + offset)
	var owner_peer: int = int(player.player_resource.current_peer_id) \
		if player.player_resource != null else 0
	var ground: Node = container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_GROUND_ITEM,
		drop_local,
		{
			"item_id": item_id,
			"amount": amount,
			"position": drop_local,
			"owner_peer_id": owner_peer,
			"exclusive_until_ms": Time.get_ticks_msec() + int(GroundItem.EXCLUSIVE_S * 1000.0),
		}
	)
	return amount if ground != null else 0


## Player-facing summary of a [method deliver_to_bank] run, e.g.
## "Banked 12 — 4 to your bag, 2 dropped at your feet." Empty when nothing moved.
static func describe(result: Dictionary) -> String:
	var parts: PackedStringArray = []
	var banked: int = int(result.get("bank", 0))
	var bagged: int = int(result.get("bag", 0))
	var ground: int = int(result.get("ground", 0))
	if banked > 0:
		parts.append("Banked %d" % banked)
	if bagged > 0:
		parts.append("%d went to your bag (bank full)" % bagged)
	if ground > 0:
		parts.append("%d dropped at your feet — pick them up" % ground)
	return ", ".join(parts)
