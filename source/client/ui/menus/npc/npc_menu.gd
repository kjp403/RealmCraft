extends Control
## Responsive compact NPC dialogue card.
## NPCs with up to three choices use one column. NPCs with more choices use
## two columns so the card stays compact and clear of the bottom-right HUD dock.

const TYPE_CPS: float = 45.0
const CARD_WIDTH: float = 500.0
const SCREEN_MARGIN: float = 16.0
const BOTTOM_MARGIN: float = 64.0
const MIN_CARD_HEIGHT: float = 142.0
const MAX_CARD_HEIGHT: float = 340.0
const BUTTON_HEIGHT: float = 30.0
const OPTION_SEPARATION: int = 5
const MULTI_COLUMN_THRESHOLD: int = 3
const MULTI_COLUMN_COUNT: int = 2

var _data: Dictionary = {}
var _lines: Array = []
var _line_index: int = 0
var _typing: bool = false
var _option_rows: int = 1

var _card: PanelContainer
var _name_label: Label
var _text: RichTextLabel
var _options: VBoxContainer
var _type_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_place_card)


func open(arg: Variant) -> void:
	_data = arg if arg is Dictionary else {}
	_cancel_typewriter()

	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	_build()
	_show_options()


func _build() -> void:
	_card = PanelContainer.new()
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card)

	var padding := MarginContainer.new()
	padding.add_theme_constant_override(&"margin_left", 12)
	padding.add_theme_constant_override(&"margin_right", 12)
	padding.add_theme_constant_override(&"margin_top", 10)
	padding.add_theme_constant_override(&"margin_bottom", 10)
	_card.add_child(padding)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 6)
	padding.add_child(column)

	_name_label = Label.new()
	_name_label.text = str(_data.get("name", ""))
	_name_label.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.88, 0.55)
	)
	_name_label.add_theme_font_size_override(&"font_size", 15)
	column.add_child(_name_label)

	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = false
	_text.fit_content = true
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(0.0, 40.0)
	_text.add_theme_font_size_override(&"normal_font_size", 13)
	column.add_child(_text)

	column.add_child(HSeparator.new())

	_options = VBoxContainer.new()
	_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options.add_theme_constant_override(
		&"separation",
		OPTION_SEPARATION
	)
	column.add_child(_options)

	_place_card()


func _place_card() -> void:
	if _card == null:
		return

	var available_width: float = maxf(
		280.0,
		size.x - SCREEN_MARGIN * 2.0
	)
	var width: float = minf(CARD_WIDTH, available_width)

	_card.offset_left = -width * 0.5
	_card.offset_right = width * 0.5
	_card.offset_bottom = -BOTTOM_MARGIN

	_fit_card.call_deferred()


func _fit_card() -> void:
	if _card == null or _text == null or _options == null:
		return

	var text_height: float = clampf(
		_text.get_content_height(),
		40.0,
		140.0
	)
	var options_height: float = (
		float(_option_rows) * BUTTON_HEIGHT
	)

	if _option_rows > 1:
		options_height += float(
			_option_rows - 1
		) * float(OPTION_SEPARATION)

	# Padding + name + dialogue + separator + response rows.
	var needed_height: float = (
		20.0
		+ 22.0
		+ 6.0
		+ text_height
		+ 13.0
		+ options_height
	)
	var available_height: float = maxf(
		MIN_CARD_HEIGHT,
		size.y - BOTTOM_MARGIN - SCREEN_MARGIN
	)
	var height: float = clampf(
		needed_height,
		MIN_CARD_HEIGHT,
		minf(MAX_CARD_HEIGHT, available_height)
	)

	_card.offset_top = _card.offset_bottom - height


func _show_options() -> void:
	_set_text(str(_data.get("greeting", "...")))
	_clear_options()

	var entries: Array = _data.get("entries", [])
	var column_count: int = (
		MULTI_COLUMN_COUNT
		if entries.size() > MULTI_COLUMN_THRESHOLD
		else 1
	)

	if not entries.is_empty():
		var choices := GridContainer.new()
		choices.columns = column_count
		choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choices.add_theme_constant_override(
			&"h_separation",
			OPTION_SEPARATION
		)
		choices.add_theme_constant_override(
			&"v_separation",
			OPTION_SEPARATION
		)
		_options.add_child(choices)

		for entry: Dictionary in entries:
			choices.add_child(_option_button(entry))

	var goodbye := _make_button("Goodbye")
	goodbye.pressed.connect(_close_dialogue)
	_options.add_child(goodbye)

	var choice_rows: int = ceili(
		float(entries.size()) / float(column_count)
	)
	_option_rows = choice_rows + 1
	_fit_card.call_deferred()


