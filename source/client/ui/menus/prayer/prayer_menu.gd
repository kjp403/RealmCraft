extends Control
## The prayer book: every prayer, what it does, and a switch. Opened from the
## Skills panel or a keybind (open_menu_requested(&"prayer")).
##
## The server is authoritative on what is on — every toggle response carries a
## full status snapshot and this redraws from THAT, never from what it hoped
## would happen. A refused toggle therefore self-corrects instead of leaving a
## button stuck in the wrong state.

const GOLD: Color = Color(1.0, 0.95, 0.8)
const MUTED: Color = Color(0.72, 0.76, 0.84)
const CYAN: Color = Color(0.37, 0.83, 0.83)
const LOCKED: Color = Color(0.62, 0.45, 0.45)
const ON_TINT: Color = Color(0.55, 0.85, 0.55)

var _content: VBoxContainer
var _busy: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The HUD only calls open() when a menu is opened WITH an argument, and the
	# prayer book is opened without one (dock icon / menu entry). Building on
	# show keeps the panel from coming up as an empty full-screen Control that
	# eats every click with no Close button — which reads as a frozen game.
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()


func open(_arg: Variant = null) -> void:
	_refresh()


func _refresh() -> void:
	# Draw a loading card with a live Close button BEFORE waiting on the server.
	# A full-screen Control with nothing in it blocks the whole game, so the
	# panel must always be escapable even if the request never comes back.
	_build_shell()
	var loading: Label = Label.new()
	loading.text = "Prayers"
	loading.add_theme_font_size_override(&"font_size", 22)
	loading.add_theme_color_override(&"font_color", GOLD)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(loading)
	_content.add_child(_button("Close", hide))

	var result: Array = await Client.request_data_await(
		&"prayer.state", {}, _instance_name()
	)
	if not visible:
		return
	_build(result[0] if result.size() > 0 and result[0] is Dictionary else {})


func _build(state: Dictionary) -> void:
	_build_shell()

	var level: int = int(state.get("level", 1))
	var active: Array = state.get("active", [])

	var title: Label = Label.new()
	title.text = "Prayers"
	title.add_theme_font_size_override(&"font_size", 22)
	title.add_theme_color_override(&"font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)

	var points: Label = Label.new()
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points.add_theme_color_override(&"font_color", CYAN)
	var drain: float = float(state.get("drain", 0.0))
	points.text = "%d / %d points" % [
		int(round(float(state.get("points", 0.0)))),
		int(round(float(state.get("max", 0.0)))),
	]
	if drain > 0.0:
		# The number players actually plan around: how long the pool lasts at
		# the current burn.
		var seconds_left: float = float(state.get("points", 0.0)) / (drain / 60.0)
		points.text += "   —   draining %s/min (%s left)" % [
			_trim(drain), _duration(seconds_left)
		]
	_content.add_child(points)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 340)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)

	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 6)
	scroll.add_child(list)

	for prayer: PrayerResource in PrayerBook.PRAYERS:
		if prayer == null:
			continue
		list.add_child(_prayer_row(prayer, level, active.has(String(prayer.slug))))

	_content.add_child(_button("Close", hide))


func _prayer_row(prayer: PrayerResource, level: int, is_on: bool) -> Control:
	var unlocked: bool = level >= prayer.required_level
	var row: PanelContainer = PanelContainer.new()
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override(StringName("margin_" + side), 10)
	for side: String in ["top", "bottom"]:
		pad.add_theme_constant_override(StringName("margin_" + side), 6)
	row.add_child(pad)

	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	line.alignment = BoxContainer.ALIGNMENT_BEGIN
	pad.add_child(line)

	# Prayer icon, if one is authored.
	if prayer.icon != null:
		var icon: TextureRect = TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.texture = prayer.icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color.WHITE if unlocked else Color(0.5, 0.5, 0.5)
		line.add_child(icon)

	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)

	var name_label: Label = Label.new()
	name_label.text = prayer.display_name
	name_label.add_theme_color_override(
		&"font_color", ON_TINT if is_on else (GOLD if unlocked else LOCKED)
	)
	text.add_child(name_label)

	var detail: Label = Label.new()
	detail.add_theme_color_override(&"font_color", MUTED)
	detail.add_theme_font_size_override(&"font_size", 12)
	if unlocked:
		detail.text = "%s   ·   %s" % [prayer.describe_modifiers(), prayer.describe_drain()]
	else:
		detail.text = "Requires Prayer %d" % prayer.required_level
	text.add_child(detail)

	var toggle: Button = Button.new()
	toggle.custom_minimum_size = Vector2(78, 34)
	toggle.text = "On" if is_on else "Off"
	toggle.disabled = not unlocked
	toggle.pressed.connect(_on_toggle.bind(prayer.slug, not is_on))
	line.add_child(toggle)
	return row


func _on_toggle(slug: StringName, want_on: bool) -> void:
	if _busy:
		return
	_busy = true
	var result: Array = await Client.request_data_await(
		&"prayer.toggle", {"prayer": String(slug), "on": want_on}, _instance_name()
	)
	_busy = false
	var payload: Dictionary = result[0] if result.size() > 0 and result[0] is Dictionary else {}
	if not bool(payload.get("ok", false)):
		match str(payload.get("reason", "")):
			"no_points":
				Toaster.toast("You have no prayer points left.")
			"prayer_level":
				Toaster.toast("Requires Prayer %d." % int(payload.get("required_level", 0)))
			"dead":
				Toaster.toast("You cannot pray while dead.")
			_:
				Toaster.toast("That prayer did not take.")
	# Redraw from the server's snapshot either way — it rides along on refusals
	# too, so the buttons always end up matching the server.
	if visible:
		_build(payload)


func _trim(value: float) -> String:
	return ("%d" % int(value)) if is_equal_approx(value, roundf(value)) else ("%.1f" % value)


func _duration(seconds: float) -> String:
	if seconds >= 60.0:
		return "%dm %ds" % [int(seconds / 60.0), int(seconds) % 60]
	return "%ds" % int(seconds)


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
	card.custom_minimum_size = Vector2(460, 0)
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


func _button(text: String, callback: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 38)
	b.pressed.connect(callback)
	return b
