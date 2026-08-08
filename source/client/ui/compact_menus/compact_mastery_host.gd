extends PanelContainer

const PANEL_SIZE := Vector2(180.0, 262.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 52.0
const TAB_SIZE := Vector2(29.0, 29.0)

const CATEGORY_ORDER: Array[StringName] = [
	&"bow",
	&"sword",
	&"hammer",
	&"book",
	&"wand",
]

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

var _state: Dictionary = {}
var _wielded: Dictionary = {}
var _categories: Array[StringName] = []
var _selected_category: StringName = &""

var _category_tabs: HBoxContainer
var _tab_buttons: Dictionary[StringName, Button] = {}
var _tab_group := ButtonGroup.new()

var _level_label: Label
var _xp_bar: ProgressBar
var _status_label: Label
var _q_name: Label
var _e_name: Label
var _power_label: Label
var _manage_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

	content.add_theme_constant_override(&"margin_left", 6)
	content.add_theme_constant_override(&"margin_right", 6)

	header_spacer.hide()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "Mastery"

	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()

	_build_layout()

	close_button.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)
	# Kill rewards push mastery XP — refresh live like Skills does on gather.
	Client.subscribe(&"combat.reward", _on_combat_reward)

	var hud := get_parent() as Control
	if hud != null:
		hud.resized.connect(_place_panel)

	call_deferred(&"_place_panel")
	hide()


func _build_layout() -> void:
	var main_box := VBoxContainer.new()
	main_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_box.add_theme_constant_override(&"separation", 4)
	content.add_child(main_box)

	var tabs_center := CenterContainer.new()
	tabs_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_box.add_child(tabs_center)

	_category_tabs = HBoxContainer.new()
	_category_tabs.add_theme_constant_override(&"separation", 3)
	tabs_center.add_child(_category_tabs)

	_level_label = Label.new()
	_level_label.text = "No mastery selected"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.add_theme_font_size_override(&"font_size", 11)
	_level_label.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.9, 0.55)
	)
	main_box.add_child(_level_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = 1.0
	_xp_bar.value = 0.0
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(0.0, 10.0)
	_xp_bar.theme_type_variation = &"XPBar"
	main_box.add_child(_xp_bar)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override(&"font_size", 8)
	_status_label.add_theme_color_override(
		&"font_color",
		Color(0.72, 0.73, 0.78)
	)
	main_box.add_child(_status_label)

	var loadout_title := Label.new()
	loadout_title.text = "Equipped abilities"
	loadout_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loadout_title.add_theme_font_size_override(&"font_size", 9)
	main_box.add_child(loadout_title)

	var loadout_row := HBoxContainer.new()
	loadout_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loadout_row.add_theme_constant_override(&"separation", 4)
	main_box.add_child(loadout_row)

	var q_chip: PanelContainer = _make_loadout_chip("Q")
	q_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loadout_row.add_child(q_chip)
	_q_name = q_chip.get_node("Content/Name") as Label

	var e_chip: PanelContainer = _make_loadout_chip("E")
	e_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loadout_row.add_child(e_chip)
	_e_name = e_chip.get_node("Content/Name") as Label

	_power_label = Label.new()
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_power_label.add_theme_font_size_override(&"font_size", 8)
	_power_label.add_theme_color_override(
		&"font_color",
		Color(0.70, 0.78, 0.88)
	)
	main_box.add_child(_power_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_box.add_child(spacer)

	_manage_button = Button.new()
	_manage_button.text = "Ability Tree"
	_manage_button.custom_minimum_size = Vector2(0.0, 24.0)
	_manage_button.add_theme_font_size_override(&"font_size", 10)
	_manage_button.disabled = true
	_manage_button.pressed.connect(_open_mastery_tree)
	main_box.add_child(_manage_button)


func _make_loadout_chip(key_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 36.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.03, 0.055, 0.88)
	style.border_color = Color(0.42, 0.28, 0.18, 0.85)

	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1

	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3

	panel.add_theme_stylebox_override(&"panel", style)

	var box := VBoxContainer.new()
	box.name = "Content"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 0)
	panel.add_child(box)

	var key_label := Label.new()
	key_label.text = key_text
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override(&"font_size", 10)
	key_label.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.88, 0.55)
	)
	box.add_child(key_label)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = "Empty"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override(&"font_size", 7)
	name_label.add_theme_color_override(
		&"font_color",
		Color(0.62, 0.64, 0.70)
	)
	box.add_child(name_label)

	return panel


