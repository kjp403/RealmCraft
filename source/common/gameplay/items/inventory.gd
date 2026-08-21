class_name Inventory
## Stateless helpers for the player inventory data model.
##
## Format (instance-based):
##     { slot_uid: int -> { "id": item_id: int, "a": amount: int } }
##
## Each slot is a distinct stack/instance. The "id" is the item registry id;
## per-instance data (durability, rolls, ...) can be added to the slot dict later
## without another migration. Stackable items merge into one slot; non-stackable
## items each get their own slot.
##
## Player bags are capped at [constant MAX_SLOTS] (currency pouch excluded).
## Banks use the same helpers with [member PlayerResource.bank_slots] as capacity.
## Uncapped grants use [method add_item]; capacity-checked grants use
## [method try_add_item] / [method can_add].
##
## Note: stored as JSON in SQLite, which turns int keys into strings and ints into
## floats on load. Always run loaded data through normalize() first.


## Hard cap on non-currency bag slots (OSRS-style). Forces bank usage.
const MAX_SLOTS: int = 30
## Number of inventory bags a player can unlock.
const MAX_BAGS: int = 3
## Materials (ores, logs, bars, hides, herbs) and cooked food stack this high
## in the bank. The bag still uses [member Item.stack_limit] (10 for most).
const BANK_RESOURCE_STACK: int = 50


## Slugs that stay unlimited in the BANK by design. Everything else caps at
## [constant BANK_RESOURCE_STACK] there, including items that never authored a
## stack_limit: 0 means "pseudo-infinite", so those sat in single 1.8k piles
## beside 50-capped ores and read as a duplication glitch.
const UNLIMITED_IN_BANK: Array[StringName] = [&"bone", &"vial_of_water"]


## Per-slot stack cap for [param item]. 0 = unlimited. Bank materials and cooked
## food use [constant BANK_RESOURCE_STACK] when that is higher than the bag cap.
## [constant UNLIMITED_IN_BANK] slugs are unlimited there (bag stays at
## [member Item.stack_limit]).
static func stack_limit_for(item: Item, in_bank: bool = false) -> int:
	var limit: int = 0 if item == null else int(item.stack_limit)
	if in_bank and item != null:
		if StringName(item.get_meta(&"slug", &"")) in UNLIMITED_IN_BANK:
			return 0
		if limit <= 0:
			# Ammo authors no stack_limit and players hold thousands of arrows.
			# Capping those at 50 would shatter one pile into forty bank rows.
			if item is AmmoItem:
				return 0
			# Unauthored (0 = pseudo-infinite). Cap it like every other vault
			# stack rather than letting it grow without bound.
			return BANK_RESOURCE_STACK
		if _bank_bulk_item(item):
			return maxi(limit, BANK_RESOURCE_STACK)
	return limit


## True for items that fill to [constant BANK_RESOURCE_STACK] in the vault.
## Bag caps stay on [member Item.stack_limit] (10 for food / most resources).
static func _bank_bulk_item(item: Item) -> bool:
	if item.inventory_tab() == Item.InventoryTab.MATERIAL:
		return true
	var food: ConsumableItem = item as ConsumableItem
	return food != null and food.cooldown_category == &"food"


static func _is_bone(item: Item) -> bool:
	return item != null and StringName(item.get_meta(&"slug", &"")) == &"bone"


## Convert raw JSON-loaded data into a clean { int: { "id": int, "a": int } } dict.
## Optional per-slot fields ("p" = pinned) survive the round-trip.
static func normalize(raw: Dictionary) -> Dictionary:
	var out: Dictionary
	for key in raw:
		var slot: Dictionary = raw[key]
		var clean: Dictionary = {
			"id": int(slot.get("id", 0)),
			"a": int(slot.get("a", 1)),
			"bag": int(slot.get("bag", 0)),
		}
		if slot.get("p", false):
			clean["p"] = true
		out[int(key)] = clean
	return out


## Pin or unpin a slot (pinned items render first in the bag UI). No-op on a
## missing slot. Returns true if the slot exists.
static func set_pinned(inventory: Dictionary, slot_uid: int, pinned: bool) -> bool:
	if not inventory.has(slot_uid):
		return false
	if pinned:
		inventory[slot_uid]["p"] = true
	else:
		inventory[slot_uid].erase("p")
	return true


## Currency lives in the pouch UI and does not consume a bag square.
static func counts_toward_capacity(item: Item) -> bool:
	return item == null or not item.is_currency


