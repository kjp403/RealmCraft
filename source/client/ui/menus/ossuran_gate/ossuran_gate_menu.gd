extends Control
## The Ossuran portal ready-up panel. Opened by walking into the OssuranPortal
## (Portal.lobby_gate → open_menu_requested(&"ossuran_gate")). Everyone at the
## portal readies up; the leader Enters and OssuranGateService moves the whole
## party into a fresh private copy of Ossuran's Ruin.
##
## Server side is `ossuran.gate` (request) + `ossuran.gate.update` /
## `ossuran.gate.entered` (pushes). This panel is pure presentation + wire.

var _content: VBoxContainer
var _self_ready: bool = false
var _is_leader: bool = false
var _all_ready: bool = false
var _subscribed: bool = false
## True between a successful join and the panel closing — gates the leave-on-hide
## so a stray visibility flip can't spam the server.
var _in_lobby: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visibility_changed.connect(_on_visibility_changed)


func open(_arg: Variant = null) -> void:
	if not _subscribed:
		Client.subscribe(&"ossuran.gate.update", _on_update)
		Client.subscribe(&"ossuran.gate.entered", func(_p: Dictionary) -> void:
			_in_lobby = false
			hide())
		_subscribed = true
	_self_ready = false
	_in_lobby = true
	_request("join")


func _on_visibility_changed() -> void:
	# Closing the panel (Esc, click-away) drops us from the lobby so a stale name
	# doesn't sit in everyone else's roster. Entering the run also hides the
	# panel — the server already moved us, and the leave then just no-ops.
	if not visible and _in_lobby:
		_in_lobby = false
		_request("leave")


func _request(action: String) -> void:
	Client.request_data(
		&"ossuran.gate", _on_update, {"action": action},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _on_update(payload: Dictionary) -> void:
	if not bool(payload.get("ok", false)):
		return
	if bool(payload.get("started", false)):
		_in_lobby = false
		hide()
		return
	_is_leader = bool(payload.get("is_leader", false))
	_all_ready = bool(payload.get("all_ready", false))
	_rebuild(payload)


func _rebuild(payload: Dictionary) -> void:
	_build_shell()

	var title: Label = Label.new()
	title.text = "Ossuran's Ruin"
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", Color(0.62, 0.78, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)

	var warn: Label = Label.new()
	warn.text = "The hardest fight in the game. Your whole party enters together, into its own instance."
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.add_theme_color_override(&"font_color", Color(0.8, 0.84, 0.9))
	warn.add_theme_font_size_override(&"font_size", 12)
	_content.add_child(warn)

	var members: Array = payload.get("members", [])
	var capacity: int = int(payload.get("capacity", 5))
	var roster_title: Label = Label.new()
	roster_title.text = "Party  (%d / %d)" % [members.size(), capacity]
	roster_title.add_theme_color_override(&"font_color", Color(0.75, 0.78, 0.86))
	roster_title.add_theme_font_size_override(&"font_size", 12)
	_content.add_child(roster_title)

	for entry: Variant in members:
		_content.add_child(_roster_row(entry as Dictionary))

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 10)
	_content.add_child(buttons)

	var ready_btn: Button = _button(
		"Not Ready" if _self_ready else "Ready",
		func() -> void:
			_self_ready = not _self_ready
			_request("ready" if _self_ready else "unready")
	)
	buttons.add_child(ready_btn)

	if _is_leader:
		var enter_btn: Button = _button("Enter", func() -> void: _request("start"))
		enter_btn.disabled = not _all_ready
		enter_btn.tooltip_text = "" if _all_ready else "Everyone must be ready."
		buttons.add_child(enter_btn)

	buttons.add_child(_button("Leave", hide))


func _roster_row(entry: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)

	var tick: Label = Label.new()
	tick.text = "✓" if bool(entry.get("ready", false)) else "•"
	tick.add_theme_color_override(
		&"font_color",
		Color(0.45, 0.9, 0.5) if bool(entry.get("ready", false)) else Color(0.6, 0.6, 0.66)
	)
	tick.custom_minimum_size = Vector2(16, 0)
	row.add_child(tick)

	var name_label: Label = Label.new()
	var nm: String = str(entry.get("name", "?"))
	name_label.text = ("%s  (leader)" % nm) if bool(entry.get("leader", false)) else nm
	name_label.add_theme_color_override(&"font_color", Color(0.9, 0.92, 0.98))
	row.add_child(name_label)
	return row


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
	card.custom_minimum_size = Vector2(360, 0)
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
	b.custom_minimum_size = Vector2(104, 38)
	b.pressed.connect(callback)
	return b