func _option_button(entry: Dictionary) -> Button:
	var icon: String = str(entry.get("icon", ""))
	var label: String = str(entry.get("label", "?"))
	var display_text: String = (
		"%s  %s" % [icon, label]
		if not icon.is_empty()
		else label
	)
	var button := _make_button(display_text)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = label
	button.pressed.connect(_on_entry.bind(entry))
	return button


func _make_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_theme_font_size_override(&"font_size", 12)
	return button


func _on_entry(entry: Dictionary) -> void:
	if entry.has("lines"):
		_lines = entry["lines"] if entry["lines"] is Array else []
		_line_index = 0
		_show_line()
	elif entry.has("request"):
		# Immediate server action (e.g. WarpInteraction → npc.warp, or
		# RemoteBankInteraction → bank.remote_open then open the bank menu).
		_close_dialogue()
		if InstanceClient.current == null:
			return
		var req: StringName = StringName(str(entry["request"]))
		var req_args: Dictionary = entry.get("args", {}) if entry.get("args", {}) is Dictionary else {}
		var open_menu: StringName = StringName(str(entry.get("open_menu", "")))
		var menu_arg: Variant = entry.get("arg", null)
		var on_result := func(data: Dictionary) -> void:
			if data.get("ok", false):
				if not open_menu.is_empty():
					if data.has("inventory"):
						ClientState.inventory_changed.emit({"quiet": true})
					ClientState.open_menu_requested.emit(open_menu, menu_arg)
				return
			var reason: String = str(data.get("reason", ""))
			if reason == "too_far":
				Toaster.toast("Too far.")
			elif reason == "wardstone":
				pass # server already pushed a system line
			elif reason == "no_quest" or reason == "in_run" or reason == "jailed":
				pass # server already pushed a system line
			elif reason == "already_done":
				pass # kill is complete — button is a no-op
			elif reason == "gold":
				var cost: int = int(data.get("cost", 0))
				if cost > 0:
					Toaster.toast("You need %d gold." % cost)
				else:
					Toaster.toast("You cannot afford that.")
			elif not open_menu.is_empty():
				Toaster.toast("Could not open the bank.")
			elif not reason.is_empty() and reason != "jailed":
				Toaster.toast("Cannot travel right now.")
		Client.request_data(
			req,
			on_result,
			req_args,
			String(InstanceClient.current.name)
		)
	elif entry.has("tutorial"):
		# A guided lesson (TutorialInteraction) — the coach takes over the screen,
		# so the dialogue card gets out of the way first.
		_close_dialogue()
		ClientState.tutorial_requested.emit(
			StringName(str(entry["tutorial"]))
		)
	elif entry.has("menu"):
		_close_dialogue()
		ClientState.open_menu_requested.emit(
			entry["menu"],
			entry.get("arg", null)
		)


func _show_line() -> void:
	if _line_index >= _lines.size():
		_show_options()
		return

	_set_text(str(_lines[_line_index]))
	_clear_options()

	var label: String = (
		"Continue"
		if _line_index < _lines.size() - 1
		else "Back"
	)
	var continue_button := _make_button(label)
	continue_button.pressed.connect(_on_continue)
	_options.add_child(continue_button)
	_option_rows = 1
	_fit_card.call_deferred()


func _on_continue() -> void:
	if _typing:
		_finish_typing()
		return

	_line_index += 1
	_show_line()


func _set_text(bbcode: String) -> void:
	_text.text = bbcode
	_text.visible_ratio = 0.0
	_typing = true
	_cancel_typewriter(false)

	var characters: int = maxi(
		1,
		_text.get_total_character_count()
	)
	_type_tween = create_tween()
	_type_tween.tween_property(
		_text,
		^"visible_ratio",
		1.0,
		float(characters) / TYPE_CPS
	)
	_type_tween.tween_callback(_on_typewriter_finished)
	_fit_card.call_deferred()


func _on_typewriter_finished() -> void:
	_typing = false


func _finish_typing() -> void:
	_cancel_typewriter()
	_text.visible_ratio = 1.0


func _cancel_typewriter(clear_typing: bool = true) -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_type_tween = null

	if clear_typing:
		_typing = false


func _clear_options() -> void:
	if _options == null:
		return

	for child: Node in _options.get_children():
		_options.remove_child(child)
		child.queue_free()


func _close_dialogue() -> void:
	_cancel_typewriter()
	hide()