## Slots that belong to [param bag_index] (0-2). When [param bag_index] is -1,
## every slot is returned.
static func slots_of_bag(inventory: Dictionary, bag_index: int = -1) -> Array:
	if bag_index < 0:
		return inventory.keys()
	var uids: Array = []
	for slot_uid in inventory:
		if int(inventory[slot_uid].get("bag", 0)) == bag_index:
			uids.append(slot_uid)
	return uids


## Occupied bag squares for [param bag_index] (or all bags if -1).
static func used_slots(inventory: Dictionary, bag_index: int = -1) -> int:
	var total: int = 0
	var uids: Array = slots_of_bag(inventory, bag_index)
	for slot_uid in uids:
		var item_id: int = int(inventory[slot_uid].get("id", 0))
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if counts_toward_capacity(item):
			total += 1
	return total


## Remaining free squares under [param capacity] for [param bag_index].
## For all bags pass -1 and a capacity equal to [member MAX_SLOTS] × unlocked bags.
static func free_slots(inventory: Dictionary, capacity: int = MAX_SLOTS, bag_index: int = -1) -> int:
	return maxi(0, capacity - used_slots(inventory, bag_index))


## Free squares across every UNLOCKED bag. Use this for anything a player sees as
## "space left in my inventory": plain [method free_slots] defaults to ONE bag's
## capacity, so it reports 0 free for a 3-bag player holding 28 items even though
## 56 squares are open.
static func total_free_slots(inventory: Dictionary, bag_count: int = 1) -> int:
	return free_slots(inventory, MAX_SLOTS * maxi(1, bag_count), -1)


## Largest amount of [param item_id] that still fits (existing stack space + free
## slots × stack_limit). Used by bank Max-withdraw and capacity-capped deposits.
## [param start_bag] / [param bag_count] control which bag(s) to consider.
static func max_fit(
	inventory: Dictionary,
	item_id: int,
	capacity: int = MAX_SLOTS,
	in_bank: bool = false,
	start_bag: int = 0,
	bag_count: int = 1
) -> int:
	if item_id <= 0:
		return 0
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.is_currency:
		return 1 << 30
	var free: int = free_slots(inventory, capacity, start_bag) if bag_count <= 1 else free_slots(inventory, capacity * bag_count, -1)
	var uids: Array = slots_of_bag(inventory, start_bag) if bag_count <= 1 else slots_of_bag(inventory, -1)
	var stackable: bool = item != null and item.is_stackable()
	if not stackable:
		return free
	var limit: int = stack_limit_for(item, in_bank)
	if limit <= 0:
		# Pseudo-infinite: one existing stack absorbs any amount; else need 1 free slot.
		for slot_uid in uids:
			if int(inventory[slot_uid].get("id", 0)) == item_id:
				return 1 << 30
		return 1 << 30 if free > 0 else 0
	var space: int = 0
	for slot_uid in uids:
		if int(inventory[slot_uid].get("id", 0)) != item_id:
			continue
		var have: int = int(inventory[slot_uid].get("a", 0))
		if have < limit:
			space += limit - have
	space += free * limit
	return space


## How many *new* bag slots [param amount] of [param item_id] would open after
## filling existing stacks up to [member Item.stack_limit]. Currency always 0.
## [param bag_index] -1 checks all bags; a specific index checks only that bag.
static func slots_needed(
	inventory: Dictionary,
	item_id: int,
	amount: int,
	in_bank: bool = false,
	bag_index: int = -1
) -> int:
	if item_id <= 0 or amount <= 0:
		return 0
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.is_currency:
		return 0
	var stackable: bool = item != null and item.is_stackable()
	if not stackable:
		return amount
	var limit: int = stack_limit_for(item, in_bank)
	var remaining: int = amount
	var uids: Array = slots_of_bag(inventory, bag_index)
	if limit > 0:
		for slot_uid in uids:
			if remaining <= 0:
				break
			if int(inventory[slot_uid].get("id", 0)) != item_id:
				continue
			var have: int = int(inventory[slot_uid].get("a", 0))
			if have >= limit:
				continue
			remaining -= mini(limit - have, remaining)
		if remaining <= 0:
			return 0
		@warning_ignore("integer_division")
		return (remaining + limit - 1) / limit
	# Pseudo-infinite stack: one existing slot absorbs everything, else one new.
	for slot_uid in uids:
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			return 0
	return 1


