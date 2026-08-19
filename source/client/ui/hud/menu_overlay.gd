extends Control
## Compact bottom-right navigation menu.

const MENU_ENTRIES: Array = [
	{"label": "Profile", "menu": ""},
	{"label": "Character", "menu": "character"},
	# Explicit icon: the default path is ICON_DIR + label, and the Prayer art
	# lives in the realmcraft_menu_icons subfolder with the other skill icons.
	{
		"label": "Prayers", "menu": "prayer",
		"icon": "res://assets/sprites/ui/menu_icons_shadow/32px/realmcraft_menu_icons/Prayer.png",
	},
	{"label": "Quests", "menu": "quests"},
	{"label": "Inventory", "menu": "inventory"},
	{"label": "Friends", "menu": "friends"},
	{"label": "Mail", "menu": "mail"},
	{"label": "Guild", "menu": "guild"},
	{"label": "Leaderboard", "menu": "leaderboard"},
	{"label": "Map", "menu": "world_map"},
	{"label": "Achievements"},
	{"label": "Bestiary"},
	{"label": "House"},
	{"label": "Shop"},
	{"label": "Help", "menu": "help"},
	{"label": "Redeem", "menu": "redeem"},
	{"label": "Settings", "menu": "settings"}
]

const ICON_DIR := \
	"res://assets/sprites/ui/menu_icons_shadow/32px/"

# Bottom-right panel placement.
const PANEL_LEFT := -252.0
const PANEL_RIGHT := -12.0
const PANEL_TOP := -524.0
const PANEL_BOTTOM := -12.0

# Positive value makes it slide in from the right edge.
const PANEL_SLIDE := 260.0

var _panel: PanelContainer
var _tween: Tween
var _mail_button: Button

var _button_normal: StyleBoxFlat
var _button_hover: StyleBoxFlat
var _button_pressed: StyleBoxFlat


func _ready() -> void:
	_build_styles()
	_build_menu()
	hide()


func _build_menu() -> void:
	# Light dimming keeps the game visible.
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	dim.color = Color(0.02, 0.025, 0.04, 0.20)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(_on_dim_input)
	add_child(dim)

	# Fixed panel anchored to the bottom-right.
	_panel = PanelContainer.new()
	_panel.anchor_left = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = PANEL_LEFT
	_panel.offset_top = PANEL_TOP
	_panel.offset_right = PANEL_RIGHT
	_panel.offset_bottom = PANEL_BOTTOM
	_panel.add_theme_stylebox_override(
		&"panel",
		_make_panel_style()
	)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(
		&"margin_left",
		10
	)
	margin.add_theme_constant_override(
		&"margin_top",
		10
	)
	margin.add_theme_constant_override(
		&"margin_right",
		10
	)
	margin.add_theme_constant_override(
		&"margin_bottom",
		10
	)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(
		&"separation",
		7
	)
	margin.add_child(column)

	var header := Label.new()
	header.text = "Menu"
	header.horizontal_alignment = \
		HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override(
		&"font_size",
		17
	)
	header.add_theme_color_override(
		&"font_color",
		Color(0.96, 0.82, 0.55)
	)
	column.add_child(header)

	column.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = \
		Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = \
		Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = \
		ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var button_column := VBoxContainer.new()
	button_column.size_flags_horizontal = \
		Control.SIZE_EXPAND_FILL
	button_column.add_theme_constant_override(
		&"separation",
		5
	)
	scroll.add_child(button_column)

	for entry: Dictionary in MENU_ENTRIES:
		button_column.add_child(
			_make_menu_button(entry)
		)

	DragScroll.enable(scroll)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = \
		Vector2(0, 38)
	close_button.add_theme_stylebox_override(
		&"normal",
		_button_pressed
	)
	close_button.add_theme_stylebox_override(
		&"hover",
		_button_hover
	)
	close_button.pressed.connect(close)
	column.add_child(close_button)


