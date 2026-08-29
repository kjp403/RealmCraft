extends PanelContainer
## Compact Mastery dock — Weapons (ability loadouts) + Perks (skilling perk points).

const PANEL_SIZE_WEAPONS := Vector2(180.0, 278.0)
## Match Skills dock height so the Perks tab stays on-screen; list/detail scroll.
const PANEL_SIZE_PERKS := Vector2(248.0, 320.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 48.0
const TAB_SIZE := Vector2(29.0, 29.0)
## Ability-loadout input labels, in slot order. Mirrors MasteryTreeMenu.SLOT_KEYS
## and mastery.loadout's MAX_PICKS.
const SLOT_KEYS: Array[String] = ["Q", "E", "R", "C"]

const CATEGORY_ORDER: Array[StringName] = [
	&"bow",
	&"sword",
	&"hammer",
	&"book",
	&"wand",
]

## Skill list order for the Perks tab (matches Skills dock).
const SKILL_ORDER: Array[String] = [
	"mining",
	"smithing",
	"fishing",
	"cooking",
	"outfitting",
	"woodcutting",
	"harvesting",
	"fletching",
	"herblore",
	"slayer",
]

enum Mode { WEAPONS, PERKS }

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

var _mode: Mode = Mode.WEAPONS
var _mode_tabs: HBoxContainer
var _weapons_tab: Button
var _perks_tab: Button
var _mode_group := ButtonGroup.new()

var _weapons_root: VBoxContainer
var _perks_root: VBoxContainer

# --- Weapons state ---
var _state: Dictionary = {}
var _wielded: Dictionary = {}
var _categories: Array[StringName] = []
var _selected_category: StringName = &""
var _category_tabs: HBoxContainer
var _tab_buttons: Dictionary[StringName, Button] = {}
var _category_group := ButtonGroup.new()
var _level_label: Label
var _xp_bar: ProgressBar
var _status_label: Label
## One Label per loadout position, in SLOT_KEYS order (Q / E / R / C). An array
## rather than named fields so a further input slot is one entry in SLOT_KEYS.
var _slot_names: Array[Label] = []
var _power_label: Label
var _manage_button: Button

# --- Perks state ---
var _skills: Dictionary = {}
var _selected_skill: String = ""
var _perks_list_root: VBoxContainer
var _perks_detail_root: VBoxContainer
var _perks_scroll: ScrollContainer
## slug -> { "button": Button, "name": Label, "pts": Label } — updated in place
## so gather refreshes don't wipe/recreate every skill row.
var _perk_skill_rows: Dictionary = {}
## Coalesce gather-driven skills.get while the dock is open (avoids hitching
## on every swing / chop while Perks is visible).
var _perks_refresh_queued: bool = false
## Coalesce combat.reward mastery.get while Weapons tab is open.
var _weapons_refresh_queued: bool = false
## Shared StyleBoxFlat instances — recreating these per row was a major cost
## when navigating Perks or refreshing while open.
var _style_tab_normal: StyleBoxFlat
var _style_tab_hover: StyleBoxFlat
var _style_tab_pressed: StyleBoxFlat
var _style_chip: StyleBoxFlat
var _style_perk_choice: StyleBoxFlat


func _ready() -> void:
	_ensure_shared_styles()
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = PANEL_SIZE_WEAPONS
	size = PANEL_SIZE_WEAPONS
	clip_contents = true

	content.add_theme_constant_override(&"margin_left", 4)
	content.add_theme_constant_override(&"margin_right", 4)
	content.add_theme_constant_override(&"margin_top", 2)
	content.add_theme_constant_override(&"margin_bottom", 2)

	header_spacer.hide()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "Mastery"
	title_label.add_theme_font_size_override(&"font_size", 13)
	var header_row: Control = title_label.get_parent() as Control
	if header_row != null:
		header_row.custom_minimum_size = Vector2(0, 22)
	close_button.custom_minimum_size = Vector2(22, 22)

	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()

	_build_layout()

	close_button.pressed.connect(_on_close_pressed)
	visibility_changed.connect(_on_visibility_changed)
	Client.subscribe(&"combat.reward", _on_combat_reward)
	ClientState.gather_succeeded.connect(_on_gather_succeeded)
	Client.subscribe(&"skills.get", _on_skills_received)

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

	_mode_tabs = HBoxContainer.new()
	_mode_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_tabs.add_theme_constant_override(&"separation", 4)
	main_box.add_child(_mode_tabs)

	_weapons_tab = _make_mode_tab("Weapons", true)
	_perks_tab = _make_mode_tab("Perks", false)
	_weapons_tab.pressed.connect(_set_mode.bind(Mode.WEAPONS))
	_perks_tab.pressed.connect(_set_mode.bind(Mode.PERKS))
	_mode_tabs.add_child(_weapons_tab)
	_mode_tabs.add_child(_perks_tab)

	_weapons_root = VBoxContainer.new()
	_weapons_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapons_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_weapons_root.add_theme_constant_override(&"separation", 4)
	main_box.add_child(_weapons_root)
	_build_weapons_layout(_weapons_root)

	_perks_root = VBoxContainer.new()
	_perks_root.visible = false
	_perks_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_perks_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_perks_root.add_theme_constant_override(&"separation", 4)
	main_box.add_child(_perks_root)
	_build_perks_layout(_perks_root)


func _make_mode_tab(label: String, pressed: bool) -> Button:
	var tab := Button.new()
	tab.text = label
	tab.toggle_mode = true
	tab.button_group = _mode_group
	tab.button_pressed = pressed
	tab.focus_mode = Control.FOCUS_NONE
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.custom_minimum_size = Vector2(0.0, 18.0)
	tab.add_theme_font_size_override(&"font_size", 9)
	_apply_mode_tab_styles(tab)
	return tab


func _ensure_shared_styles() -> void:
	if _style_tab_normal != null:
		return
	_style_tab_normal = _make_tab_style(
		Color(0.035, 0.03, 0.055, 0.88), Color(0.35, 0.25, 0.18, 0.75)
	)
	_style_tab_hover = _make_tab_style(
		Color(0.11, 0.075, 0.07, 0.96), Color(0.86, 0.57, 0.25, 1.0)
	)
	_style_tab_pressed = _make_tab_style(
		Color(0.18, 0.11, 0.055, 1.0), Color(1.0, 0.72, 0.30, 1.0)
	)
	for style: StyleBoxFlat in [
		_style_tab_normal, _style_tab_hover, _style_tab_pressed
	]:
		style.content_margin_top = 1
		style.content_margin_bottom = 1
		style.content_margin_left = 4
		style.content_margin_right = 4
	_style_chip = _make_tab_style(
		Color(0.035, 0.03, 0.055, 0.88), Color(0.42, 0.28, 0.18, 0.85)
	)
	_style_perk_choice = _make_tab_style(
		Color(0.04, 0.035, 0.06, 0.92), Color(0.40, 0.28, 0.18, 0.80)
	)


func _apply_mode_tab_styles(tab: Button) -> void:
	_ensure_shared_styles()
	tab.add_theme_stylebox_override(&"normal", _style_tab_normal)
	tab.add_theme_stylebox_override(&"hover", _style_tab_hover)
	tab.add_theme_stylebox_override(&"pressed", _style_tab_pressed)
	tab.add_theme_stylebox_override(&"disabled", _style_tab_normal)
	tab.add_theme_stylebox_override(&"focus", _style_tab_normal)


func _build_weapons_layout(main_box: VBoxContainer) -> void:
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
	_level_label.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.55))
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
	_status_label.add_theme_color_override(&"font_color", Color(0.72, 0.73, 0.78))
	main_box.add_child(_status_label)

	var loadout_title := Label.new()
	loadout_title.text = "Equipped abilities"
	loadout_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loadout_title.add_theme_font_size_override(&"font_size", 9)
	main_box.add_child(loadout_title)

	var loadout_row := HBoxContainer.new()
	loadout_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loadout_row.add_theme_constant_override(&"separation", 3)
	main_box.add_child(loadout_row)

	_slot_names.clear()
	for key: String in SLOT_KEYS:
		var chip: PanelContainer = _make_loadout_chip(key)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		loadout_row.add_child(chip)
		_slot_names.append(chip.get_node("Content/Name") as Label)

	_power_label = Label.new()
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_power_label.add_theme_font_size_override(&"font_size", 8)
	_power_label.add_theme_color_override(&"font_color", Color(0.70, 0.78, 0.88))
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


