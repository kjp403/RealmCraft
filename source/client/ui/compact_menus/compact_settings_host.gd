extends PanelContainer

const PANEL_SIZE := Vector2(180.0, 340.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 48.0
const SECTION := &"general"
## Combat feel toggles live in their own settings section, so the rows below read
## from it explicitly rather than through the [constant SECTION]-scoped helpers.
const COMBAT_SECTION := &"combat"
## Combat feel toggles, in display order. One entry per row — adding a future one
## (a stronger assist, a hitstop length) means appending here, nothing else.
const COMBAT_TOGGLES: Array[Dictionary] = [
	{
		&"property": &"commit_aim",
		&"label": "Commit aim",
		&"tooltip": "Attacks keep the direction they were aimed at instead of following your aim through the swing.",
	},
	{
		&"property": &"aim_assist",
		&"label": "Aim assist",
		&"tooltip": "Nudges attacks onto an enemy already fighting you. Never starts a fight for you.",
	},
	{
		&"property": &"hitstop",
		&"label": "Hit impact",
		&"tooltip": "Briefly freezes a struck enemy's animation on impact.",
	},
	{
		&"property": &"screen_shake",
		&"label": "Screen shake",
		&"tooltip": "Camera kick on hits and heavy attacks.",
	},
]
const LOGOUT_RED := Color(0.92, 0.28, 0.28)
const LOGOUT_RED_HOVER := Color(1.0, 0.42, 0.38)
const LOGOUT_RED_PRESSED := Color(0.72, 0.16, 0.16)

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

var _main_view: VBoxContainer
## Every on/off row lives here rather than on the main page: stacked inline they
## pushed the buttons below them off the bottom of the panel.
var _toggles_view: VBoxContainer
var _audio_view: VBoxContainer
var _music_slider: HSlider
var _sound_slider: HSlider
var _zoom_slider: HSlider
var _weather_toggle: CheckButton
var _slayer_tracker_toggle: CheckButton
var _combat_toggles: Dictionary[StringName, CheckButton] = {}
var _music_value: Label
var _sound_value: Label
var _zoom_value: Label
var _online_label: Label
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

	close_button.pressed.connect(_on_close_pressed)
	visibility_changed.connect(_on_visibility_changed)
	ClientState.settings.setting_changed.connect(_on_setting_changed)

	var hud := get_parent() as Control
	if hud != null:
		hud.resized.connect(_place_panel)

	_sync_controls()
	_show_main_view()
	call_deferred(&"_place_panel")
	hide()


func _build_layout() -> void:
	_main_view = _add_view()
	_toggles_view = _add_view()
	_audio_view = _add_view()

	_build_main_view(_main_view)
	_build_toggles_view(_toggles_view)
	_build_audio_view(_audio_view)


## One switchable page, returned as the box its rows go into. Each page gets its
## own ScrollContainer so a page taller than the panel scrolls instead of running
## off the bottom of the HUD, and [method _show_view] hides the scroller (not the
## box) so a hidden page claims no space in the shared Content margin.
func _add_view() -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 5)
	scroll.add_child(box)
	return box


func _build_main_view(main_box: VBoxContainer) -> void:
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

	main_box.add_child(HSeparator.new())

	# Server population. Polled on open (see _refresh_online_count) rather than
	# pushed — an exact live counter isn't worth a subscription, and "how busy is
	# it right now" is the question players actually open this for.
	_online_label = Label.new()
	_online_label.text = "Players online: —"
	_online_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_online_label.add_theme_font_size_override(&"font_size", 9)
	_online_label.add_theme_color_override(
		&"font_color",
		Color(0.91, 0.78, 0.48)
	)
	_online_label.tooltip_text = "Characters connected to this world right now."
	main_box.add_child(_online_label)

	main_box.add_child(HSeparator.new())

	var toggles_button := Button.new()
	toggles_button.text = "Toggles"
	toggles_button.custom_minimum_size = Vector2(0.0, 26.0)
	toggles_button.add_theme_font_size_override(&"font_size", 9)
	toggles_button.tooltip_text = "Weather, Slayer tracker and combat feel switches."
	toggles_button.pressed.connect(_show_toggles_view)
	main_box.add_child(toggles_button)

	var audio_button := Button.new()
	audio_button.text = "Audio"
	audio_button.custom_minimum_size = Vector2(0.0, 26.0)
	audio_button.add_theme_font_size_override(&"font_size", 9)
	audio_button.tooltip_text = "Music and sound effect volumes."
	audio_button.pressed.connect(_show_audio_view)
	main_box.add_child(audio_button)

	var commands_button := Button.new()
	commands_button.text = "Chat commands"
	commands_button.custom_minimum_size = Vector2(0.0, 26.0)
	commands_button.add_theme_font_size_override(&"font_size", 9)
	commands_button.tooltip_text = "Show chat commands available to your account."
	commands_button.pressed.connect(_on_commands_pressed)
	main_box.add_child(commands_button)

	var reset_button := Button.new()
	reset_button.text = "Reset to defaults"
	reset_button.custom_minimum_size = Vector2(0.0, 26.0)
	reset_button.add_theme_font_size_override(&"font_size", 9)
	reset_button.tooltip_text = "Restore audio, zoom and weather defaults."
	reset_button.pressed.connect(_on_reset_pressed)
	main_box.add_child(reset_button)

	var discord_button := Button.new()
	discord_button.text = "Join Discord"
	discord_button.custom_minimum_size = Vector2(0.0, 26.0)
	discord_button.add_theme_font_size_override(&"font_size", 9)
	discord_button.tooltip_text = "Open the Arkenelle Discord invite in your browser."
	discord_button.pressed.connect(SettingsAccountActions.open_discord)
	main_box.add_child(discord_button)

	var logout_button := Button.new()
	logout_button.text = "Log out"
	logout_button.custom_minimum_size = Vector2(0.0, 26.0)
	logout_button.add_theme_font_size_override(&"font_size", 9)
	logout_button.tooltip_text = "Disconnect and return to the login screen."
	_style_logout_button(logout_button)
	logout_button.pressed.connect(_on_logout_pressed)
	main_box.add_child(logout_button)


