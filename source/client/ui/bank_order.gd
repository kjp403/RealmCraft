class_name BankOrder
## Client-persisted bank vault presentation: the manual drag order (mirrors
## [BagOrder], stored under settings key bank/bank_order), the chosen sort mode,
## and the last category tab the player was looking at.
##
## Sorting is a VIEW concern, so it lives here rather than on the server: two
## players can look at the same vault data and order it differently, and the
## choice has to survive a relog. Only [constant Sort.CUSTOM] consults the manual
## order — every other mode derives its order from the item data, which is why
## dragging a stack flips the menu back to Custom.


const SECTION: StringName = &"bank"
const PROPERTY: StringName = &"bank_order"
const SORT_PROPERTY: StringName = &"bank_sort"
const TAB_PROPERTY: StringName = &"bank_tab"
const EMPTY: int = -1

## Vault sort modes, in the order the picker lists them. CUSTOM is the manual
## drag order; the rest are derived and re-apply themselves as the vault changes.
enum Sort {
	CUSTOM,
	NAME_ASC,
	NAME_DESC,
	QUANTITY,
	VALUE,
	CATEGORY,
	TIER,
}

## Picker labels. Kept beside the enum so a new mode can't ship without one.
const SORT_LABELS: Dictionary = {
	Sort.CUSTOM: "Custom (drag)",
	Sort.NAME_ASC: "Name  A–Z",
	Sort.NAME_DESC: "Name  Z–A",
	Sort.QUANTITY: "Quantity",
	Sort.VALUE: "Value",
	Sort.CATEGORY: "Category",
	Sort.TIER: "Tier",
}

## One-line explanation per mode, shown as the picker's tooltip.
const SORT_HINTS: Dictionary = {
	Sort.CUSTOM: "Your own layout. Drag stacks to rearrange them.",
	Sort.NAME_ASC: "Alphabetical, A to Z.",
	Sort.NAME_DESC: "Alphabetical, Z to A.",
	Sort.QUANTITY: "Biggest stacks first.",
	Sort.VALUE: "Highest vendor value first (stack total).",
	Sort.CATEGORY: "Grouped by weapons, armor, consumables, materials.",
	Sort.TIER: "Highest level / mastery requirement first.",
}


static func load_order() -> Array:
	var raw: Variant = ClientState.settings.get_value(SECTION, PROPERTY)
	if raw is Array:
		return (raw as Array).duplicate()
	return []


static func save_order(order: Array) -> void:
	ClientState.settings.set_value(SECTION, PROPERTY, order)


## Persisted sort mode, clamped so a settings file written by a newer build
## (or hand-edited) can never select a mode this one doesn't have.
static func load_sort() -> Sort:
	var raw: Variant = ClientState.settings.get_value(SECTION, SORT_PROPERTY)
	var mode: int = int(raw) if raw != null else int(Sort.CUSTOM)
	if not SORT_LABELS.has(mode):
		return Sort.CUSTOM
	return mode as Sort


static func save_sort(mode: Sort) -> void:
	ClientState.settings.set_value(SECTION, SORT_PROPERTY, int(mode))


## Last category tab (an [enum Item.InventoryTab] value, or the menu's own
## "All" sentinel). Stored raw — the menu validates it against the tabs that
## actually have items before selecting it.
static func load_tab(fallback: int) -> int:
	var raw: Variant = ClientState.settings.get_value(SECTION, TAB_PROPERTY)
	return int(raw) if raw != null else fallback


static func save_tab(tab: int) -> void:
	ClientState.settings.set_value(SECTION, TAB_PROPERTY, tab)


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


## Rewrite the manual order to match the uids as currently laid out. Used when
## the player drags while a derived sort is active: the visible arrangement is
## frozen into Custom first, so the dragged stack lands where they dropped it
## instead of snapping back to wherever the old manual order had it.
static func adopt_order(uids: Array) -> Array:
	var order: Array = []
	for uid: Variant in uids:
		order.append(int(uid))
	save_order(order)
	return order