func _build_perks_layout(main_box: VBoxContainer) -> void:
	_perks_list_root = VBoxContainer.new()
	_perks_list_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_perks_list_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_perks_list_root.add_theme_constant_override(&"separation", 4)
	main_box.add_child(_perks_list_root)

	var intro := Label.new()
	intro.name = "Intro"
	intro.text = "Skill perk points — specialize gathering & crafting."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override(&"font_size", 9)
	intro.add_theme_color_override(&"font_color", Color(0.72, 0.74, 0.80))
	_perks_list_root.add_child(intro)

	_perks_scroll = ScrollContainer.new()
	_perks_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_perks_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_perks_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_perks_list_root.add_child(_perks_scroll)
	DragScroll.enable(_perks_scroll)

	var list := VBoxContainer.new()
	list.name = "SkillList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 3)
	_perks_scroll.add_child(list)

	_perks_detail_root = VBoxContainer.new()
	_perks_detail_root.visible = false
	_perks_detail_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_perks_detail_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_perks_detail_root.add_theme_constant_override(&"separation", 4)
	main_box.add_child(_perks_detail_root)


func _make_loadout_chip(key_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 36.0)
	_ensure_shared_styles()
	panel.add_theme_stylebox_override(&"panel", _style_chip)

	var box := VBoxContainer.new()
	box.name = "Content"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 0)
	panel.add_child(box)

	var key_label := Label.new()
	key_label.text = key_text
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.add_theme_font_size_override(&"font_size", 10)
	key_label.add_theme_color_override(&"font_color", Color(1.0, 0.88, 0.55))
	box.add_child(key_label)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = "Empty"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override(&"font_size", 7)
	name_label.add_theme_color_override(&"font_color", Color(0.62, 0.64, 0.70))
	# Clip rather than let the ability name set the chip's minimum width: four
	# chips share a 180px dock, so an un-clipped "Paladin's Might III" would push
	# the row wider than the panel it lives in.
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(name_label)

	return panel