func _build_toggles_view(toggles_box: VBoxContainer) -> void:
	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(0.0, 26.0)
	back_button.add_theme_font_size_override(&"font_size", 9)
	back_button.pressed.connect(_show_main_view)
	toggles_box.add_child(back_button)

	toggles_box.add_child(HSeparator.new())

	_weather_toggle = CheckButton.new()
	_weather_toggle.text = "Weather effects"
	_weather_toggle.custom_minimum_size = Vector2(0.0, 26.0)
	_weather_toggle.add_theme_font_size_override(&"font_size", 10)
	_weather_toggle.toggled.connect(_on_weather_toggled)
	toggles_box.add_child(_weather_toggle)

	_slayer_tracker_toggle = CheckButton.new()
	_slayer_tracker_toggle.text = "Slayer tracker"
	_slayer_tracker_toggle.custom_minimum_size = Vector2(0.0, 26.0)
	_slayer_tracker_toggle.add_theme_font_size_override(&"font_size", 10)
	_slayer_tracker_toggle.tooltip_text = (
		"Show your current Slayer task in the top-right corner."
	)
	_slayer_tracker_toggle.toggled.connect(_on_slayer_tracker_toggled)
	toggles_box.add_child(_slayer_tracker_toggle)

	for entry: Dictionary in COMBAT_TOGGLES:
		var property: StringName = entry["property"]
		var toggle := CheckButton.new()
		toggle.text = entry["label"]
		toggle.custom_minimum_size = Vector2(0.0, 26.0)
		toggle.add_theme_font_size_override(&"font_size", 10)
		toggle.tooltip_text = entry["tooltip"]
		toggle.toggled.connect(_on_combat_toggled.bind(property))
		toggles_box.add_child(toggle)
		_combat_toggles[property] = toggle


func _build_audio_view(audio_box: VBoxContainer) -> void:
	var back_button := Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(0.0, 26.0)
	back_button.add_theme_font_size_override(&"font_size", 9)
	back_button.pressed.connect(_show_main_view)
	audio_box.add_child(back_button)

	audio_box.add_child(HSeparator.new())

	var music_controls: Dictionary = _add_slider_setting(
		audio_box,
		"Music",
		&"music_volume",
		0.0,
		1.0,
		0.05
	)
	_music_slider = music_controls["slider"]
	_music_value = music_controls["value"]

	var sound_controls: Dictionary = _add_slider_setting(
		audio_box,
		"Sound effects",
		&"sound_volume",
		0.0,
		1.0,
		0.05
	)
	_sound_slider = sound_controls["slider"]
	_sound_value = sound_controls["value"]


func _style_logout_button(button: Button) -> void:
	button.add_theme_color_override(&"font_color", Color(1.0, 0.92, 0.92))
	button.add_theme_color_override(&"font_hover_color", Color(1.0, 0.98, 0.98))
	button.add_theme_color_override(&"font_pressed_color", Color(1.0, 0.85, 0.85))
	button.add_theme_color_override(&"font_focus_color", Color(1.0, 0.92, 0.92))
	for state: StringName in [
		&"normal",
		&"hover",
		&"pressed",
		&"focus",
	]:
		var box := StyleBoxFlat.new()
		box.bg_color = (
			LOGOUT_RED_PRESSED if state == &"pressed"
			else (LOGOUT_RED_HOVER if state == &"hover" else LOGOUT_RED)
		)
		box.set_border_width_all(1)
		box.border_color = Color(1.0, 0.55, 0.5)
		box.set_corner_radius_all(2)
		box.content_margin_left = 6
		box.content_margin_right = 6
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		button.add_theme_stylebox_override(state, box)


