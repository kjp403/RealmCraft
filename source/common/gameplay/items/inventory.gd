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
const MAX_SLOTS: int = 28


## Convert raw JSON-loaded data into a clean { int: { "id": int, "a": int } } dict.
## Optional per-slot fields ("p" = pinned) survive the round-trip.
static func normalize(raw: Dictionary) -> Dictionary:
	var out: Dictionary
	for key in raw:
		var slot: Dictionary = raw[key]
		var clean: Dictionary = {
			"id": int(slot.get("id", 0)),
			"a": int(slot.get("a", 1)),
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


## Occupied bag squares (excludes currency stacks).
static func used_slots(inventory: Dictionary) -> int:
	var total: int = 0
	for slot_uid in inventory:
		var item_id: int = int(inventory[slot_uid].get("id", 0))
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if counts_toward_capacity(item):
			total += 1
	return total


## Remaining free squares under [param capacity] (bag default [constant MAX_SLOTS]).
static func free_slots(inventory: Dictionary, capacity: int = MAX_SLOTS) -> int:
	return maxi(0, capacity - used_slots(inventory))


## Largest amount of [param item_id] that still fits (existing stack space + free
## slots × stack_limit). Used by bank Max-withdraw and capacity-capped deposits.
static func max_fit(inventory: Dictionary, item_id: int, capacity: int = MAX_SLOTS) -> int:
	if item_id <= 0:
		return 0
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.is_currency:
		return 1 << 30
	var free: int = free_slots(inventory, capacity)
	var stackable: bool = item != null and item.is_stackable()
	if not stackable:
		return free
	var limit: int = 0 if item == null else int(item.stack_limit)
	if limit <= 0:
		# Pseudo-infinite: one existing stack absorbs any amount; else need 1 free slot.
		for slot_uid in inventory:
			if int(inventory[slot_uid].get("id", 0)) == item_id:
				return 1 << 30
		return 1 << 30 if free > 0 else 0
	var space: int = 0
	for slot_uid in inventory:
		if int(inventory[slot_uid].get("id", 0)) != item_id:
			continue
		var have: int = int(inventory[slot_uid].get("a", 0))
		if have < limit:
			space += limit - have
	space += free * limit
	return space


## How many *new* bag slots [param amount] of [param item_id] would open after
## filling existing stacks up to [member Item.stack_limit]. Currency always 0.
static func slots_needed(inventory: Dictionary, item_id: int, amount: int) -> int:
	if item_id <= 0 or amount <= 0:
		return 0
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.is_currency:
		return 0
	var stackable: bool = item != null and item.is_stackable()
	if not stackable:
		return amount
	var limit: int = 0 if item == null else int(item.stack_limit)
	var remaining: int = amount
	if limit > 0:
		for slot_uid in inventory:
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
	for slot_uid in inventory:
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			return 0
	return 1


## True if the store can accept the full [param amount] without exceeding
## [param capacity]. Currency always fits.
static func can_add(
	inventory: Dictionary,
	item_id: int,
	amount: int = 1,
	capacity: int = MAX_SLOTS
) -> bool:
	return slots_needed(inventory, item_id, amount) <= free_slots(inventory, capacity)


## Add to a capacity-capped store. Returns false without mutating when the full
## amount would not fit. Currency / stacking into free stack space still works
## on a "full" bag or bank.
static func try_add_item(
	inventory: Dictionary,
	item_id: int,
	amount: int = 1,
	capacity: int = MAX_SLOTS
) -> bool:
	if not can_add(inventory, item_id, amount, capacity):
		return false
	add_item(inventory, item_id, amount)
	return true


## Add an item to the inventory, stacking when the item allows it.
## Respects [member Item.stack_limit]: fill existing stacks up to the cap, then
## open new slots for the remainder. No capacity check — use [method try_add_item]
## for the player bag or bank.
static func add_item(inventory: Dictionary, item_id: int, amount: int = 1) -> void:
	if item_id <= 0 or amount <= 0:
		return

	# `as Item` so a bad index entry (e.g. an id pointing at a PackedScene) yields
	# null instead of crashing the server on the strict assignment.
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	# Unknown items default to non-stackable (own slot) to stay safe.
	var stackable: bool = item != null and item.is_stackable()
	if not stackable:
		for _i: int in amount:
			inventory[next_uid(inventory)] = {"id": item_id, "a": 1}
		return

	# 0 = pseudo-infinite (legacy default); otherwise hard cap per slot.
	var limit: int = 0 if item == null else int(item.stack_limit)
	var remaining: int = amount
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
		while remaining > 0:
			var put: int = mini(limit, remaining)
			inventory[next_uid(inventory)] = {"id": item_id, "a": put}
			remaining -= put
		return

	for slot_uid in inventory:
		if int(inventory[slot_uid].get("id", 0)) == item_id:
			inventory[slot_uid]["a"] = int(inventory[slot_uid].get("a", 0)) + remaining
			return
	inventory[next_uid(inventory)] = {"id": item_id, "a": remaining}


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
