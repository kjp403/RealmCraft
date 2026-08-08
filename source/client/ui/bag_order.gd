class_name BagOrder
## Client-persisted bag slot order for drag-to-rearrange. Inventory stacks are
## keyed by uid with no grid index; this keeps a uid sequence in settings so
## the dock (and fullscreen) can honor player arrangement across sessions.
## Empty grid cells are stored as [constant EMPTY] so items can sit past gaps.


const SECTION: StringName = &"inventory"
const PROPERTY: StringName = &"bag_order"
## Placeholder in the saved order for an empty bag square.
const EMPTY: int = -1


static func load_order() -> Array:
	var raw: Variant = ClientState.settings.get_value(SECTION, PROPERTY)
	if raw is Array:
		return (raw as Array).duplicate()
	return []


static func save_order(order: Array) -> void:
	ClientState.settings.set_value(SECTION, PROPERTY, order)


## Merge live inventory uids into the saved order: keep known order (and empty
## gaps), append new uids, drop missing ones.
static func sync_with_entries(entries: Array) -> Array:
	var live: Array = []
	for entry: Variant in entries:
		if entry is Dictionary and entry.has("uid"):
			live.append(int(entry["uid"]))
	var order: Array = load_order()
	var kept: Array = []
	var used: Dictionary = {}
	for uid: Variant in order:
		var id: int = int(uid)
		if id == EMPTY:
			kept.append(EMPTY)
			continue
		if id in live and not used.has(id):
			kept.append(id)
			used[id] = true
	# Drop trailing empties so newly gained items pack after the last real slot.
	while not kept.is_empty() and int(kept[kept.size() - 1]) == EMPTY:
		kept.pop_back()
	for id: int in live:
		if not used.has(id):
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


## Place [param uid] at bag grid [param index], preserving empty squares.
## Trailing empties are trimmed after the move.
static func move_to_index(order: Array, uid: int, index: int) -> Array:
	if uid < 0 or index < 0:
		return order
	var ia: int = order.find(uid)
	if ia < 0:
		return order
	while order.size() <= index:
		order.append(EMPTY)
	order.remove_at(ia)
	if ia < index:
		index -= 1
	if index < order.size() and int(order[index]) == EMPTY:
		order[index] = uid
	else:
		order.insert(clampi(index, 0, order.size()), uid)
	while not order.is_empty() and int(order[order.size() - 1]) == EMPTY:
		order.pop_back()
	save_order(order)
	return order
