class_name CommandsPanel
extends Control
## Overlay listing chat commands the local player may run. Opened from Settings.
## Role-filtered server-side via chat.commands.list (same rules as /help).

var _list: VBoxContainer
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.72)
	backdrop.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			hide())
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(440, 360)
	center.add_child(card)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 16)
	pad.add_theme_constant_override(&"margin_right", 16)
	pad.add_theme_constant_override(&"margin_top", 12)
	pad.add_theme_constant_override(&"margin_bottom", 12)
	card.add_child(pad)

	var root := VBoxContainer.new()
	root.add_theme_constant_override(&"separation", 8)
	pad.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "Chat Commands"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	header.add_child(title)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(72, 32)
	close.pressed.connect(hide)
	header.add_child(close)

	var hint := Label.new()
	hint.text = "Commands available to you. Type /help <name> in chat for usage."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override(&"font_size", 11)
	hint.add_theme_color_override(&"font_color", Color(0.7, 0.74, 0.8))
	root.add_child(hint)

	_status = Label.new()
	_status.add_theme_font_size_override(&"font_size", 12)
	_status.add_theme_color_override(&"font_color", Color(0.75, 0.78, 0.85))
	root.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_list)

	hide()
	visibility_changed.connect(_on_visibility_changed)


func open() -> void:
	show()
	_load()


func _on_visibility_changed() -> void:
	if visible:
		_load()


func _load() -> void:
	_status.text = "Loading…"
	for child: Node in _list.get_children():
		child.queue_free()
	if InstanceClient.current == null:
		_status.text = "Commands are available while in-game."
		return
	Client.request_data(
		&"chat.commands.list",
		_on_received,
		{},
		InstanceClient.current.name
	)


func _on_received(data: Dictionary) -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	if not bool(data.get("ok", false)):
		_status.text = "Couldn't load commands right now."
		return
	var commands: Array = data.get("commands", [])
	if commands.is_empty():
		_status.text = "No commands available."
		return
	_status.text = "%d command%s" % [commands.size(), "" if commands.size() == 1 else "s"]
	for row: Variant in commands:
		if row is Dictionary:
			_list.add_child(_make_row(row))


func _make_row(row: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 1)

	var name_row := HBoxContainer.new()
	box.add_child(name_row)

	var name_label := Label.new()
	name_label.text = "/" + str(row.get("name", "?"))
	name_label.add_theme_font_size_override(&"font_size", 13)
	name_label.add_theme_color_override(&"font_color", Color(0.95, 0.88, 0.55))
	name_row.add_child(name_label)

	var aliases: Array = row.get("aliases", [])
	if not aliases.is_empty():
		var alias_label := Label.new()
		alias_label.text = "  (" + ", ".join(PackedStringArray(aliases)) + ")"
		alias_label.add_theme_font_size_override(&"font_size", 11)
		alias_label.add_theme_color_override(&"font_color", Color(0.6, 0.65, 0.72))
		name_row.add_child(alias_label)

	var usage := Label.new()
	usage.text = str(row.get("usage", ""))
	usage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	usage.add_theme_font_size_override(&"font_size", 11)
	usage.add_theme_color_override(&"font_color", Color(0.78, 0.8, 0.86))
	box.add_child(usage)
	return box
