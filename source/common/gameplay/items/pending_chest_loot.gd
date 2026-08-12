class_name PendingChestLoot
extends RefCounted
## Server-side staging for chest opens. Items accumulate here (merged by item id)
## until the player claims them into the bag or bank. Gold never stages — it goes
## straight to the currency pouch. On logout, [method flush_to_bank] parks leftovers.

## Normalize a JSON-loaded array into [{ "id": int, "a": int }, ...], dropping junk.
static func normalize(raw: Variant) -> Array:
	var out: Array = []
	if not raw is Array:
		return out
	for entry: Variant in raw:
		if not entry is Dictionary:
			continue
		var item_id: int = int((entry as Dictionary).get("id", 0))
		var amount: int = int((entry as Dictionary).get("a", (entry as Dictionary).get("amount", 0)))
		if item_id <= 0 or amount <= 0:
			continue
		_merge_into(out, item_id, amount)
	return out


## Append [param amount] of [param item_id], merging into an existing stack.
static func add(pending: Array, item_id: int, amount: int) -> void:
	if item_id <= 0 or amount <= 0:
		return
	_merge_into(pending, item_id, amount)


static func _merge_into(pending: Array, item_id: int, amount: int) -> void:
	for entry: Variant in pending:
		if not entry is Dictionary:
			continue
		if int((entry as Dictionary).get("id", 0)) != item_id:
			continue
		(entry as Dictionary)["a"] = int((entry as Dictionary).get("a", 0)) + amount
		return
	pending.append({"id": item_id, "a": amount})


## Total staged stacks (for empty checks / UI counts).
static func is_empty(pending: Array) -> bool:
	return pending.is_empty()


## Remove up to [param amount] of [param item_id]. Returns how many were removed.
static func take(pending: Array, item_id: int, amount: int) -> int:
	if item_id <= 0 or amount <= 0:
		return 0
	var remaining: int = amount
	var i: int = 0
	while i < pending.size() and remaining > 0:
		var entry: Dictionary = pending[i] as Dictionary
		if int(entry.get("id", 0)) != item_id:
			i += 1
			continue
		var have: int = int(entry.get("a", 0))
		var removed: int = mini(have, remaining)
		have -= removed
		remaining -= removed
		if have <= 0:
			pending.remove_at(i)
		else:
			entry["a"] = have
			i += 1
	return amount - remaining


## Move as much of one staged stack into the bag as will fit. Returns amount moved.
static func take_to_bag(resource: PlayerResource, item_id: int, amount: int = -1) -> int:
	if resource == null or item_id <= 0:
		return 0
	var pending: Array = resource.pending_chest_loot
	var have: int = count(pending, item_id)
	if have <= 0:
		return 0
	var want: int = have if amount < 0 else mini(amount, have)
	var fit: int = Inventory.max_fit(resource.inventory, item_id)
	var move: int = mini(want, fit)
	if move <= 0:
		return 0
	take(pending, item_id, move)
	Inventory.add_item(resource.inventory, item_id, move)
	return move


## Move every staged stack into the bag until full. Returns total items moved.
static func take_all_to_bag(resource: PlayerResource) -> int:
	if resource == null:
		return 0
	var moved: int = 0
	# Snapshot ids — take_to_bag mutates the array.
	var ids: Array[int] = []
	for entry: Variant in resource.pending_chest_loot:
		if entry is Dictionary:
			var item_id: int = int((entry as Dictionary).get("id", 0))
			if item_id > 0 and not ids.has(item_id):
				ids.append(item_id)
	for item_id: int in ids:
		moved += take_to_bag(resource, item_id, -1)
	return moved


## Move one staged stack into the bank (respecting [member PlayerResource.bank_slots]).
## Returns amount moved. Stacking into existing piles still works when "full".
static func bank(resource: PlayerResource, item_id: int, amount: int = -1) -> int:
	if resource == null or item_id <= 0:
		return 0
	var have: int = count(resource.pending_chest_loot, item_id)
	if have <= 0:
		return 0
	var want: int = have if amount < 0 else mini(amount, have)
	var capacity: int = maxi(BankInteraction.STARTING_SLOTS, resource.bank_slots)
	var fit: int = Inventory.max_fit(resource.bank, item_id, capacity)
	var move: int = mini(want, fit)
	if move <= 0:
		return 0
	take(resource.pending_chest_loot, item_id, move)
	Inventory.add_item(resource.bank, item_id, move)
	return move


## Dump as much of the staging area into the bank as capacity allows. Leftovers
## stay pending (e.g. logout when the vault is full). Returns total items moved.
static func flush_to_bank(resource: PlayerResource) -> int:
	if resource == null:
		return 0
	var moved: int = 0
	# Snapshot unique ids — bank() mutates pending.
	var ids: Array[int] = []
	for entry: Variant in resource.pending_chest_loot:
		if entry is Dictionary:
			var item_id: int = int((entry as Dictionary).get("id", 0))
			if item_id > 0 and not ids.has(item_id):
				ids.append(item_id)
	for item_id: int in ids:
		moved += bank(resource, item_id, -1)
	return moved


static func count(pending: Array, item_id: int) -> int:
	var total: int = 0
	for entry: Variant in pending:
		if entry is Dictionary and int((entry as Dictionary).get("id", 0)) == item_id:
			total += int((entry as Dictionary).get("a", 0))
	return total


## Client/server payload rows with display names for the claim UI.
static func to_payload(pending: Array) -> Array:
	var out: Array = []
	for entry: Variant in pending:
		if not entry is Dictionary:
			continue
		var item_id: int = int((entry as Dictionary).get("id", 0))
		var amount: int = int((entry as Dictionary).get("a", 0))
		if item_id <= 0 or amount <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		out.append({
			"id": item_id,
			"amount": amount,
			"name": str(item.item_name) if item != null else "Item",
		})
	return out