func _on_close_pressed() -> void:
	if _mode == Mode.PERKS and _perks_detail_root.visible:
		_show_perks_list()
		return
	hide()


func _on_visibility_changed() -> void:
	if visible:
		# Re-fit every open — first show can land before the HUD has a real size,
		# which used to crop the Perks detail until a later reopen.
		call_deferred(&"_place_panel")
		_refresh()


func _on_combat_reward(data: Dictionary) -> void:
	if not visible:
		return
	if _mode == Mode.WEAPONS and data.get("mastery", {}).is_empty():
		return
	if _mode == Mode.WEAPONS:
		_queue_weapons_refresh()


func _queue_weapons_refresh() -> void:
	if _weapons_refresh_queued:
		return
	_weapons_refresh_queued = true
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		_weapons_refresh_queued = false
		if visible and _mode == Mode.WEAPONS:
			_refresh_weapons()
	, CONNECT_ONE_SHOT)


func _on_gather_succeeded(_result: Dictionary) -> void:
	if not visible or _mode != Mode.PERKS:
		return
	# Debounce: gathering while Perks is open used to fire skills.get + full
	# list rebuild on every extract, which hitch the client.
	_queue_perks_refresh()


func _queue_perks_refresh() -> void:
	if _perks_refresh_queued:
		return
	_perks_refresh_queued = true
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		_perks_refresh_queued = false
		if visible:
			_refresh_perks()
	, CONNECT_ONE_SHOT)


