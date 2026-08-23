class_name QuickPrayers
## Client-local "quick prayers" set — which prayers the player has starred in
## the prayer book to bulk-toggle from the prayer bar's Q button. Membership is
## a pure UI preference (mirrors [BagOrder]'s manual order / item hotkeys):
## the server never validates or stores it, only the resulting
## prayer.quick_toggle request is authoritative.

const SECTION: StringName = &"prayer"
const PROPERTY: StringName = &"quick_set"


static func load_set() -> Array[StringName]:
	var raw: Variant = ClientState.settings.get_value(SECTION, PROPERTY)
	var out: Array[StringName] = []
	if raw is Array:
		for entry: Variant in raw:
			out.append(StringName(str(entry)))
	return out


static func save_set(slugs: Array[StringName]) -> void:
	var raw: Array = []
	for slug: StringName in slugs:
		raw.append(String(slug))
	ClientState.settings.set_value(SECTION, PROPERTY, raw)
	ClientState.quick_prayers_changed.emit()


static func is_quick(slug: StringName) -> bool:
	return load_set().has(slug)


## Add/remove one prayer from the set. Returns the new membership state.
static func toggle_membership(slug: StringName) -> bool:
	var set: Array[StringName] = load_set()
	var now_in: bool
	if set.has(slug):
		set.erase(slug)
		now_in = false
	else:
		set.append(slug)
		now_in = true
	save_set(set)
	return now_in
