extends Control
## The church altar. Two things happen here: burn bones for Prayer xp, and top
## your prayer points back up for free.
##
## Same card shape as boss_hunt_exit_menu. Rebuilt on every open (and after every
## offering) off the live bag, so a stack that empties disappears from the list
## rather than sitting there as a dead button.

const ROW_HEIGHT: float = 46.0
const GOLD: Color = Color(1.0, 0.95, 0.8)
const MUTED: Color = Color(0.72, 0.76, 0.84)
const CYAN: Color = Color(0.37, 0.83, 0.83)

var _content: VBoxContainer
## Offering rows are rebuilt constantly; the points line is not, so it is kept
## to update in place instead of flickering the whole card.
var _points_label: Label
## Snapshot of the bag, refetched with every rebuild.
var _inventory: Dictionary = {}
var _busy: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(_arg: Variant = null) -> void:
	_refresh()


## The bag is NOT mirrored on ClientState — every menu that needs it asks the
## server (see inventory_menu.fill_inventory), so this does the same rather than
## reading a mirror that does not exist.
func _refresh() -> void:
	var state: Array = await Client.request_data_await(
		&"prayer.state", {}, _instance_name()
	)
	var bag: Array = await Client.request_data_await(
		&"inventory.get", {}, _instance_name()
	)
	if not visible:
		return
	var prayer: Dictionary = state[0] if state.size() > 0 and state[0] is Dictionary else {}
	_inventory = bag[0] if bag.size() > 0 and bag[0] is Dictionary else {}
	_build(prayer)


func _build(prayer: Dictionary) -> void:
	_build_shell()

	var title: Label = Label.new()
	title.text = "Altar"
	title.add_theme_font_size_override(&"font_size", 22)
	title.add_theme_color_override(&"font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)

	_points_label = Label.new()
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.add_theme_color_override(&"font_color", CYAN)
	_content.add_child(_points_label)
	_set_points(prayer)

	var recharge: Button = _button("Restore prayer points", _on_recharge)
	recharge.custom_minimum_size = Vector2(0, 38)
	_content.add_child(recharge)

	_content.add_child(_separator())

	var heading: Label = Label.new()
	heading.text = "Offer bones"
	heading.add_theme_color_override(&"font_color", MUTED)
	_content.add_child(heading)

	var rows: Array[Dictionary] = _offerable()
	if rows.is_empty():
		var empty: Label = Label.new()
		empty.text = "You have no bones to offer."
		empty.add_theme_color_override(&"font_color", MUTED)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_content.add_child(empty)
	else:
		for row: Dictionary in rows:
			_content.add_child(_offering_row(row))

	_content.add_child(_button("Close", hide))


## Bones in the bag the altar will actually take, newest-value first so the
## best offering is the top button.
func _offerable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table: AltarOfferingTable = AltarOfferingTable.shared()
	if table == null:
		return out
	for slot_uid: Variant in _inventory:
		var slot: Dictionary = _inventory[slot_uid]
		var item_id: int = int(slot.get("id", 0))
		var amount: int = int(slot.get("a", 0))
		if item_id <= 0 or amount <= 0 or bool(slot.get("p", false)):
			continue
		var offering: AltarOffering = table.offering_for(item_id)
		if offering == null or offering.item == null:
			continue
		out.append({
			"uid": int(slot_uid),
			"amount": amount,
			"name": String(offering.item.item_name),
			"icon": offering.item.item_icon,
			"xp": offering.xp,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["xp"]) > int(b["xp"]))
	return out


func _offering_row(row: Dictionary) -> Control:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.text = "%s  x%d      +%d xp each" % [
		row["name"], int(row["amount"]), int(row["xp"])
	]
	button.icon = row["icon"]
	button.expand_icon = true
	button.pressed.connect(_on_offer.bind(int(row["uid"])))
	return button


func _set_points(prayer: Dictionary) -> void:
	if _points_label == null:
		return
	_points_label.text = "Prayer  %d / %d" % [
		int(round(float(prayer.get("points", 0.0)))),
		int(round(float(prayer.get("max", 0.0)))),
	]


func _on_offer(slot_uid: int) -> void:
	if _busy:
		return
	_busy = true
	# Whole stack: the server defaults to it when no amount is sent, and burying
	# bones one at a time is the most tedious thing about this skill elsewhere.
	var result: Array = await Client.request_data_await(
		&"altar.offer", {"uid": slot_uid}, _instance_name()
	)
	_busy = false
	var payload: Dictionary = result[0] if result.size() > 0 and result[0] is Dictionary else {}
	if not bool(payload.get("ok", false)):
		_toast_rejection(payload)
		return
	Toaster.toast("Offered %d — +%d Prayer xp." % [
		int(payload.get("amount", 0)), int(payload.get("xp", 0))
	])
	if bool(payload.get("leveled_up", false)):
		Announcer.announce("Prayer level %d" % int(payload.get("level", 0)))
	# The stack is gone from the bag now — refetch instead of redrawing rows
	# that would still offer it.
	_refresh()


func _on_recharge() -> void:
	if _busy:
		return
	_busy = true
	var result: Array = await Client.request_data_await(
		&"altar.recharge", {}, _instance_name()
	)
	_busy = false
	var payload: Dictionary = result[0] if result.size() > 0 and result[0] is Dictionary else {}
	if not bool(payload.get("ok", false)):
		_toast_rejection(payload)
		return
	Toaster.toast("Your prayer points are restored.")
	_set_points(payload.get("prayer", {}) as Dictionary)


func _toast_rejection(payload: Dictionary) -> void:
	match str(payload.get("reason", "")):
		"already_full":
			Toaster.toast("Your prayer points are already full.")
		"too_far":
			Toaster.toast("Step up to the altar first.")
		"pinned":
			Toaster.toast("Unfavorite those first.")
		"not_an_offering":
			Toaster.toast("The altar has no use for that.")
		"prayer_level":
			Toaster.toast("Requires Prayer %d." % int(payload.get("required_level", 0)))
		"dead":
			Toaster.toast("You cannot do that while dead.")
		_:
			Toaster.toast("Nothing happened.")


func _instance_name() -> String:
	return String(InstanceClient.current.name) if InstanceClient.current else ""


func _build_shell() -> void:
	for child: Node in get_children():
		child.queue_free()
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.7)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	center.add_child(card)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 18)
	pad.add_theme_constant_override(&"margin_right", 18)
	pad.add_theme_constant_override(&"margin_top", 14)
	pad.add_theme_constant_override(&"margin_bottom", 14)
	card.add_child(pad)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 10)
	pad.add_child(_content)


func _separator() -> Control:
	var line: HSeparator = HSeparator.new()
	return line


func _button(text: String, callback: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 38)
	b.pressed.connect(callback)
	return b