func _set_mode(mode: Mode) -> void:
	_mode = mode
	_weapons_tab.button_pressed = mode == Mode.WEAPONS
	_perks_tab.button_pressed = mode == Mode.PERKS
	_weapons_root.visible = mode == Mode.WEAPONS
	_perks_root.visible = mode == Mode.PERKS
	title_label.text = "Mastery" if mode == Mode.WEAPONS else "Skill Perks"
	_place_panel()
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	# Perks list/badge needs skills.get; Weapons only needs mastery.get.
	# Still refresh skills when the Perks tab is selected, or once so the
	# badge is populated if we have never fetched.
	if _mode == Mode.PERKS or _skills.is_empty():
		_refresh_perks()
	if _mode == Mode.WEAPONS:
		_refresh_weapons()


func _refresh_weapons() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(
		&"mastery.get",
		_on_mastery_received,
		{},
		InstanceClient.current.name
	)


func _refresh_perks() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(
		&"skills.get",
		_on_skills_received,
		{},
		InstanceClient.current.name
	)


func _on_mastery_received(data: Dictionary) -> void:
	_state = data.get("masteries", {})
	_wielded = data.get("wielded", {})
	# Freshest mastery levels in the session — keep the shared mirror in step so
	# gear tooltips elsewhere colour their wear-gates correctly.
	ClientState.apply_mastery_payload(_state)
	_populate_category_tabs()
	_render_selected_category()


func _on_skills_received(data: Dictionary) -> void:
	_skills = data.get("skills", {})
	_update_perks_tab_badge()
	if _mode != Mode.PERKS:
		return
	if _perks_detail_root.visible and not _selected_skill.is_empty():
		_rebuild_perk_detail()
	else:
		_rebuild_perks_list(false)


func _update_perks_tab_badge() -> void:
	var total_points: int = 0
	for skill_name: Variant in _skills:
		total_points += int((_skills[skill_name] as Dictionary).get("points", 0))
	if total_points > 0:
		_perks_tab.text = "Perks (%d)" % total_points
	else:
		_perks_tab.text = "Perks"


# ---------------------------------------------------------------------------
# Weapons — category tabs + summary
# ---------------------------------------------------------------------------

func _populate_category_tabs() -> void:
	var next_categories: Array[StringName] = []
	for category: StringName in CATEGORY_ORDER:
		if MasteryService.tree_for(category) != null:
			next_categories.append(category)
	for category: StringName in MasteryService.trees():
		if not next_categories.has(category):
			next_categories.append(category)

	# Reuse existing tab buttons when the category set is unchanged — wiping
	# and recreating them on every mastery.get was hitching the Weapons tab.
	var same_set: bool = (
		next_categories.size() == _categories.size()
		and _tab_buttons.size() == next_categories.size()
	)
	if same_set:
		for i: int in next_categories.size():
			if next_categories[i] != _categories[i]:
				same_set = false
				break

	_categories = next_categories
	if _categories.is_empty():
		_selected_category = &""
		for child: Node in _category_tabs.get_children():
			_category_tabs.remove_child(child)
			child.queue_free()
		_tab_buttons.clear()
		return

	if _selected_category.is_empty() or not _categories.has(_selected_category):
		_selected_category = _categories[0]

	if same_set:
		for category: StringName in _categories:
			var tree: MasteryTreeResource = MasteryService.tree_for(category)
			var tab: Button = _tab_buttons.get(category) as Button
			if tree == null or tab == null:
				continue
			var info: Dictionary = _state.get(String(category), {})
			var level: int = int(info.get("level", 1))
			var display_name: String = (
				tree.display_name
				if not tree.display_name.is_empty()
				else String(category).capitalize()
			)
			tab.tooltip_text = "%s\nLevel %d" % [display_name, level]
			tab.button_pressed = category == _selected_category
		return

	for child: Node in _category_tabs.get_children():
		_category_tabs.remove_child(child)
		child.queue_free()
	_tab_buttons.clear()

	for category: StringName in _categories:
		var tree: MasteryTreeResource = MasteryService.tree_for(category)
		if tree == null:
			continue

		var info: Dictionary = _state.get(String(category), {})
		var level: int = int(info.get("level", 1))
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
		tab.button_group = _category_group
		tab.button_pressed = category == _selected_category
		tab.tooltip_text = "%s\nLevel %d" % [display_name, level]
		tab.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tab.expand_icon = true
		tab.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab.add_theme_constant_override(&"icon_max_width", 21)

		if tree.category_icon != null:
			tab.icon = tree.category_icon
		else:
			tab.text = display_name.left(1).to_upper()
			tab.add_theme_font_size_override(&"font_size", 10)

		_apply_mode_tab_styles(tab)
		tab.pressed.connect(_select_category.bind(category))

		_category_tabs.add_child(tab)
		_tab_buttons[category] = tab