## True if the store can accept the full [param amount] without exceeding
## [param capacity]. Currency always fits.
## [param start_bag] is where new slots are placed first; [param bag_count] is
## how many unlocked bags the player has (1-3). When [param bag_count] is 1,
## only [param start_bag] is checked.
static func can_add(
	inventory: Dictionary,
	item_id: int,
	amount: int = 1,
	capacity: int = MAX_SLOTS,
	in_bank: bool = false,
	start_bag: int = 0,
	bag_count: int = 1
) -> bool:
	if bag_count <= 1:
		return slots_needed(inventory, item_id, amount, in_bank, start_bag) <= free_slots(inventory, capacity, start_bag)
	var need: int = slots_needed(inventory, item_id, amount, in_bank, -1)
	var total_free: int = free_slots(inventory, capacity * bag_count, -1)
	return need <= total_free


## Add to a capacity-capped store. Returns false without mutating when the full
## amount would not fit. Currency / stacking into free stack space still works
## on a "full" bag or bank.
## [param start_bag] is the active/preferred bag; [param bag_count] is unlocked bags.
static func try_add_item(
	inventory: Dictionary,
	item_id: int,
	amount: int = 1,
	capacity: int = MAX_SLOTS,
	in_bank: bool = false,
	start_bag: int = 0,
	bag_count: int = 1
) -> bool:
	if not can_add(inventory, item_id, amount, capacity, in_bank, start_bag, bag_count):
		return false
	add_item(inventory, item_id, amount, in_bank, start_bag, bag_count)
	return true


## Add an item to the inventory, stacking when the item allows it.
## Respects [member Item.stack_limit]: fill existing stacks up to the cap, then
## open new slots for the remainder. No capacity check — use [method try_add_item]
## for the player bag or bank.
## [param start_bag] is where new slots are placed first; new slots wrap through
## [param bag_count] unlocked bags. Existing stacks of the same item are filled
## regardless of which bag they live in.
static func add_item(
	inventory: Dictionary,
	item_id: int,
	amount: int = 1,
	in_bank: bool = false,
	start_bag: int = 0,
	bag_count: int = 1
) -> void:
	if item_id <= 0 or amount <= 0:
		return

	# `as Item` so a bad index entry (e.g. an id pointing at a PackedScene) yields
	# null instead of crashing the server on the strict assignment.
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	# Unknown items default to non-stackable (own slot) to stay safe.
	var stackable: bool = item != null and item.is_stackable()
	if not stackable:
		for _i: int in amount:
			var bag: int = 0 if in_bank else _next_bag_with_space(
				inventory, MAX_SLOTS, start_bag, bag_count
			)
			inventory[next_uid(inventory)] = {"id": item_id, "a": 1, "bag": bag}
		return

	# 0 = pseudo-infinite (legacy default); otherwise hard cap per slot.
	var limit: int = stack_limit_for(item, in_bank)
	var remaining: int = amount

	# Fill existing stacks anywhere first.
	if limit > 0:
		for slot_uid in inventory:
			if remaining <= 0:
				break
			if int(inventory[slot_uid].get("id", 0)) != item_id:
				continue
			var have: int = int(inventory[slot_uid].get("a", 0))
			if have >= limit:
				continue
			var space: int = limit - have
			var put: int = mini(space, remaining)
			inventory[slot_uid]["a"] = have + put
			remaining -= put

		# The BANK has no bags and its capacity is PlayerResource.bank_slots, not
		# MAX_SLOTS. Running it through the bag loop below bounded new vault
		# slots at 28 per "bag 0", so a bank holding 28+ stacks reported zero
		# free slots and the loop exited with items still in hand — which this
		# void function then dropped, after the deposit had already taken them
		# out of the player's bag. Callers gate bank adds with max_fit().
		if in_bank:
			while remaining > 0:
				var bank_put: int = mini(limit, remaining)
				inventory[next_uid(inventory)] = {"id": item_id, "a": bank_put, "bag": 0}
				remaining -= bank_put
			return

		# Open new slots, wrapping through unlocked bags starting at [param start_bag].
		# bag_count is floored at 1: inventory_bags is clamped [1, MAX_BAGS] on save
		# and load, but a stray 0 here would divide by zero on the wrap below.
		var bags: int = maxi(1, bag_count)
		var current_bag: int = start_bag
		var checked: int = 0
		while remaining > 0 and checked < bags:
			var free_in_bag: int = free_slots(inventory, MAX_SLOTS, current_bag)
			if free_in_bag > 0:
				var can_fit_here: int = free_in_bag * limit
				var put_here: int = mini(can_fit_here, remaining)
				while put_here > 0:
					var put: int = mini(limit, put_here)
					inventory[next_uid(inventory)] = {"id": item_id, "a": put, "bag": current_bag}
					put_here -= put
					remaining -= put
					free_in_bag -= 1
			current_bag = (current_bag + 1) % bags
			checked += 1
		if remaining > 0:
			# add_item returns void, so anything still here is GONE. Callers are
			# supposed to pre-check with can_add()/max_fit(); shout rather than
			# lose it quietly, the way the bank path did.
			push_error(
				"Inventory.add_item dropped %d x item %d — capacity check missing upstream"
				% [remaining, item_id]
			)
		return

	# Pseudo-infinite stack: add to any existing stack, else a new one.
	for slot_uid in inventory:
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			inventory[slot_uid]["a"] = int(inventory[slot_uid].get("a", 0)) + remaining
			return
	var bag: int = 0 if in_bank else _next_bag_with_space(
		inventory, MAX_SLOTS, start_bag, bag_count
	)
	inventory[next_uid(inventory)] = {"id": item_id, "a": remaining, "bag": bag}