## Show exactly one page and title it. Toggles the page's ScrollContainer, since
## that (not the inner box) is what occupies room in the Content margin.
func _show_view(view: VBoxContainer, title: String) -> void:
	for page: VBoxContainer in [_main_view, _toggles_view, _audio_view]:
		if page == null:
			continue
		var scroll := page.get_parent() as Control
		if scroll != null:
			scroll.visible = page == view
	title_label.text = title


func _show_main_view() -> void:
	_show_view(_main_view, "Settings")


func _show_toggles_view() -> void:
	_show_view(_toggles_view, "Toggles")
	_sync_controls()


func _show_audio_view() -> void:
	_show_view(_audio_view, "Audio")
	_sync_controls()


func _on_close_pressed() -> void:
	_show_main_view()
	hide()


func _on_commands_pressed() -> void:
	const ACTIONS := preload("res://source/client/ui/menus/settings/settings_commands_actions.gd")
	ACTIONS.open_commands_panel(self)


func _on_logout_pressed() -> void:
	hide()
	SettingsAccountActions.logout_to_login()


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
		_show_main_view()
		_sync_controls()
		_refresh_online_count()


func _refresh_online_count() -> void:
	if _online_label == null or InstanceClient.current == null:
		return
	Client.request_data(
		&"players.online",
		func(data: Dictionary) -> void:
			if is_instance_valid(_online_label):
				_online_label.text = "Players online: %d" % int(data.get("count", 0)),
		{},
		InstanceClient.current.name
	)


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


func _on_slayer_tracker_toggled(enabled: bool) -> void:
	if _syncing:
		return
	SlayerTracker.set_enabled(enabled)


func _on_combat_toggled(enabled: bool, property: StringName) -> void:
	if _syncing:
		return
	ClientState.settings.set_value(COMBAT_SECTION, property, enabled)


func _on_setting_changed(
	section: StringName,
	property: StringName,
	_value: Variant
) -> void:
	if section == COMBAT_SECTION:
		if _combat_toggles.has(property):
			_sync_controls()
		return
	if section != SECTION:
		return
	if property in [
		&"music_volume",
		&"sound_volume",
		&"camera_zoom",
		&"weather_effects",
		SlayerTracker.SETTING_PROPERTY,
	]:
		_sync_controls()


func _sync_controls() -> void:
	if not is_instance_valid(_music_slider) or not is_instance_valid(_zoom_slider):
		return

	_syncing = true
	_music_slider.value = float(_setting_value(&"music_volume", 1.0))
	_sound_slider.value = float(_setting_value(&"sound_volume", 1.0))
	_zoom_slider.value = float(_setting_value(&"camera_zoom", 2.0))
	_weather_toggle.button_pressed = bool(
		_setting_value(&"weather_effects", true)
	)
	_slayer_tracker_toggle.button_pressed = SlayerTracker.is_enabled()
	for property: StringName in _combat_toggles:
		_combat_toggles[property].button_pressed = bool(
			_section_value(COMBAT_SECTION, property, true)
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
	return _section_value(SECTION, property, fallback)


## Stored value, else the shipped default, else [param fallback] — for any section
## (the compact panel now shows rows from [constant COMBAT_SECTION] too).
func _section_value(
	section: StringName,
	property: StringName,
	fallback: Variant
) -> Variant:
	var value: Variant = ClientState.settings.get_value(section, property)
	if value != null:
		return value

	value = ClientState.settings.get_default(section, property)
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
		SlayerTracker.SETTING_PROPERTY,
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
	# Combat rows live in their own section, so they need their own reset pass.
	for property: StringName in _combat_toggles:
		var combat_default: Variant = (
			ClientState.settings.get_default(COMBAT_SECTION, property)
		)
		if combat_default != null:
			ClientState.settings.set_value(
				COMBAT_SECTION,
				property,
				combat_default
			)

	Toaster.toast("Settings restored to defaults.")


func _place_panel() -> void:
	var hud := get_parent() as Control
	if hud == null:
		return

	var panel_size: Vector2 = PANEL_SIZE
	var max_h: float = maxf(180.0, hud.size.y - BOTTOM_CLEARANCE)
	if panel_size.y > max_h:
		panel_size.y = max_h
	custom_minimum_size = panel_size
	size = panel_size
	position = Vector2(
		hud.size.x - panel_size.x - RIGHT_MARGIN,
		maxi(0, int(hud.size.y - panel_size.y - BOTTOM_CLEARANCE))
	)