func _make_tab_style(background_color: Color, border_color: Color) -> StyleBoxFlat:
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
		_tab_buttons[category_key].button_pressed = category_key == _selected_category
	_render_selected_category()


func _render_selected_category() -> void:
	if _selected_category.is_empty():
		_level_label.text = "No mastery selected"
		_xp_bar.visible = false
		_status_label.text = ""
		for name_label: Label in _slot_names:
			name_label.text = "Empty"
		_power_label.text = ""
		_manage_button.disabled = true
		return

	var tree: MasteryTreeResource = MasteryService.tree_for(_selected_category)
	if tree == null:
		_manage_button.disabled = true
		return

	var info: Dictionary = _state.get(String(_selected_category), {})
	var level: int = int(info.get("level", 1))
	var points: int = int(info.get("points", 0))
	var xp: int = int(info.get("xp", 0))
	var xp_to_next: int = maxi(1, int(info.get("xp_to_next", 1)))
	var display_name: String = (
		tree.display_name
		if not tree.display_name.is_empty()
		else String(_selected_category).capitalize()
	)

	_level_label.text = "%s · Lv %d" % [display_name, level]
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
		Color(1.0, 0.86, 0.48) if points > 0 else Color(0.72, 0.73, 0.78)
	)

	var loadout: Array = info.get("loadout", [])
	for i: int in _slot_names.size():
		_slot_names[i].text = _loadout_name(loadout, i, tree)

	if _wielded_capacity() < 0:
		_power_label.text = "Equip this weapon type to use its abilities."
	else:
		_power_label.text = "Abilities channel while this weapon is held."

	_manage_button.disabled = false


func _loadout_name(loadout: Array, index: int, tree: MasteryTreeResource) -> String:
	if index < 0 or index >= loadout.size():
		return "Empty"
	var node_id: String = str(loadout[index])
	if node_id.is_empty():
		return "Empty"
	var mastery_node: MasteryNode = tree.get_node_by_id(StringName(node_id))
	if mastery_node == null:
		return node_id
	return mastery_node.display_name()


func _wielded_capacity() -> int:
	if str(_wielded.get("category", "")) == String(_selected_category):
		return int(_wielded.get("capacity", 0))
	return -1


func _open_mastery_tree() -> void:
	if _selected_category.is_empty():
		return
	hide()
	ClientState.open_menu_requested.emit(&"mastery_tree", String(_selected_category))


# ---------------------------------------------------------------------------
# Perks — skill list + spend detail
# ---------------------------------------------------------------------------

func _show_perks_list() -> void:
	_selected_skill = ""
	_perks_detail_root.visible = false
	_perks_list_root.visible = true
	title_label.text = "Skill Perks"
	_rebuild_perks_list(false)


func _show_perk_detail(slug: String) -> void:
	_selected_skill = slug
	_perks_list_root.visible = false
	_perks_detail_root.visible = true
	_rebuild_perk_detail()
	call_deferred(&"_place_panel")


