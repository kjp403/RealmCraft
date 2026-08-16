class_name HuntChest
extends RefCounted
## The character's Hunt Chest — a persistent stash in the Guild Hall that Boss
## Hunt loot is banked into automatically as the party kills. It fills over a
## session (and across sessions), and the owner empties it into their bag or
## bank whenever they like from the chest in the hall.
##
## Storage shape is the same [{"id": int, "a": int}, ...] as
## [PendingChestLoot], so the array helpers there (normalize / add / take /
## count / to_payload) are reused verbatim; what differs is that this pile is
## PERMANENT — nothing auto-flushes it on logout — and it has a stack cap so it
## can't grow without bound. Persisted as PlayerResource.hunt_chest.

## Distinct item stacks the chest holds. Amounts inside a stack are unbounded
## (it's a trophy pile, not a bag), so this caps rows, not quantity.
const MAX_STACKS: int = 120


## Bank [param amount] of [param item_id] into [param resource]'s chest.
## Returns the amount actually stored — 0 when the chest is at [constant
## MAX_STACKS] and this item has no stack there yet, so the caller can tell the
## player their chest is full instead of silently eating the drop.
static func deposit(resource: PlayerResource, item_id: int, amount: int) -> int:
	if resource == null or item_id <= 0 or amount <= 0:
		return 0
	var chest: Array = resource.hunt_chest
	if PendingChestLoot.count(chest, item_id) <= 0 and chest.size() >= MAX_STACKS:
		return 0
	PendingChestLoot.add(chest, item_id, amount)
	return amount


## True when a NEW item id would not fit (existing stacks still grow).
static func is_full(resource: PlayerResource) -> bool:
	return resource != null and resource.hunt_chest.size() >= MAX_STACKS


static func stack_count(resource: PlayerResource) -> int:
	return resource.hunt_chest.size() if resource != null else 0


static func is_empty(resource: PlayerResource) -> bool:
	return resource == null or resource.hunt_chest.is_empty()


## Move one stack (or [param amount] of it) into the bag. Returns amount moved.
static func take_to_bag(resource: PlayerResource, item_id: int, amount: int = -1) -> int:
	if resource == null or item_id <= 0:
		return 0
	var have: int = PendingChestLoot.count(resource.hunt_chest, item_id)
	if have <= 0:
		return 0
	var want: int = have if amount < 0 else mini(amount, have)
	var move: int = mini(want, Inventory.max_fit(resource.inventory, item_id))
	if move <= 0:
		return 0
	PendingChestLoot.take(resource.hunt_chest, item_id, move)
	Inventory.add_item(resource.inventory, item_id, move)
	return move


## Move one stack (or [param amount] of it) into the bank. Returns amount moved.
static func take_to_bank(resource: PlayerResource, item_id: int, amount: int = -1) -> int:
	if resource == null or item_id <= 0:
		return 0
	var have: int = PendingChestLoot.count(resource.hunt_chest, item_id)
	if have <= 0:
		return 0
	var want: int = have if amount < 0 else mini(amount, have)
	var capacity: int = maxi(BankInteraction.STARTING_SLOTS, resource.bank_slots)
	var move: int = mini(want, Inventory.max_fit(resource.bank, item_id, capacity, true))
	if move <= 0:
		return 0
	PendingChestLoot.take(resource.hunt_chest, item_id, move)
	Inventory.add_item(resource.bank, item_id, move, true)
	return move


## Empty as much of the chest as the bag will hold. Returns total items moved.
static func take_all_to_bag(resource: PlayerResource) -> int:
	var moved: int = 0
	for item_id: int in _stack_ids(resource):
		moved += take_to_bag(resource, item_id, -1)
	return moved


## Empty as much of the chest as the bank will hold. Returns total items moved.
static func take_all_to_bank(resource: PlayerResource) -> int:
	var moved: int = 0
	for item_id: int in _stack_ids(resource):
		moved += take_to_bank(resource, item_id, -1)
	return moved


## Display rows for the chest UI.
static func to_payload(resource: PlayerResource) -> Array:
	return PendingChestLoot.to_payload(resource.hunt_chest) if resource != null else []


## Snapshot ids up front — the movers mutate the array while we iterate.
static func _stack_ids(resource: PlayerResource) -> Array[int]:
	var ids: Array[int] = []
	if resource == null:
		return ids
	for entry: Variant in resource.hunt_chest:
		if entry is Dictionary:
			var item_id: int = int((entry as Dictionary).get("id", 0))
			if item_id > 0 and not ids.has(item_id):
				ids.append(item_id)
	return ids
