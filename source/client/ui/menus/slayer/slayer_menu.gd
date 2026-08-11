extends Control
## Slayer master panel — opened by SlayerInteraction via HUD.display_menu("slayer", master_key).

var _master_key: String = ""
var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Client.subscribe(&"slayer.update", _on_slayer_update)


func open(master_key: Variant) -> void:
	_master_key = str(master_key) if master_key != null else ""
	_build_shell()
	_set_message("Loading…")
	_refresh()


func _build_shell() -> void:
	for child: Node in get_children():
		child.queue_free()
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.7)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(420, 0)
	center.add_child(card)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 18)
	pad.add_theme_constant_override(&"margin_right", 18)
	pad.add_theme_constant_override(&"margin_top", 14)
	pad.add_theme_constant_override(&"margin_bottom", 14)
	card.add_child(pad)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 10)
	pad.add_child(_content)


func _refresh() -> void:
	Client.request_data(
		&"slayer.status",
		_apply_state,
		{"master": _master_key},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _apply_state(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		var reason: String = str(response.get("reason", ""))
		Toaster.toast({
			"too_far": "You're too far from the Slayer master.",
			"no_master": "Slayer master not found.",
			"no_player": "Slayer unavailable.",
			"already_has_task": "You already have a Slayer task.",
			"master_level_too_low": "Your Slayer level is too low for this master.",
			"no_eligible_tasks": "No tasks available right now.",
			"no_active_task": "You don't have a task to change.",
			"wrong_master": "Only the master who gave this task can change it.",
			"not_enough_points": "Not enough Slayer points.",
		}.get(reason, "Slayer unavailable."))
		if reason in ["too_far", "no_master", "no_player"]:
			hide()
			return
		# Soft failures keep the panel open — refresh from status.
		_refresh()
		return
	_render(response)


func _render(data: Dictionary) -> void:
	if _content == null:
		_build_shell()
	for c: Node in _content.get_children():
		c.queue_free()

	var master_name: String = str(data.get("master_name", "Slayer Master"))
	var title := Label.new()
	title.text = master_name
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	_content.add_child(title)

	var greeting := Label.new()
	greeting.text = str(data.get("greeting", ""))
	greeting.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	greeting.add_theme_color_override(&"font_color", Color(0.82, 0.84, 0.9))
	_content.add_child(greeting)

	var stats := Label.new()
	stats.text = "Slayer %d  ·  %d points  ·  streak %d" % [
		int(data.get("level", 1)),
		int(data.get("points", 0)),
		int(data.get("streak", 0)),
	]
	stats.add_theme_font_size_override(&"font_size", 12)
	stats.add_theme_color_override(&"font_color", Color(0.7, 0.74, 0.8))
	_content.add_child(stats)

	var has_task: bool = data.has("display_name") and not str(data.get("display_name", "")).is_empty()
	if has_task:
		var task := Label.new()
		task.text = "Task: %s  (%d / %d remaining)" % [
			str(data.get("display_name", "?")),
			int(data.get("remaining", 0)),
			int(data.get("assigned_amount", 0)),
		]
		task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		task.add_theme_color_override(&"font_color", Color(0.95, 0.88, 0.6))
		_content.add_child(task)
		var notes: String = str(data.get("guide_notes", ""))
		if not notes.is_empty():
			var guide := Label.new()
			guide.text = notes
			guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			guide.add_theme_font_size_override(&"font_size", 12)
			guide.add_theme_color_override(&"font_color", Color(0.65, 0.7, 0.78))
			_content.add_child(guide)
	else:
		var none := Label.new()
		none.text = "No active task."
		none.add_theme_color_override(&"font_color", Color(0.65, 0.7, 0.78))
		_content.add_child(none)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(buttons)

	if not has_task:
		var assign := Button.new()
		assign.text = "Get a task"
		assign.custom_minimum_size = Vector2(0, 40)
		assign.disabled = int(data.get("level", 1)) < int(data.get("min_slayer_level", 1))
		assign.pressed.connect(_on_assign)
		buttons.add_child(assign)
	else:
		var skip := Button.new()
		if bool(data.get("free_reassign", false)):
			skip.text = "New task (resets streak)"
		else:
			skip.text = "Skip (%d pts)" % int(data.get("reassign_point_cost", 30))
		skip.custom_minimum_size = Vector2(0, 40)
		skip.pressed.connect(_on_skip)
		buttons.add_child(skip)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(hide)
	buttons.add_child(close)


func _on_assign() -> void:
	Client.request_data(
		&"slayer.assign",
		_apply_state,
		{"master": _master_key},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _on_skip() -> void:
	Client.request_data(
		&"slayer.skip",
		_apply_state,
		{"master": _master_key},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _on_slayer_update(_payload: Dictionary) -> void:
	if visible and not _master_key.is_empty():
		_refresh()


func _set_message(text: String) -> void:
	if _content == null:
		_build_shell()
	for c: Node in _content.get_children():
		c.queue_free()
	var label := Label.new()
	label.text = text
	_content.add_child(label)
