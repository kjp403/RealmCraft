class_name BankOrder
## Client-persisted bank vault slot order for drag-to-rearrange. Mirrors
## [BagOrder] but stores under settings key bank/bank_order.


const SECTION: StringName = &"bank"
const PROPERTY: StringName = &"bank_order"
const EMPTY: int = -1


static func load_order() -> Array:
	var raw: Variant = ClientState.settings.get_value(SECTION, PROPERTY)
	if raw is Array:
		return (raw as Array).duplicate()
	return []


static func save_order(order: Array) -> void:
	ClientState.settings.set_value(SECTION, PROPERTY, order)


static func sync_with_uids(uids: Array) -> Array:
	var live: Array = []
	for uid: Variant in uids:
		live.append(int(uid))
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
	while not kept.is_empty() and int(kept[kept.size() - 1]) == EMPTY:
		kept.pop_back()
	for id: int in live:
		if not used.has(id):
			kept.append(id)
	if kept != order:
		save_order(kept)
	return kept


static func index_of(order: Array, uid: int) -> int:
	var idx: int = order.find(uid)
	return idx if idx >= 0 else 1_000_000 + uid


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
