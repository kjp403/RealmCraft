class_name SlayerTracker
extends PanelContainer
## HUD Slayer task readout: current assignment, kills remaining, points, and
## streak. Lives in the upper-right rail directly under the navigation minimap
## (HUD._place_right_rail owns the stacking). Hidden when the player has no
## active task, or when they've switched it off — see [constant SETTING_SECTION]
## / [constant SETTING_PROPERTY], the same client-settings pair the weather layer
## uses, so the choice persists across sessions.
##
## Every label AUTOWRAPS on purpose. A Label reports its full text width as its
## minimum size, and this panel grows leftward (grow_horizontal = BEGIN), so a
## long task line used to stretch the panel clear across the screen and out from
## under the right rail. Wrapping pins the width to the anchored rect instead.

const SETTING_SECTION: StringName = &"general"
const SETTING_PROPERTY: StringName = &"slayer_tracker"

var _content: VBoxContainer
var _cached: Dictionary = {}


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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override(&"panel", _make_panel_style())

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 10)
	margin.add_theme_constant_override(&"margin_right", 6)
	for side: String in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)

	_content = VBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override(&"separation", 2)
	margin.add_child(_content)

	hide()
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
		hide()
		return
	Client.request_data(&"slayer.info", _on_received, {}, InstanceClient.current.name)


func _on_received(data: Dictionary) -> void:
	if not bool(data.get("ok", false)):
		hide()
		return
	_cached = data.duplicate(true)
	_display(_cached)


func _display(data: Dictionary) -> void:
	for child in _content.get_children():
		child.queue_free()

	var has_task: bool = data.has("display_name") and not str(data.get("display_name", "")).is_empty()
	if not has_task or not is_enabled():
		hide()
		return

	# Title row: the assignment, plus a hide affordance. Switching it off here
	# writes the same setting the Settings panel toggles, so the two can't drift.
	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override(&"separation", 4)
	_content.add_child(title_row)

	var title: Label = Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override(&"font_size", 13)
	title.text = "Slayer: %s" % str(data.get("display_name", "?"))
	title.add_theme_color_override(&"font_color", _accent_color())
	title_row.add_child(title)

	var hide_button: Button = Button.new()
	hide_button.text = "✕"
	hide_button.flat = true
	hide_button.focus_mode = Control.FOCUS_NONE
	hide_button.custom_minimum_size = Vector2(18, 18)
	hide_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hide_button.add_theme_font_size_override(&"font_size", 10)
	hide_button.tooltip_text = "Hide the Slayer tracker (turn it back on in Settings)."
	hide_button.pressed.connect(_on_hide_pressed)
	title_row.add_child(hide_button)

	var progress: Label = Label.new()
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	progress.add_theme_font_size_override(&"font_size", 12)
	var remaining: int = int(data.get("remaining", 0))
	var assigned: int = int(data.get("assigned_amount", 0))
	var killed: int = maxi(0, assigned - remaining)
	progress.text = "Kills %d / %d  ·  %d left" % [killed, assigned, remaining]
	progress.add_theme_color_override(&"font_color", Color(0.92, 0.9, 0.82))
	_content.add_child(progress)

	var meta: Label = Label.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.add_theme_font_size_override(&"font_size", 11)
	meta.text = "%d points  ·  streak %d" % [
		int(data.get("points", 0)),
		int(data.get("streak", 0)),
	]
	meta.add_theme_color_override(&"font_color", Color(0.7, 0.74, 0.8))
	_content.add_child(meta)

	show()


func _on_hide_pressed() -> void:
	set_enabled(false)
	Toaster.toast("Slayer tracker hidden — turn it back on in Settings.")


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
