class_name SlayerTracker
extends PanelContainer
## HUD Slayer task readout: current assignment, kills remaining, points, and
## streak. Hover the badge for XP/kill and where to hunt. A compact badge pinned
## to the top-LEFT corner (HUD._place_slayer_tracker owns the placement). Hidden
## when the player has no active task, or when they've switched it off — see
## [constant SETTING_SECTION] / [constant SETTING_PROPERTY], the same
## client-settings pair the weather layer uses, so the choice persists across
## sessions.
##
## Nothing wraps: the panel shrinks to its contents and grows rightward from the
## screen edge, so labels stay on one line and the badge stays small. Keep the
## text terse for that reason — a long assignment name widens the badge.

const SETTING_SECTION: StringName = &"general"
const SETTING_PROPERTY: StringName = &"slayer_tracker"

var _content: VBoxContainer
var _cached: Dictionary = {}
## Web-only hover card. Godot tooltip_text popups do not show in the HTML5 export.
var _hint_panel: PanelContainer
var _hint_label: Label
var _hover_copy: String = ""


## Whether the player has the tracker switched on (default true). Static so the
## settings panels can read/write it without reaching into the HUD.
static func is_enabled() -> bool:
	var value: Variant = ClientState.settings.get_value(SETTING_SECTION, SETTING_PROPERTY)
	if value == null:
		value = ClientState.settings.get_default(SETTING_SECTION, SETTING_PROPERTY)
	return true if value == null else bool(value)


static func set_enabled(enabled: bool) -> void:
	ClientState.settings.set_value(SETTING_SECTION, SETTING_PROPERTY, enabled)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = ""
	add_theme_stylebox_override(&"panel", _make_panel_style())

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	add_child(margin)

	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override(&"separation", 0)
	margin.add_child(_content)

	hide()
	if UiGlyphs.is_web():
		_build_web_hint()
		mouse_entered.connect(_show_web_hint)
		mouse_exited.connect(_hide_web_hint)
		gui_input.connect(_on_web_gui_input)
	Client.subscribe(&"slayer.update", _on_slayer_update)
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): refresh())
	ClientState.settings.setting_changed.connect(_on_setting_changed)
	refresh()


func refresh() -> void:
	_refresh()


func _on_setting_changed(
	section: StringName,
	property: StringName,
	_value: Variant
) -> void:
	if section != SETTING_SECTION or property != SETTING_PROPERTY:
		return
	# Re-show instantly from cache, then re-poll — the cache may be empty (or
	# stale) if the tracker was switched off across a task change.
	_display(_cached)
	if is_enabled():
		_refresh()


func _on_slayer_update(payload: Dictionary) -> void:
	# Live kill advances / completions arrive as pushes — merge into cache so
	# the tracker ticks without waiting on another round-trip.
	if not _cached.is_empty():
		if payload.has("remaining"):
			_cached["remaining"] = int(payload["remaining"])
		if bool(payload.get("complete", false)):
			_cached.erase("display_name")
			_cached.erase("remaining")
			_cached.erase("assigned_amount")
			if payload.has("points_gained"):
				_cached["points"] = int(_cached.get("points", 0)) + int(payload["points_gained"])
			if payload.has("streak"):
				_cached["streak"] = int(payload["streak"])
		_display(_cached)
	_refresh()


func _refresh() -> void:
	if InstanceClient.current == null:
		_hover_copy = ""
		tooltip_text = ""
		_hide_web_hint()
		hide()
		return
	Client.request_data(&"slayer.info", _on_received, {}, InstanceClient.current.name)


func _on_received(data: Dictionary) -> void:
	if not bool(data.get("ok", false)):
		_hover_copy = ""
		tooltip_text = ""
		_hide_web_hint()
		hide()
		return
	_cached = data.duplicate(true)
	_display(_cached)