func _rebuild_perks_list(force_rebuild: bool = true) -> void:
	var list: VBoxContainer = _perks_scroll.get_node("SkillList") as VBoxContainer
	var ordered: Array[String] = []
	for slug: String in SKILL_ORDER:
		var info: Dictionary = _perk_skill_info(slug)
		if info.is_empty():
			continue
		ordered.append(slug)
	for job_slug: StringName in JobRegistry.JOBS:
		var slug: String = String(job_slug)
		if ordered.has(slug):
			continue
		var info: Dictionary = _perk_skill_info(slug)
		if info.is_empty():
			continue
		ordered.append(slug)

	var can_inplace: bool = (
		not force_rebuild
		and _perk_skill_rows.size() == ordered.size()
		and list.get_child_count() == ordered.size()
	)
	if can_inplace:
		for slug: String in ordered:
			if not _perk_skill_rows.has(slug):
				can_inplace = false
				break
	if can_inplace:
		for slug: String in ordered:
			_update_skill_row(slug, _perk_skill_info(slug))
		_update_perks_intro()
		return

	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()
	_perk_skill_rows.clear()

	for slug: String in ordered:
		list.add_child(_make_skill_row(slug, _perk_skill_info(slug)))

	_update_perks_intro()


func _perk_skill_info(slug: String) -> Dictionary:
	var info: Dictionary = _skills.get(slug, {}) as Dictionary
	if info.is_empty() and JobRegistry.has_job(StringName(slug)):
		return {
			"display_name": JobRegistry.display_name(StringName(slug)),
			"level": 1,
			"points": 0,
			"choices": [],
			"perks": [],
		}
	return info


func _update_perks_intro() -> void:
	var total_points: int = 0
	for skill_name: Variant in _skills:
		total_points += int((_skills[skill_name] as Dictionary).get("points", 0))
	var intro: Label = _perks_list_root.get_node_or_null("Intro") as Label
	if intro == null:
		return
	if total_points > 0:
		intro.text = "%d perk point%s ready to spend. Tap a skill." % [
			total_points,
			"" if total_points == 1 else "s",
		]
		intro.add_theme_color_override(&"font_color", Color(1.0, 0.86, 0.48))
	else:
		# Matches JobPerks.perk_every_levels default (10) / Slayer (15).
		# Weapon mastery is every 3 levels — that is a different system.
		intro.text = (
			"Earn 1 perk point every 10 skill levels (15 for Slayer). "
			+ "Tap a skill for the full breakdown."
		)
		intro.add_theme_color_override(&"font_color", Color(0.72, 0.74, 0.80))


func _update_skill_row(slug: String, info: Dictionary) -> void:
	if info.is_empty():
		return
	var entry: Variant = _perk_skill_rows.get(slug, null)
	if entry == null or not (entry is Dictionary):
		return
	var row_data: Dictionary = entry
	var name_label: Label = row_data.get("name") as Label
	var pts: Label = row_data.get("pts") as Label
	if name_label == null or pts == null:
		return
	var display: String = str(info.get("display_name", slug.capitalize()))
	var level: int = int(info.get("level", 1))
	var points: int = int(info.get("points", 0))
	name_label.text = "%s  Lv %d" % [display, level]
	if points > 0:
		pts.text = "%d pt%s" % [points, "" if points == 1 else "s"]
		pts.add_theme_color_override(&"font_color", Color(1.0, 0.86, 0.48))
	else:
		pts.text = "—"
		pts.add_theme_color_override(&"font_color", Color(0.55, 0.56, 0.60))


