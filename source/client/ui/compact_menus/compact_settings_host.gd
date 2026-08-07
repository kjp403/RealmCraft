extends PanelContainer

const PANEL_SIZE := Vector2(180.0, 262.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 52.0
const SECTION := &"general"

@onready var title_label: Label = (
	$MarginContainer/MainColumn/Header/TitleLabel
)
@onready var header_spacer: Control = (
	$MarginContainer/MainColumn/Header/HeaderSpacer
)
@onready var close_button: Button = (
	$MarginContainer/MainColumn/Header/CloseButton
)
@onready var content: MarginContainer = (
	$MarginContainer/MainColumn/Content
)

var _music_slider: HSlider
var _sound_slider: HSlider
var _zoom_slider: HSlider
var _weather_toggle: CheckButton
var _music_value: Label
var _sound_value: Label
var _zoom_value: Label
var _syncing: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

	content.add_theme_constant_override(&"margin_left", 7)
	content.add_theme_constant_override(&"margin_right", 7)
	content.add_theme_constant_override(&"margin_top", 4)
	content.add_theme_constant_override(&"margin_bottom", 5)

	header_spacer.hide()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "Settings"

	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()

	_build_layout()

	close_button.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)
	ClientState.settings.setting_changed.connect(_on_setting_changed)

	var hud := get_parent() as Control
	if hud != null:
		hud.resized.connect(_place_panel)

	_sync_controls()
	call_deferred(&"_place_panel")
	hide()


func _build_layout() -> void:
	var main_box := VBoxContainer.new()
	main_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_box.add_theme_constant_override(&"separation", 5)
	content.add_child(main_box)

	var music_controls: Dictionary = _add_slider_setting(
		main_box,
		"Music",
		&"music_volume",
		0.0,
		1.0,
		0.05
	)
	_music_slider = music_controls["slider"]
	_music_value = music_controls["value"]

	var sound_controls: Dictionary = _add_slider_setting(
		main_box,
		"Sound effects",
		&"sound_volume",
		0.0,
		1.0,
		0.05
	)
	_sound_slider = sound_controls["slider"]
	_sound_value = sound_controls["value"]

	var zoom_controls: Dictionary = _add_slider_setting(
		main_box,
		"Camera zoom",
		&"camera_zoom",
		1.0,
		4.0,
		0.25
	)
	_zoom_slider = zoom_controls["slider"]
	_zoom_value = zoom_controls["value"]

	_weather_toggle = CheckButton.new()
	_weather_toggle.text = "Weather effects"
	_weather_toggle.custom_minimum_size = Vector2(0.0, 26.0)
	_weather_toggle.add_theme_font_size_override(&"font_size", 10)
	_weather_toggle.toggled.connect(_on_weather_toggled)
	main_box.add_child(_weather_toggle)

	main_box.add_child(HSeparator.new())

	var reset_button := Button.new()
	reset_button.text = "Reset to defaults"
	reset_button.custom_minimum_size = Vector2(0.0, 26.0)
	reset_button.add_theme_font_size_override(&"font_size", 9)
	reset_button.tooltip_text = "Restore audio, zoom and weather defaults."
	reset_button.pressed.connect(_on_reset_pressed)
	main_box.add_child(reset_button)


func _add_slider_setting(
	parent: VBoxContainer,
	label_text: String,
	property: StringName,
	minimum: float,
	maximum: float,
	step_size: float
) -> Dictionary:
	var group := VBoxContainer.new()
	group.add_theme_constant_override(&"separation", 1)
	parent.add_child(group)

	var header := HBoxContainer.new()
	group.add_child(header)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override(&"font_size", 9)
	header.add_child(label)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(38.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override(&"font_size", 9)
	value_label.add_theme_color_override(
		&"font_color",
		Color(0.91, 0.78, 0.48)
	)
	header.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0.0, 16.0)
	slider.value_changed.connect(
		_on_slider_value_changed.bind(property, value_label)
	)
	group.add_child(slider)

	return {
		"slider": slider,
		"value": value_label,
	}


func _on_visibility_changed() -> void:
	if visible:
		_sync_controls()


func _on_slider_value_changed(
	value: float,
	property: StringName,
	value_label: Label
) -> void:
	_update_value_label(property, value_label, value)
	if _syncing:
		return
	ClientState.settings.set_value(SECTION, property, value)


func _on_weather_toggled(enabled: bool) -> void:
	if _syncing:
		return
	ClientState.settings.set_value(
		SECTION,
		&"weather_effects",
		enabled
	)


func _on_setting_changed(
	section: StringName,
	property: StringName,
	_value: Variant
) -> void:
	if section != SECTION:
		return
	if property in [
		&"music_volume",
		&"sound_volume",
		&"camera_zoom",
		&"weather_effects",
	]:
		_sync_controls()


func _sync_controls() -> void:
	if not is_instance_valid(_music_slider):
		return

	_syncing = true
	_music_slider.value = float(_setting_value(&"music_volume", 1.0))
	_sound_slider.value = float(_setting_value(&"sound_volume", 1.0))
	_zoom_slider.value = float(_setting_value(&"camera_zoom", 2.0))
	_weather_toggle.button_pressed = bool(
		_setting_value(&"weather_effects", true)
	)

	_update_value_label(
		&"music_volume",
		_music_value,
		_music_slider.value
	)
	_update_value_label(
		&"sound_volume",
		_sound_value,
		_sound_slider.value
	)
	_update_value_label(
		&"camera_zoom",
		_zoom_value,
		_zoom_slider.value
	)
	_syncing = false


func _setting_value(property: StringName, fallback: Variant) -> Variant:
	var value: Variant = ClientState.settings.get_value(SECTION, property)
	if value != null:
		return value

	value = ClientState.settings.get_default(SECTION, property)
	return fallback if value == null else value


func _update_value_label(
	property: StringName,
	label: Label,
	value: float
) -> void:
	if property == &"camera_zoom":
		label.text = "%.2fx" % value
	else:
		label.text = "%d%%" % int(round(value * 100.0))


func _on_reset_pressed() -> void:
	for property: StringName in [
		&"music_volume",
		&"sound_volume",
		&"camera_zoom",
		&"weather_effects",
	]:
		var default_value: Variant = (
			ClientState.settings.get_default(SECTION, property)
		)
		if default_value != null:
			ClientState.settings.set_value(
				SECTION,
				property,
				default_value
			)

	Toaster.toast("Settings restored to defaults.")


func _place_panel() -> void:
	var hud := get_parent() as Control
	if hud == null:
		return

	size = PANEL_SIZE
	position = Vector2(
		hud.size.x - PANEL_SIZE.x - RIGHT_MARGIN,
		hud.size.y - PANEL_SIZE.y - BOTTOM_CLEARANCE
	)