func _make_menu_button(entry: Dictionary) -> Button:
	var button := Button.new()
	var label := String(entry.get("label", "Menu"))

	button.text = label
	button.tooltip_text = label
	button.custom_minimum_size = Vector2(210, 48)
	button.size_flags_horizontal = \
		Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.expand_icon = false

	button.add_theme_font_size_override(
		&"font_size",
		15
	)
	button.add_theme_constant_override(
		&"icon_separation",
		12
	)
	button.add_theme_stylebox_override(
		&"normal",
		_button_normal
	)
	button.add_theme_stylebox_override(
		&"hover",
		_button_hover
	)
	button.add_theme_stylebox_override(
		&"pressed",
		_button_pressed
	)
	button.add_theme_stylebox_override(
		&"focus",
		_button_hover
	)

	var icon_path := String(entry.get("icon", ""))

	if icon_path.is_empty():
		icon_path = ICON_DIR + label.to_lower() + ".png"

	if ResourceLoader.exists(icon_path):
		button.icon = load(icon_path)

	if label == "Mail":
		_mail_button = button

	if entry.has("menu"):
		button.pressed.connect(
			_on_entry_pressed.bind(
				String(entry["menu"])
			)
		)
	else:
		button.pressed.connect(
			_show_coming_soon.bind(label)
		)

	return button


func _build_styles() -> void:
	_button_normal = _make_button_style(
		Color(0.065, 0.07, 0.10, 0.96),
		Color(0.25, 0.24, 0.28, 1.0)
	)

	_button_hover = _make_button_style(
		Color(0.14, 0.15, 0.20, 1.0),
		Color(0.77, 0.52, 0.28, 1.0)
	)

	_button_pressed = _make_button_style(
		Color(0.035, 0.04, 0.06, 1.0),
		Color(0.55, 0.36, 0.20, 1.0)
	)


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.06, 0.97)
	style.border_color = Color(0.53, 0.37, 0.22)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 7
	return style


func _make_button_style(
	background: Color,
	border: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)

	style.content_margin_left = 12
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7

	return style


func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			close()


func _on_entry_pressed(menu_name: String) -> void:
	close()

	if menu_name.is_empty():
		ClientState.player_profile_requested.emit(0)
	else:
		ClientState.open_menu_requested.emit(
			StringName(menu_name),
			null
		)


func _show_coming_soon(label: String) -> void:
	Toaster.toast(
		"%s coming soon" % label,
		1.5
	)


func open() -> void:
	_refresh_mail_badge()

	if _tween != null and _tween.is_valid():
		_tween.kill()

	show()
	modulate.a = 0.0

	_panel.offset_left = PANEL_LEFT + PANEL_SLIDE
	_panel.offset_right = PANEL_RIGHT + PANEL_SLIDE

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_QUAD)

	_tween.tween_property(
		self,
		^"modulate:a",
		1.0,
		0.18
	)

	_tween.tween_property(
		_panel,
		^"offset_left",
		PANEL_LEFT,
		0.18
	)

	_tween.tween_property(
		_panel,
		^"offset_right",
		PANEL_RIGHT,
		0.18
	)


func close() -> void:
	if not visible:
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_QUAD)

	_tween.tween_property(
		self,
		^"modulate:a",
		0.0,
		0.16
	)

	_tween.tween_property(
		_panel,
		^"offset_left",
		PANEL_LEFT + PANEL_SLIDE,
		0.16
	)

	_tween.tween_property(
		_panel,
		^"offset_right",
		PANEL_RIGHT + PANEL_SLIDE,
		0.16
	)

	_tween.chain().tween_callback(hide)


func _refresh_mail_badge() -> void:
	if _mail_button == null:
		return

	if InstanceClient.current == null:
		return

	var result: Array = await Client.request_data_await(
		&"mail.unread_count",
		{},
		String(InstanceClient.current.name)
	)

	if not is_instance_valid(_mail_button):
		return

	var count := 0

	if result[1] == OK:
		var response: Dictionary = result[0]
		count = int(response.get("count", 0))

	_mail_button.text = (
		"Mail (%d)" % count
		if count > 0
		else "Mail"
	)