func _on_visibility_changed() -> void:
	if visible:
		_refresh()


func _on_combat_reward(data: Dictionary) -> void:
	if not visible:
		return
	if data.get("mastery", {}).is_empty():
		return
	_refresh()


func _refresh() -> void:
	if not visible:
		return

	if InstanceClient.current == null:
		return

	Client.request_data(
		&"mastery.get",
		_on_mastery_received,
		{},
		InstanceClient.current.name
	)


func _on_mastery_received(data: Dictionary) -> void:
	_state = data.get("masteries", {})
	_wielded = data.get("wielded", {})

	_populate_category_tabs()
	_render_selected_category()


func _populate_category_tabs() -> void:
	for child: Node in _category_tabs.get_children():
		_category_tabs.remove_child(child)
		child.queue_free()

	_categories.clear()
	_tab_buttons.clear()

	for category: StringName in CATEGORY_ORDER:
		if MasteryService.tree_for(category) != null:
			_categories.append(category)

	for category: StringName in MasteryService.trees():
		if not _categories.has(category):
			_categories.append(category)

	if _categories.is_empty():
		_selected_category = &""
		return

	if (
		_selected_category.is_empty()
		or not _categories.has(_selected_category)
	):
		_selected_category = _categories[0]

	for category: StringName in _categories:
		var tree: MasteryTreeResource = (
			MasteryService.tree_for(category)
		)
		if tree == null:
			continue

		var info: Dictionary = _state.get(
			String(category),
			{}
		)
		var level: int = int(info.get("level", 0))
		var display_name: String = (
			tree.display_name
			if not tree.display_name.is_empty()
			else String(category).capitalize()
		)

		var tab := Button.new()
		tab.custom_minimum_size = TAB_SIZE
		tab.size = TAB_SIZE
		tab.focus_mode = Control.FOCUS_NONE
		tab.toggle_mode = true
		tab.button_group = _tab_group
		tab.button_pressed = (
			category == _selected_category
		)
		tab.tooltip_text = "%s\nLevel %d" % [
			display_name,
			level,
		]
		tab.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tab.expand_icon = true
		tab.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.add_theme_constant_override(&"icon_max_width", 21)

		if tree.category_icon != null:
			tab.icon = tree.category_icon
		else:
			tab.text = display_name.left(1).to_upper()
			tab.add_theme_font_size_override(&"font_size", 10)

		_apply_tab_styles(tab)
		tab.pressed.connect(_select_category.bind(category))

		_category_tabs.add_child(tab)
		_tab_buttons[category] = tab


func _apply_tab_styles(tab: Button) -> void:
	tab.add_theme_stylebox_override(
		&"normal",
		_make_tab_style(
			Color(0.035, 0.03, 0.055, 0.88),
			Color(0.35, 0.25, 0.18, 0.75)
		)
	)
	tab.add_theme_stylebox_override(
		&"hover",
		_make_tab_style(
			Color(0.11, 0.075, 0.07, 0.96),
			Color(0.86, 0.57, 0.25, 1.0)
		)
	)
	tab.add_theme_stylebox_override(
		&"pressed",
		_make_tab_style(
			Color(0.18, 0.11, 0.055, 1.0),
			Color(1.0, 0.72, 0.30, 1.0)
		)
	)