func _make_skill_row(slug: String, info: Dictionary) -> Button:
	var display: String = str(info.get("display_name", slug.capitalize()))
	var level: int = int(info.get("level", 1))
	var points: int = int(info.get("points", 0))

	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size = Vector2(0.0, 28.0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.pressed.connect(_show_perk_detail.bind(slug))
	_apply_mode_tab_styles(row)

	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 6)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 6
	box.offset_right = -6
	row.add_child(box)

	var name_label := Label.new()
	name_label.text = "%s  Lv %d" % [display, level]
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override(&"font_size", 10)
	name_label.add_theme_color_override(&"font_color", Color(0.92, 0.90, 0.86))
	box.add_child(name_label)

	var pts := Label.new()
	if points > 0:
		pts.text = "%d pt%s" % [points, "" if points == 1 else "s"]
		pts.add_theme_color_override(&"font_color", Color(1.0, 0.86, 0.48))
	else:
		pts.text = "—"
		pts.add_theme_color_override(&"font_color", Color(0.55, 0.56, 0.60))
	pts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pts.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pts.add_theme_font_size_override(&"font_size", 10)
	box.add_child(pts)

	_perk_skill_rows[slug] = {
		"button": row,
		"name": name_label,
		"pts": pts,
	}
	return row


func _rebuild_perk_detail() -> void:
	# Preserve scroll so spending a point (especially the 3rd bonus) doesn't
	# yank the player back to the top of the Spend list.
	var saved_scroll: int = 0
	for child: Node in _perks_detail_root.get_children():
		if child is ScrollContainer:
			saved_scroll = (child as ScrollContainer).scroll_vertical
		_perks_detail_root.remove_child(child)
		child.queue_free()

	if _selected_skill.is_empty():
		_show_perks_list()
		return

	var info: Dictionary = _skills.get(_selected_skill, {}) as Dictionary
	if info.is_empty():
		_show_perks_list()
		return

	var jp: JobPerks = JobRegistry.perks_for(StringName(_selected_skill))
	var display: String = str(info.get("display_name", _selected_skill.capitalize()))
	var level: int = int(info.get("level", 1))
	var points: int = int(info.get("points", 0))
	title_label.text = display

	var back := Button.new()
	back.text = UiGlyphs.back() + "All skills"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(0, 18)
	back.add_theme_font_size_override(&"font_size", 9)
	_apply_mode_tab_styles(back)
	back.pressed.connect(_show_perks_list)
	_perks_detail_root.add_child(back)

	var header := Label.new()
	header.text = "Lv %d · %d point%s available" % [
		level,
		points,
		"" if points == 1 else "s",
	]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override(&"font_size", 10)
	header.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.86, 0.48) if points > 0 else Color(0.85, 0.82, 0.70)
	)
	_perks_detail_root.add_child(header)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = true
	_perks_detail_root.add_child(scroll)
	DragScroll.enable(scroll)
	if saved_scroll > 0:
		scroll.set_deferred(&"scroll_vertical", saved_scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 4)
	scroll.add_child(body)

	# How points work
	var rules_title := Label.new()
	rules_title.text = "How perk points work"
	rules_title.add_theme_font_size_override(&"font_size", 10)
	rules_title.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.55))
	body.add_child(rules_title)

	var rules := Label.new()
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_font_size_override(&"font_size", 9)
	rules.add_theme_color_override(&"font_color", Color(0.72, 0.74, 0.80))
	if jp != null:
		rules.text = jp.points_rules_text()
	else:
		rules.text = "Train this skill to unlock perk choices."
	body.add_child(rules)

	# Current effective bonuses
	var bonus_lines: Array = info.get("perks", [])
	if not bonus_lines.is_empty():
		var bonus_title := Label.new()
		bonus_title.text = "Current bonuses"
		bonus_title.add_theme_font_size_override(&"font_size", 10)
		bonus_title.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.55))
		body.add_child(bonus_title)
		for line: Variant in bonus_lines:
			var bullet := Label.new()
			bullet.text = "• " + str(line)
			bullet.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bullet.add_theme_font_size_override(&"font_size", 9)
			bullet.add_theme_color_override(&"font_color", Color(0.60, 0.85, 1.0))
			body.add_child(bullet)

	# Spendable choices
	var choices: Array = info.get("choices", [])
	var spend_title := Label.new()
	spend_title.text = "Spend points"
	spend_title.add_theme_font_size_override(&"font_size", 10)
	spend_title.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.55))
	body.add_child(spend_title)

	if choices.is_empty():
		var empty := Label.new()
		empty.text = "No perk choices authored for this skill yet."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override(&"font_size", 9)
		empty.add_theme_color_override(&"font_color", Color(0.65, 0.66, 0.70))
		body.add_child(empty)
	else:
		for choice: Variant in choices:
			body.add_child(_make_perk_choice_row(_selected_skill, choice as Dictionary, points))


