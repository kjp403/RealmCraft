class_name BagOrder
## Client-persisted bag slot order for drag-to-rearrange. Inventory stacks are
## keyed by uid with no grid index; this keeps a uid sequence in settings so
## the dock (and fullscreen) can honor player arrangement across sessions.


const SECTION: StringName = &"inventory"
const PROPERTY: StringName = &"bag_order"


static func load_order() -> Array:
	var raw: Variant = ClientState.settings.get_value(SECTION, PROPERTY)
	if raw is Array:
		return (raw as Array).duplicate()
	return []


static func save_order(order: Array) -> void:
	ClientState.settings.set_value(SECTION, PROPERTY, order)


## Merge live inventory uids into the saved order: keep known order, append new
## uids, drop missing ones.
static func sync_with_entries(entries: Array) -> Array:
	var live: Array = []
	for entry: Variant in entries:
		if entry is Dictionary and entry.has("uid"):
			live.append(int(entry["uid"]))
	var order: Array = load_order()
	var kept: Array = []
	for uid: Variant in order:
		var id: int = int(uid)
		if id in live and id not in kept:
			kept.append(id)
	for id: int in live:
		if id not in kept:
			kept.append(id)
	if kept != order:
		save_order(kept)
	return kept


## Sort key helper: lower index in order first; unknown uids go last by uid.
static func index_of(order: Array, uid: int) -> int:
	var idx: int = order.find(uid)
	return idx if idx >= 0 else 1_000_000 + uid


static func swap(order: Array, uid_a: int, uid_b: int) -> Array:
	var ia: int = order.find(uid_a)
	var ib: int = order.find(uid_b)
	if ia < 0 or ib < 0 or ia == ib:
		return order
	var tmp: Variant = order[ia]
	order[ia] = order[ib]
	order[ib] = tmp
	save_order(order)
	return order


## Move uid_a to the index currently occupied by uid_b (insert-style).
static func move_before(order: Array, uid_a: int, uid_b: int) -> Array:
	var ia: int = order.find(uid_a)
	var ib: int = order.find(uid_b)
	if ia < 0 or ib < 0 or ia == ib:
		return order
	order.remove_at(ia)
	if ia < ib:
		ib -= 1
	order.insert(ib, uid_a)
	save_order(order)
	return order