## Find the next unlocked bag with at least one free slot, starting from
## [param start_bag] and wrapping. Falls back to [param start_bag] if all are full.
##
## [param capacity] is the PER-BAG slot cap and must be [constant MAX_SLOTS] for
## the player bag. Passing 1 makes "has space" mean "is entirely empty", which
## scatters one item into each bag instead of filling the active one — see
## tools/verify_bags.tscn.
static func _next_bag_with_space(
	inventory: Dictionary,
	capacity: int,
	start_bag: int,
	bag_count: int
) -> int:
	for i: int in bag_count:
		var bag: int = (start_bag + i) % maxi(1, bag_count)
		if free_slots(inventory, capacity, bag) > 0:
			return bag
	return start_bag


## Move as much as possible from [param from_uid] onto [param to_uid] when both
## slots hold the same stackable item and the destination still has room.
## Returns the amount moved. Erases [param from_uid] if it empties. No-op (0)
## when the slots are incompatible or the destination is already full.
static func merge_slots(
	inventory: Dictionary,
	from_uid: int,
	to_uid: int,
	in_bank: bool = false
) -> int:
	if from_uid == to_uid or not inventory.has(from_uid) or not inventory.has(to_uid):
		return 0
	var from_slot: Dictionary = inventory[from_uid]
	var to_slot: Dictionary = inventory[to_uid]
	var item_id: int = int(from_slot.get("id", 0))
	if item_id <= 0 or item_id != int(to_slot.get("id", 0)):
		return 0
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item == null or not item.is_stackable():
		return 0
	var limit: int = stack_limit_for(item, in_bank)
	var have_to: int = int(to_slot.get("a", 0))
	var have_from: int = int(from_slot.get("a", 0))
	var space: int = have_from if limit <= 0 else maxi(0, limit - have_to)
	var moved: int = mini(have_from, space)
	if moved <= 0:
		return 0
	to_slot["a"] = have_to + moved
	remove_from_slot(inventory, from_uid, moved)
	return moved


## Remove up to `amount` from a slot, erasing the slot when it empties.
## Returns the amount actually removed (0 if the slot is missing).
static func remove_from_slot(inventory: Dictionary, slot_uid: int, amount: int = 1) -> int:
	if amount <= 0 or not inventory.has(slot_uid):
		return 0
	var have: int = int(inventory[slot_uid].get("a", 0))
	var removed: int = min(have, amount)
	var left: int = have - removed
	if left > 0:
		inventory[slot_uid]["a"] = left
	else:
		inventory.erase(slot_uid)
	return removed


## Remove one of the first slot holding the given item id. Returns true if removed.
static func remove_one_by_id(inventory: Dictionary, item_id: int) -> bool:
	for slot_uid in inventory:
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			return remove_from_slot(inventory, slot_uid, 1) > 0
	return false


## Total amount of an item across all slots (used for currency / stack totals).
static func count(inventory: Dictionary, item_id: int) -> int:
	var total: int = 0
	for slot_uid in inventory:
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			total += int(inventory[slot_uid].get("a", 0))
	return total


## Remove `amount` of an item across slots. No-op + false if not enough is held.
static func remove_amount_by_id(inventory: Dictionary, item_id: int, amount: int) -> bool:
	if amount <= 0 or count(inventory, item_id) < amount:
		return false
	var remaining: int = amount
	for slot_uid in inventory.keys():
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			remaining -= remove_from_slot(inventory, slot_uid, remaining)
			if remaining <= 0:
				break
	return true


## True if any slot holds the given item id.
static func has_item(inventory: Dictionary, item_id: int) -> bool:
	for slot_uid in inventory:
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			return true
	return false


## Next free slot uid. INT64 headroom is effectively unlimited for inventory sizes.
static func next_uid(inventory: Dictionary) -> int:
	var max_uid: int
	for slot_uid in inventory:
		max_uid = max(max_uid, int(slot_uid))
	return max_uid + 1