func _make_perk_choice_row(skill_name: String, choice: Dictionary, available_points: int) -> Control:
	var rank: int = int(choice.get("rank", 0))
	var max_rank: int = int(choice.get("max_rank", 0))
	var perk_id: String = str(choice.get("id", ""))
	var perk_name: String = str(choice.get("name", ""))
	var effect: String = str(choice.get("effect", ""))
	var per_rank: float = float(choice.get("per_rank", 0.0))

	var panel := PanelContainer.new()
	_ensure_shared_styles()
	panel.add_theme_stylebox_override(&"panel", _style_perk_choice)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 6)
	margin.add_theme_constant_override(&"margin_right", 6)
	margin.add_theme_constant_override(&"margin_top", 4)
	margin.add_theme_constant_override(&"margin_bottom", 4)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	margin.add_child(row)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override(&"separation", 1)
	row.add_child(text_col)

	var name_label := Label.new()
	name_label.text = "%s  (%d/%d)" % [perk_name, rank, max_rank]
	name_label.add_theme_font_size_override(&"font_size", 10)
	name_label.add_theme_color_override(&"font_color", Color(0.95, 0.92, 0.86))
	text_col.add_child(name_label)

	var desc := Label.new()
	desc.text = JobPerks.describe_perk_effect(effect, per_rank)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override(&"font_size", 8)
	desc.add_theme_color_override(&"font_color", Color(0.62, 0.74, 0.86))
	text_col.add_child(desc)

	if rank > 0:
		var earned := Label.new()
		earned.text = "Active: %s" % JobPerks.describe_perk_effect(effect, per_rank * float(rank)).replace(
			" per rank", ""
		)
		earned.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		earned.add_theme_font_size_override(&"font_size", 8)
		earned.add_theme_color_override(&"font_color", Color(0.55, 0.82, 0.62))
		text_col.add_child(earned)

	var btn := Button.new()
	btn.text = "+"
	btn.custom_minimum_size = Vector2(28, 28)
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.disabled = available_points <= 0 or rank >= max_rank
	btn.tooltip_text = (
		"Max rank reached" if rank >= max_rank
		else ("No points available" if available_points <= 0 else "Spend 1 perk point")
	)
	btn.pressed.connect(_on_perk_pressed.bind(skill_name, perk_id))
	row.add_child(btn)

	return panel


func _on_perk_pressed(skill_name: String, perk_id: String) -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(
		&"skill.perk.choose",
		func(_d: Dictionary) -> void: _refresh_perks(),
		{"skill": skill_name, "perk": perk_id},
		InstanceClient.current.name
	)


func _place_panel() -> void:
	var hud := get_parent() as Control
	if hud == null:
		return
	var panel_size: Vector2 = (
		PANEL_SIZE_PERKS if _mode == Mode.PERKS else PANEL_SIZE_WEAPONS
	)
	# Shrink slightly on short viewports so the panel never starts above y=0
	# and never spills past the bottom clearance.
	var max_h: float = maxf(180.0, hud.size.y - BOTTOM_CLEARANCE)
	if panel_size.y > max_h:
		panel_size.y = max_h
	custom_minimum_size = panel_size
	size = panel_size
	# Force layout before positioning so scroll areas get a real height on the
	# first Perks detail open (avoids the "crops until reopen" glitch).
	reset_size()
	size = panel_size
	position = Vector2(
		hud.size.x - panel_size.x - RIGHT_MARGIN,
		maxi(0, int(hud.size.y - panel_size.y - BOTTOM_CLEARANCE))
	)