func _make_tab_style(
	background_color: Color,
	border_color: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color

	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1

	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3

	return style


func _select_category(category: StringName) -> void:
	if not _categories.has(category):
		return

	_selected_category = category

	for category_key: StringName in _tab_buttons:
		_tab_buttons[category_key].button_pressed = (
			category_key == _selected_category
		)

	_render_selected_category()


func _render_selected_category() -> void:
	if _selected_category.is_empty():
		_level_label.text = "No mastery selected"
		_xp_bar.visible = false
		_status_label.text = ""
		_q_name.text = "Empty"
		_e_name.text = "Empty"
		_power_label.text = ""
		_manage_button.disabled = true
		return

	var tree: MasteryTreeResource = MasteryService.tree_for(
		_selected_category
	)
	if tree == null:
		_manage_button.disabled = true
		return

	var info: Dictionary = _state.get(
		String(_selected_category),
		{}
	)
	var level: int = int(info.get("level", 0))
	var points: int = int(info.get("points", 0))
	var xp: int = int(info.get("xp", 0))
	var xp_to_next: int = maxi(
		1,
		int(info.get("xp_to_next", 1))
	)
	var display_name: String = (
		tree.display_name
		if not tree.display_name.is_empty()
		else String(_selected_category).capitalize()
	)

	_level_label.text = "%s · Lv %d" % [
		display_name,
		level,
	]

	_xp_bar.visible = level > 0
	_xp_bar.max_value = xp_to_next
	_xp_bar.value = xp

	if level <= 0:
		_status_label.text = "Unpracticed · 0 points"
	elif level >= int(PlayerResource.MASTERY_LEVEL_CAP):
		_status_label.text = "Maximum level · %d points" % points
	else:
		_status_label.text = "%d/%d XP · %d point%s" % [
			xp,
			xp_to_next,
			points,
			"" if points == 1 else "s",
		]

	_status_label.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.86, 0.48)
		if points > 0
		else Color(0.72, 0.73, 0.78)
	)

	var loadout: Array = info.get("loadout", [])

	_q_name.text = _loadout_name(loadout, 0, tree)
	_e_name.text = _loadout_name(loadout, 1, tree)

	var capacity: int = _wielded_capacity()
	if capacity < 0:
		_power_label.text = "Equip this weapon type to use its abilities."
	else:
		_power_label.text = "Abilities channel while this weapon is held."

	_manage_button.disabled = false


func _loadout_name(
	loadout: Array,
	index: int,
	tree: MasteryTreeResource
) -> String:
	if index < 0 or index >= loadout.size():
		return "Empty"

	var node_id: String = str(loadout[index])
	if node_id.is_empty():
		return "Empty"

	var mastery_node: MasteryNode = tree.get_node_by_id(
		StringName(node_id)
	)
	if mastery_node == null:
		return node_id

	return mastery_node.display_name()


func _wielded_capacity() -> int:
	if str(_wielded.get("category", "")) == String(
		_selected_category
	):
		return int(_wielded.get("capacity", 0))

	return -1


func _loadout_power_used(
	loadout: Array,
	tree: MasteryTreeResource
) -> int:
	var total: int = 0

	for selection: Variant in loadout:
		var node_id: String = str(selection)
		if node_id.is_empty():
			continue

		var mastery_node: MasteryNode = tree.get_node_by_id(
			StringName(node_id)
		)
		if mastery_node != null:
			total += mastery_node.tier

	return total


func _open_mastery_tree() -> void:
	if _selected_category.is_empty():
		return

	hide()
	ClientState.open_menu_requested.emit(
		&"mastery_tree",
		String(_selected_category)
	)


func _place_panel() -> void:
	var hud := get_parent() as Control
	if hud == null:
		return

	size = PANEL_SIZE
	position = Vector2(
		hud.size.x - PANEL_SIZE.x - RIGHT_MARGIN,
		hud.size.y - PANEL_SIZE.y - BOTTOM_CLEARANCE
	)
