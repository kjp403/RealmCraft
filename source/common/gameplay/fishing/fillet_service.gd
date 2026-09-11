class_name FilletService
## Turning raw fish into Fish Bait with the Fillet Knife. Static functions over a
## [PlayerResource], like every other service here.
##
## SERVER-AUTHORITATIVE. The panel is a view: it renders [method filletable] and
## sends `fillet.convert`. Every gate below — knife held, fish actually in the bag,
## bag space for the bait — is re-checked here, because the client's copy of the
## inventory is a mirror and a fabricated packet must not be able to print bait.

## Item slug of the knife. Resolved through the registry, never a hardcoded id: a
## hand-written id that drifts from items_index silently resolves to nothing, and
## the tool would refuse every conversion with no clue why.
const KNIFE_SLUG: StringName = &"fillet_knife"

## Cap on one conversion request, mirroring [constant MAX_BUY_AMOUNT] in
## shop.buy.item. A client-sent `amount` large enough to overflow
## `amount * bait_yield` into a negative would slip past the capacity check and
## then run an unbounded add loop.
const MAX_CONVERT: int = 9999


## True when the player is carrying a Fillet Knife. The knife is a tool, not a
## consumable — it is never spent, it just gates the action.
static func has_knife(resource: PlayerResource) -> bool:
	if resource == null:
		return false
	if ContentRegistryHub.registry_of(&"items") == null:
		return false
	var id: int = ContentRegistryHub.id_from_slug(&"items", KNIFE_SLUG)
	return id > 0 and Inventory.has_item(resource.inventory, id)


## Every raw fish in the player's bags, as rows for the Fillet panel:
## {"id": int, "name": String, "held": int, "yield_each": int, "bait": int}.
##
## Only ids and counts cross the wire — the client resolves the icon from the id
## through its own registry. A payload that carried textures would put this panel
## on the wrong side of the WebSocket buffer the moment someone showed up with a
## bag full of twelve species.
static func filletable(resource: PlayerResource) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if resource == null:
		return rows

	var table: FilletTable = FilletTable.shared()
	if table == null:
		return rows

	# Fold the bags down to one count per item id first. Walking slots directly
	# would list Raw Tuna three times for a player holding three part-stacks.
	var counts: Dictionary[int, int] = {}
	for slot_uid: Variant in resource.inventory:
		var slot: Dictionary = resource.inventory[slot_uid]
		var id: int = int(slot.get("id", 0))
		if id <= 0:
			continue
		counts[id] = int(counts.get(id, 0)) + int(slot.get("a", 0))

	for id: int in counts:
		var item: Item = ContentRegistryHub.load_by_id(&"items", id) as Item
		if item == null or not FilletTable.is_raw_fish(item):
			continue
		var each: int = table.yield_for(item)
		if each <= 0:
			continue
		var held: int = int(counts[id])
		rows.append({
			"id": id,
			"name": String(item.item_name),
			"held": held,
			"yield_each": each,
			"bait": held * each,
		})

	# Stable, player-legible order: most bait first, then by name so two fish with
	# the same payoff do not swap places between redraws.
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["bait"]) != int(b["bait"]):
			return int(a["bait"]) > int(b["bait"])
		return String(a["name"]) < String(b["name"])
	)
	return rows


## Fillet [param amount] of one fish. [param amount] <= 0 means "all of this fish".
## Returns {"ok": bool, "converted": int, "bait": int, "reason": String}.
static func fillet(resource: PlayerResource, item_id: int, amount: int = 0) -> Dictionary:
	if resource == null:
		return {"ok": false, "reason": "no_player"}
	if not has_knife(resource):
		return {"ok": false, "reason": "no_knife"}

	var bait_id: int = BaitBucket.bait_id()
	if bait_id <= 0:
		return {"ok": false, "reason": "no_bait_item"}

	var table: FilletTable = FilletTable.shared()
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if table == null or item == null or not FilletTable.is_raw_fish(item):
		return {"ok": false, "reason": "not_fish"}

	var each: int = table.yield_for(item)
	if each <= 0:
		return {"ok": false, "reason": "not_fish"}

	var held: int = Inventory.count(resource.inventory, item_id)
	var take: int = held if amount <= 0 else mini(amount, held)
	take = mini(take, MAX_CONVERT)
	if take <= 0:
		return {"ok": false, "reason": "none_held"}

	return _convert(resource, item_id, take, each, bait_id)


## Fillet every raw fish in the bags, biggest payoff first. Partial success is a
## success: a bag that fills halfway through still reports what it managed, rather
## than rolling back work the player watched happen.
static func fillet_all(resource: PlayerResource) -> Dictionary:
	if resource == null:
		return {"ok": false, "reason": "no_player"}
	if not has_knife(resource):
		return {"ok": false, "reason": "no_knife"}

	var bait_id: int = BaitBucket.bait_id()
	if bait_id <= 0:
		return {"ok": false, "reason": "no_bait_item"}

	var converted: int = 0
	var bait: int = 0
	var stopped_full: bool = false
	for row: Dictionary in filletable(resource):
		var result: Dictionary = _convert(
			resource, int(row["id"]), int(row["held"]), int(row["yield_each"]), bait_id
		)
		if bool(result.get("ok", false)):
			converted += int(result.get("converted", 0))
			bait += int(result.get("bait", 0))
			continue
		if str(result.get("reason", "")) == "inventory_full":
			stopped_full = true
			break

	if converted <= 0:
		return {"ok": false, "reason": "inventory_full" if stopped_full else "no_fish"}
	return {"ok": true, "converted": converted, "bait": bait, "partial": stopped_full}


## The one conversion primitive. Removes the fish FIRST — which frees the slots the
## bait is about to need — then adds the bait, and puts the fish back if that add
## somehow fails. Ordering it the other way round would refuse conversions that
## actually fit, because the bait would be sized against a bag still holding the
## fish it is replacing.
static func _convert(
	resource: PlayerResource, item_id: int, take: int, each: int, bait_id: int
) -> Dictionary:
	if take <= 0:
		return {"ok": false, "reason": "none_held"}

	var bag_count: int = resource.inventory_bags
	var active_bag: int = resource.active_inventory_bag
	var produced: int = take * each

	if not Inventory.remove_amount_by_id(resource.inventory, item_id, take):
		return {"ok": false, "reason": "none_held"}

	if not Inventory.can_add(
		resource.inventory, bait_id, produced, Inventory.MAX_SLOTS,
		false, active_bag, bag_count
	):
		# Nothing was produced — hand the fish back exactly as it was.
		Inventory.add_item(
			resource.inventory, item_id, take, false, active_bag, bag_count
		)
		return {"ok": false, "reason": "inventory_full"}

	Inventory.try_add_item(
		resource.inventory, bait_id, produced, Inventory.MAX_SLOTS,
		false, active_bag, bag_count
	)
	return {"ok": true, "converted": take, "bait": produced}
