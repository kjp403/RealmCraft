extends Control
## Centered online-players roster opened by /players (or /online).


var _card: PanelContainer
var _list: VBoxContainer
var _count_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_shell()
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()


func open(payload: Variant = null) -> void:
	show()
	move_to_front()
	if payload is Dictionary:
		_render(payload as Dictionary)
	else:
		_render({"players": [], "count": 0})


func _build_shell() -> void:
	for child: Node in get_children():
		child.queue_free()

	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.62)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(420, 360)
	_card.add_theme_stylebox_override(&"panel", _card_style())
	center.add_child(_card)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 18)
	pad.add_theme_constant_override(&"margin_right", 18)
	pad.add_theme_constant_override(&"margin_top", 14)
	pad.add_theme_constant_override(&"margin_bottom", 14)
	_card.add_child(pad)

	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 10)
	pad.add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	root.add_child(header)

	var title: Label = Label.new()
	title.text = "Players Online"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	title.add_theme_font_size_override(&"font_size", 22)
	header.add_child(title)

	_count_label = Label.new()
	_count_label.add_theme_color_override(&"font_color", Color(0.82, 0.78, 0.68))
	_count_label.add_theme_font_size_override(&"font_size", 14)
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_count_label)

	var close_x: Button = Button.new()
	close_x.text = UiGlyphs.close()
	close_x.focus_mode = Control.FOCUS_NONE
	close_x.custom_minimum_size = Vector2(34, 34)
	close_x.tooltip_text = "Close"
	close_x.pressed.connect(hide)
	header.add_child(close_x)

	var rule: ColorRect = ColorRect.new()
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(0.78, 0.55, 0.28, 0.55)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(rule)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 240)
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 4)
	scroll.add_child(_list)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(footer)

	var close_btn: Button = Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(120, 36)
	close_btn.pressed.connect(hide)
	footer.add_child(close_btn)


func _card_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.14, 0.96)
	style.border_color = Color(0.78, 0.55, 0.28, 0.85)
	style.set_border_width_all(1)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 8
	return style


func _render(payload: Dictionary) -> void:
	if _list == null:
		_build_shell()
	for child: Node in _list.get_children():
		child.queue_free()

	var players: Array = payload.get("players", [])
	var count: int = int(payload.get("count", players.size()))
	_count_label.text = "%d online" % count

	if players.is_empty():
		var empty: Label = Label.new()
		empty.text = "No one else is online right now."
		empty.add_theme_color_override(&"font_color", Color(0.7, 0.72, 0.76))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(empty)
		return

	var header_row: HBoxContainer = _row(
		"Name", "Lv", "Zone", Color(0.78, 0.55, 0.28), true
	)
	_list.add_child(header_row)

	for entry: Variant in players:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var name_text: String = str(d.get("name", "?"))
		if bool(d.get("self", false)):
			name_text += "  (you)"
		var level_text: String = str(int(d.get("level", 1)))
		var zone_text: String = _pretty_zone(str(d.get("instance", "")))
		var color: Color = Color(1.0, 0.95, 0.8) if bool(d.get("self", false)) else Color(0.9, 0.92, 0.95)
		_list.add_child(_row(name_text, level_text, zone_text, color, false))


func _row(name_text: String, level_text: String, zone_text: String, color: Color, header: bool) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if not header:
		var bg: PanelContainer = PanelContainer.new()
		bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row_style: StyleBoxFlat = StyleBoxFlat.new()
		row_style.bg_color = Color(1, 1, 1, 0.03)
		row_style.content_margin_left = 8
		row_style.content_margin_right = 8
		row_style.content_margin_top = 5
		row_style.content_margin_bottom = 5
		bg.add_theme_stylebox_override(&"panel", row_style)
		var inner: HBoxContainer = HBoxContainer.new()
		inner.add_theme_constant_override(&"separation", 8)
		bg.add_child(inner)
		_add_cols(inner, name_text, level_text, zone_text, color, header)
		row.add_child(bg)
	else:
		_add_cols(row, name_text, level_text, zone_text, color, header)
	return row


func _add_cols(
	parent: HBoxContainer,
	name_text: String,
	level_text: String,
	zone_text: String,
	color: Color,
	header: bool
) -> void:
	var name_l: Label = Label.new()
	name_l.text = name_text
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.add_theme_color_override(&"font_color", color)
	if header:
		name_l.add_theme_font_size_override(&"font_size", 13)
	parent.add_child(name_l)

	var lv: Label = Label.new()
	lv.text = level_text
	lv.custom_minimum_size = Vector2(36, 0)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_theme_color_override(&"font_color", color)
	if header:
		lv.add_theme_font_size_override(&"font_size", 13)
	parent.add_child(lv)

	var zone: Label = Label.new()
	zone.text = zone_text
	zone.custom_minimum_size = Vector2(140, 0)
	zone.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zone.add_theme_color_override(&"font_color", color if header else Color(0.75, 0.78, 0.82))
	if header:
		zone.add_theme_font_size_override(&"font_size", 13)
	parent.add_child(zone)


func _pretty_zone(raw: String) -> String:
	if raw.is_empty():
		return "—"
	var titles: Dictionary = {
		"woodland": "Goblin Woodland",
		"the_hollow": "The Hollow",
		"fungus_cave": "Fungus Cave",
		"overworld": "Castle Garden",
		"hub": "Castle Garden",
		"desert": "Desert",
		"bandit_hideout": "Bandit Hideout",
		"fire_forge": "Fire Forge",
		"sewers": "Sewers",
		"guild_house": "Guild Hall",
		"slayer_house": "Slayer House",
		"sunspire_terraces": "Sunspire Terraces",
		"sunken_tombs": "The Sunken Tombs",
		"gutterworks": "The Gutterworks",
		"drowned_cistern": "The Drowned Cistern",
		"ossuary": "The Ossuary",
		"bellows_gallery": "The Bellows Gallery",
		"cinder_deeps": "The Cinder Deeps",
	}
	var key: String = raw.strip_edges().to_lower()
	if titles.has(key):
		return str(titles[key])
	return raw.replace("_", " ").capitalize()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hide()