func _display(data: Dictionary) -> void:
	for child in _content.get_children():
		child.queue_free()

	var has_task: bool = data.has("display_name") and not str(data.get("display_name", "")).is_empty()
	if not has_task or not is_enabled():
		_hover_copy = ""
		tooltip_text = ""
		_hide_web_hint()
		hide()
		return

	# Title row: the assignment, plus a hide affordance. Switching it off here
	# writes the same setting the Settings panel toggles, so the two can't drift.
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override(&"separation", 3)
	_content.add_child(title_row)

	var title: Label = Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_theme_font_size_override(&"font_size", 9)
	title.text = str(data.get("display_name", "?"))
	title.add_theme_color_override(&"font_color", _accent_color())
	title_row.add_child(title)

	var hide_button: Button = Button.new()
	hide_button.text = UiGlyphs.close()
	hide_button.flat = true
	hide_button.focus_mode = Control.FOCUS_NONE
	hide_button.custom_minimum_size = Vector2(12, 12)
	hide_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hide_button.add_theme_font_size_override(&"font_size", 8)
	hide_button.add_theme_stylebox_override(&"normal", StyleBoxEmpty.new())
	if not UiGlyphs.is_web():
		hide_button.tooltip_text = "Hide the Slayer tracker (turn it back on in Settings)."
	hide_button.pressed.connect(_on_hide_pressed)
	title_row.add_child(hide_button)

	var progress: Label = Label.new()
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_theme_font_size_override(&"font_size", 9)
	var remaining: int = int(data.get("remaining", 0))
	var assigned: int = int(data.get("assigned_amount", 0))
	var killed: int = maxi(0, assigned - remaining)
	progress.text = "%d/%d · %dp · x%d" % [
		killed,
		assigned,
		int(data.get("points", 0)),
		int(data.get("streak", 0)),
	]
	progress.add_theme_color_override(&"font_color", Color(0.92, 0.9, 0.82))
	_content.add_child(progress)

	_hover_copy = _hover_text(data, killed, assigned, remaining)
	tooltip_text = "" if UiGlyphs.is_web() else _hover_copy
	show()


func _on_hide_pressed() -> void:
	_hide_web_hint()
	set_enabled(false)
	Toaster.toast("Slayer tracker hidden — turn it back on in Settings.")


func _build_web_hint() -> void:
	_hint_panel = PanelContainer.new()
	_hint_panel.visible = false
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.z_index = 80
	_hint_panel.add_theme_stylebox_override(&"panel", _make_panel_style())
	var pad: MarginContainer = MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	_hint_label = Label.new()
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_size_override(&"font_size", 10)
	_hint_label.add_theme_color_override(&"font_color", Color(0.92, 0.9, 0.82))
	pad.add_child(_hint_label)
	_hint_panel.add_child(pad)
	add_child(_hint_panel)
	_hint_panel.set_as_top_level(true)


func _show_web_hint() -> void:
	if _hint_panel == null or _hint_label == null or _hover_copy.is_empty() or not visible:
		return
	_hint_label.text = _hover_copy
	_hint_panel.visible = true
	_hint_panel.reset_size()
	_hint_panel.global_position = global_position + Vector2(0.0, size.y + 4.0)


func _hide_web_hint() -> void:
	if _hint_panel != null:
		_hint_panel.visible = false


func _on_web_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if _hint_panel != null and _hint_panel.visible:
			_hide_web_hint()
		else:
			_show_web_hint()


func _hover_text(data: Dictionary, killed: int, assigned: int, remaining: int) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var where: String = str(data.get("location_hint", "")).strip_edges()
	if not where.is_empty():
		lines.append(where)
	var xp_min: int = int(data.get("xp_per_kill_min", 0))
	var xp_max: int = int(data.get("xp_per_kill_max", xp_min))
	if xp_min > 0:
		if xp_max > xp_min:
			lines.append("%d-%d XP/kill" % [xp_min, xp_max])
		else:
			lines.append("%d XP/kill" % xp_min)
	lines.append("%d/%d killed · %d left" % [killed, assigned, remaining])
	lines.append("%d points · streak %d" % [
		int(data.get("points", 0)),
		int(data.get("streak", 0)),
	])
	return "\n".join(lines)


func _make_panel_style() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.08, 0.6)
	box.set_border_width_all(1)
	box.border_color = Color(1.0, 1.0, 1.0, 0.07)
	box.set_corner_radius_all(4)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 5
	return box


func _accent_color() -> Color:
	var saved: Variant = ClientState.settings.get_value(&"gateway", &"palette")
	var slug: StringName = StringName(saved) if saved is String or saved is StringName else ThemePalettes.DEFAULT
	return ThemePalettes.accent(slug)
