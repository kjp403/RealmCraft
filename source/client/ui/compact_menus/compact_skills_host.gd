extends PanelContainer
## Dock Skills panel — OSRS-style cells for live skills, plus a Combat tab
## that lists mastery-gated weapons per profession (Swordsmanship, etc.).

const PANEL_SIZE := Vector2(248.0, 320.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 52.0
const GRID_COLUMNS := 2
const TILE_SIZE := Vector2(112.0, 52.0)

## Live skills only (slug keys match JobRegistry / save data).
const SKILL_ORDER: Array[String] = [
	"mining",
	"smithing",
	"fishing",
	"cooking",
	"outfitting",
	"woodcutting",
	"harvesting",
	# Combat skill (category == &"combat"), listed last so the existing
	# gathering/crafting tiles keep their grid positions.
	"slayer",
]

enum Mode { SKILLS, COMBAT }

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

var _mode: Mode = Mode.SKILLS
var _mode_tabs: HBoxContainer
var _skills: Dictionary = {}
var _skills_grid: GridContainer
var _grid_root: Control
var _detail_root: VBoxContainer
var _combat_root: Control
var _total_level_bar: Label
var _selected_slug: String = ""
var _selected_combat_category: StringName = &""
var _back_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

	content.add_theme_constant_override(&"margin_left", 4)
	content.add_theme_constant_override(&"margin_right", 4)
	content.add_theme_constant_override(&"margin_top", 2)
	content.add_theme_constant_override(&"margin_bottom", 4)

	header_spacer.hide()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "Skills"
	title_label.add_theme_color_override(&"font_color", Color(0.98, 0.92, 0.35))
	title_label.add_theme_font_size_override(&"font_size", 13)
	var header_row: Control = title_label.get_parent() as Control
	if header_row != null:
		header_row.custom_minimum_size = Vector2(0, 22)
	close_button.custom_minimum_size = Vector2(22, 22)
	clip_contents = true

	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()

	_build_layout()

	close_button.pressed.connect(_on_close_pressed)
	visibility_changed.connect(_on_visibility_changed)
	ClientState.gather_succeeded.connect(_on_gather_succeeded)
	Client.subscribe(&"skills.get", _on_skills_received)

	var hud := get_parent() as Control
	if hud != null:
		hud.resized.connect(_place_panel)

	call_deferred(&"_place_panel")
	hide()


func _build_layout() -> void:
	_mode_tabs = HBoxContainer.new()
	_mode_tabs.add_theme_constant_override(&"separation", 4)
	_mode_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_mode_tabs)
	# Put tabs above grid by rebuilding: content is MarginContainer, children stack?
	# MarginContainer only shows one child well — use a VBox as sole content child.
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override(&"separation", 2)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(root)

	_mode_tabs = HBoxContainer.new()
	_mode_tabs.add_theme_constant_override(&"separation", 3)
	root.add_child(_mode_tabs)
	var mode_group := ButtonGroup.new()
	var skills_tab := _make_mode_tab("Skills", Mode.SKILLS, mode_group)
	var combat_tab := _make_mode_tab("Combat", Mode.COMBAT, mode_group)
	_mode_tabs.add_child(skills_tab)
	_mode_tabs.add_child(combat_tab)
	skills_tab.button_pressed = true

	_grid_root = VBoxContainer.new()
	_grid_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_root.add_theme_constant_override(&"separation", 4)
	root.add_child(_grid_root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid_root.add_child(scroll)

	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_center)

	_skills_grid = GridContainer.new()
	_skills_grid.columns = GRID_COLUMNS
	_skills_grid.add_theme_constant_override(&"h_separation", 4)
	_skills_grid.add_theme_constant_override(&"v_separation", 4)
	grid_center.add_child(_skills_grid)

	_total_level_bar = Label.new()
	_total_level_bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_level_bar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_total_level_bar.custom_minimum_size = Vector2(0, 22)
	_total_level_bar.add_theme_font_size_override(&"font_size", 12)
	_total_level_bar.add_theme_color_override(&"font_color", Color(1.0, 1.0, 0.0))
	_total_level_bar.text = "Total level: —"
	var total_panel := PanelContainer.new()
	total_panel.add_theme_stylebox_override(&"panel", _make_total_bar_style())
	total_panel.add_child(_total_level_bar)
	_grid_root.add_child(total_panel)

	_detail_root = VBoxContainer.new()
	_detail_root.visible = false
	_detail_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_root.add_theme_constant_override(&"separation", 3)
	root.add_child(_detail_root)

	_combat_root = VBoxContainer.new()
	_combat_root.visible = false
	_combat_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_combat_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_combat_root.add_theme_constant_override(&"separation", 3)
	root.add_child(_combat_root)


func _make_mode_tab(label: String, mode: Mode, group: ButtonGroup) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.toggle_mode = true
	btn.button_group = group
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 18)
	btn.add_theme_font_size_override(&"font_size", 9)
	btn.add_theme_constant_override(&"outline_size", 0)
	_apply_compact_button_style(btn)
	btn.pressed.connect(_set_mode.bind(mode))
	return btn


func _apply_compact_button_style(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.11, 0.10, 0.95)
	normal.border_color = Color(0.48, 0.40, 0.28, 0.9)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 4
	normal.content_margin_right = 4
	normal.content_margin_top = 1
	normal.content_margin_bottom = 1
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = Color(0.92, 0.72, 0.28, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.20, 0.15, 0.08, 1.0)
	pressed.border_color = Color(1.0, 0.82, 0.30, 1.0)
	btn.add_theme_stylebox_override(&"normal", normal)
	btn.add_theme_stylebox_override(&"hover", hover)
	btn.add_theme_stylebox_override(&"pressed", pressed)
	btn.add_theme_stylebox_override(&"focus", normal)


func _set_mode(mode: Mode) -> void:
	_mode = mode
	_selected_slug = ""
	_selected_combat_category = &""
	_detail_root.visible = false
	if mode == Mode.SKILLS:
		_combat_root.visible = false
		_grid_root.visible = true
		title_label.text = "Skills"
		_build_skills_grid()
		_total_level_bar.text = "Total level: %d" % _total_unlocked_level()
	else:
		_grid_root.visible = false
		_combat_root.visible = true
		title_label.text = "Combat"
		_build_combat_categories()



func _on_close_pressed() -> void:
	if _detail_root.visible:
		if _mode == Mode.COMBAT and _selected_combat_category != &"":
			_selected_combat_category = &""
			_detail_root.visible = false
			_combat_root.visible = true
			title_label.text = "Combat"
			_build_combat_categories()
			return
		_show_grid()
		return
	if _mode == Mode.COMBAT and _combat_root.visible and _selected_combat_category != &"":
		_selected_combat_category = &""
		_build_combat_categories()
		return
	hide()


func _on_visibility_changed() -> void:
	if visible:
		if _mode == Mode.COMBAT:
			_set_mode(Mode.COMBAT)
		else:
			_show_grid()
		_refresh()
	else:
		_selected_slug = ""
		_selected_combat_category = &""


func _on_gather_succeeded(_result: Dictionary) -> void:
	if visible and _mode == Mode.SKILLS:
		_refresh()


func _refresh() -> void:
	if not visible:
		return
	if InstanceClient.current == null:
		return
	Client.request_data(
		&"skills.get",
		_on_skills_received,
		{},
		InstanceClient.current.name
	)


func _on_skills_received(data: Dictionary) -> void:
	_skills = data.get("skills", {})
	var total_level: int = _total_unlocked_level()
	if _mode != Mode.SKILLS:
		return
	if _detail_root.visible and _selected_slug != "":
		title_label.text = str(
			(_skills.get(_selected_slug, {}) as Dictionary).get(
				"display_name", _selected_slug.capitalize()
			)
		)
		_rebuild_detail()
	else:
		title_label.text = "Skills"
		_build_skills_grid()
		_total_level_bar.text = "Total level: %d" % total_level


func _total_unlocked_level() -> int:
	var total_level: int = 0
	for skill_name: Variant in _skills:
		total_level += int((_skills[skill_name] as Dictionary).get("level", 1))
	return total_level


func _show_grid() -> void:
	_selected_slug = ""
	_selected_combat_category = &""
	_detail_root.visible = false
	_combat_root.visible = false
	_grid_root.visible = true
	_mode = Mode.SKILLS
	title_label.text = "Skills"
	_build_skills_grid()
	_total_level_bar.text = "Total level: %d" % _total_unlocked_level()


func _show_detail(slug: String) -> void:
	_selected_slug = slug
	_grid_root.visible = false
	_combat_root.visible = false
	_detail_root.visible = true
	_rebuild_detail()


func _build_combat_categories() -> void:
	for child: Node in _combat_root.get_children():
		_combat_root.remove_child(child)
		child.queue_free()

	var hint := Label.new()
	hint.text = "Mastery gear unlocks"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override(&"font_size", 11)
	hint.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.55))
	_combat_root.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_combat_root.add_child(scroll)
	DragScroll.enable(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 4)
	scroll.add_child(list)

	for cat: StringName in MasteryEquipmentGuide.CATEGORY_ORDER:
		var btn := Button.new()
		btn.text = MasteryEquipmentGuide.display_name_for(cat)
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 22)
		btn.add_theme_font_size_override(&"font_size", 10)
		_apply_compact_button_style(btn)
		btn.pressed.connect(_show_combat_category.bind(cat))
		list.add_child(btn)


func _show_combat_category(category: StringName) -> void:
	_selected_combat_category = category
	_combat_root.visible = false
	_detail_root.visible = true
	title_label.text = MasteryEquipmentGuide.display_name_for(category)
	_rebuild_combat_detail()


func _back_to_combat_categories() -> void:
	_selected_combat_category = &""
	_detail_root.visible = false
	_combat_root.visible = true
	title_label.text = "Combat"
	_build_combat_categories()


func _rebuild_combat_detail() -> void:
	for child: Node in _detail_root.get_children():
		_detail_root.remove_child(child)
		child.queue_free()

	var back := Button.new()
	back.text = "← Combat"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(0, 18)
	back.add_theme_font_size_override(&"font_size", 9)
	_apply_compact_button_style(back)
	back.pressed.connect(_back_to_combat_categories)
	_detail_root.add_child(back)

	var blurb := Label.new()
	blurb.text = (
		"Level / mastery required to equip"
		if _selected_combat_category == MasteryEquipmentGuide.ARMOR_CATEGORY
		else "Mastery level required to equip"
	)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override(&"font_size", 9)
	blurb.add_theme_color_override(&"font_color", Color(0.72, 0.74, 0.80))
	_detail_root.add_child(blurb)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_root.add_child(scroll)
	DragScroll.enable(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 3)
	scroll.add_child(list)

	var entries: Array[Dictionary] = MasteryEquipmentGuide.weapons_for(
		_selected_combat_category
	)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = (
			"No armor found."
			if _selected_combat_category == MasteryEquipmentGuide.ARMOR_CATEGORY
			else "No weapons found for this mastery."
		)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override(&"font_color", Color(0.65, 0.66, 0.7))
		list.add_child(empty)
		return

	for entry: Dictionary in entries:
		var item: Item = entry.get("item", null) as Item
		if item == null:
			continue
		var req: int = int(entry.get("level", 0))
		var player_level: int = 0
		var local_player := _local_player()
		if local_player != null and local_player.player_resource != null:
			if _selected_combat_category == MasteryEquipmentGuide.ARMOR_CATEGORY:
				# Armor may gate on character level or any mastery — use
				# character level so "locked" rows match can_equip's level check.
				player_level = int(local_player.player_resource.level)
				var gear := item as GearItem
				if gear != null and gear.required_mastery_level > 0:
					player_level = 0
					for cat: StringName in gear.required_mastery_categories:
						player_level = maxi(
							player_level,
							local_player.player_resource.mastery_level_of(cat)
						)
					if gear.required_mastery_categories.has(&"any"):
						for cat2: StringName in MasteryService.trees():
							player_level = maxi(
								player_level,
								local_player.player_resource.mastery_level_of(cat2)
							)
			else:
				player_level = local_player.player_resource.mastery_level_of(
					_selected_combat_category
				)
		list.add_child(_make_source_row(item, req, player_level))


func _local_player() -> Player:
	return ClientState.local_player as Player


func _build_skills_grid() -> void:
	for child: Node in _skills_grid.get_children():
		_skills_grid.remove_child(child)
		child.queue_free()

	for slug: String in SKILL_ORDER:
		if _skills.has(slug):
			_skills_grid.add_child(_create_skill_tile(slug, _skills[slug]))
		else:
			var info: Dictionary = {
				"display_name": JobRegistry.display_name(StringName(slug)),
				"level": 1,
				"xp": 0,
				"xp_to_next": 1,
			}
			_skills_grid.add_child(_create_skill_tile(slug, info))


func _create_skill_tile(skill_name: String, info: Dictionary) -> Button:
	var level: int = int(info.get("level", 1))
	var xp: int = int(info.get("xp", 0))
	var raw_next: int = int(info.get("xp_to_next", 1))
	var at_cap: bool = raw_next <= 0 or level >= SkillXp.LEVEL_CAP
	var xp_to_next: int = 1 if at_cap else maxi(1, raw_next)
	var display: String = str(info.get("display_name", skill_name.capitalize()))
	var remaining: int = 0 if at_cap else maxi(0, xp_to_next - xp)
	var total_xp: int = SkillXp.total_xp_for_level(level) + (0 if at_cap else xp)

	var tile := Button.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.size = TILE_SIZE
	tile.clip_contents = true
	tile.focus_mode = Control.FOCUS_NONE
	tile.flat = true
	if at_cap:
		tile.tooltip_text = "%s\nLv %d — Max level\nTotal XP: %s\nClick for details" % [
			display, level, _format_xp(total_xp)
		]
	else:
		tile.tooltip_text = "%s\nLv %d — %s / %s XP\n%s XP to next level\nTotal XP: %s\nClick for details" % [
			display, level, _format_xp(xp), _format_xp(xp_to_next), _format_xp(remaining), _format_xp(total_xp)
		]
	tile.pressed.connect(_show_detail.bind(skill_name))
	_apply_tile_styles(tile)

	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _get_skill_icon(skill_name)
	icon.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	icon.offset_left = 2
	icon.offset_top = 2
	icon.offset_right = 50
	icon.offset_bottom = -2
	tile.add_child(icon)

	if icon.texture == null:
		var fallback := Label.new()
		fallback.text = display.left(1).to_upper()
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.add_theme_font_size_override(&"font_size", 14)
		fallback.add_theme_color_override(&"font_color", Color(0.82, 0.72, 0.52))
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.add_child(fallback)

	# OSRS-style diagonal current / base levels (yellow).
	var cur := Label.new()
	cur.text = str(level)
	cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cur.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cur.add_theme_font_size_override(&"font_size", 12)
	cur.add_theme_color_override(&"font_color", Color(1.0, 1.0, 0.0))
	cur.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 1))
	cur.add_theme_constant_override(&"shadow_offset_x", 1)
	cur.add_theme_constant_override(&"shadow_offset_y", 1)
	cur.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cur.offset_left = -40
	cur.offset_top = 2
	cur.offset_right = -10
	cur.offset_bottom = 18
	tile.add_child(cur)

	var base := Label.new()
	base.text = str(level)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	base.add_theme_font_size_override(&"font_size", 12)
	base.add_theme_color_override(&"font_color", Color(1.0, 1.0, 0.0))
	base.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 1))
	base.add_theme_constant_override(&"shadow_offset_x", 1)
	base.add_theme_constant_override(&"shadow_offset_y", 1)
	base.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	base.offset_left = -32
	base.offset_top = -18
	base.offset_right = -4
	base.offset_bottom = -2
	tile.add_child(base)

	var slash := Label.new()
	slash.text = "/"
	slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slash.add_theme_font_size_override(&"font_size", 11)
	slash.add_theme_color_override(&"font_color", Color(1.0, 1.0, 0.0))
	slash.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	slash.offset_left = -28
	slash.offset_top = -8
	slash.offset_right = -16
	slash.offset_bottom = 8
	tile.add_child(slash)

	return tile


func _rebuild_detail() -> void:
	for child: Node in _detail_root.get_children():
		_detail_root.remove_child(child)
		child.queue_free()

	if _selected_slug.is_empty() or not _skills.has(_selected_slug):
		_show_grid()
		return

	var info: Dictionary = _skills[_selected_slug]
	var display: String = str(info.get("display_name", _selected_slug.capitalize()))
	var level: int = int(info.get("level", 1))
	var xp: int = int(info.get("xp", 0))
	var raw_next: int = int(info.get("xp_to_next", 1))
	var at_cap: bool = raw_next <= 0 or level >= SkillXp.LEVEL_CAP
	var xp_to_next: int = 1 if at_cap else maxi(1, raw_next)
	title_label.text = display

	_back_button = Button.new()
	_back_button.text = "← All skills"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.custom_minimum_size = Vector2(0, 18)
	_back_button.add_theme_font_size_override(&"font_size", 9)
	_apply_compact_button_style(_back_button)
	_back_button.pressed.connect(_show_grid)
	_detail_root.add_child(_back_button)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override(&"separation", 4)
	header_row.custom_minimum_size = Vector2(0, 18)
	_detail_root.add_child(header_row)

	var detail_icon := TextureRect.new()
	detail_icon.custom_minimum_size = Vector2(16, 16)
	detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	detail_icon.texture = _get_skill_icon(_selected_slug)
	header_row.add_child(detail_icon)

	var header := Label.new()
	header.text = "Lv %d / %d" % [level, level]
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override(&"font_size", 11)
	header.add_theme_color_override(&"font_color", Color(1.0, 1.0, 0.0))
	header_row.add_child(header)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = xp_to_next
	bar.value = xp_to_next if at_cap else xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 7)
	bar.add_theme_stylebox_override(&"background", _make_bar_bg())
	bar.add_theme_stylebox_override(&"fill", _make_bar_fill())
	_detail_root.add_child(bar)

	var xp_label := Label.new()
	var total_xp: int = SkillXp.total_xp_for_level(level) + (0 if at_cap else xp)
	xp_label.text = (
		"Max · Total XP: %s" % _format_xp(total_xp) if at_cap
		else "%s / %s XP · Total %s" % [
			_format_xp(xp), _format_xp(xp_to_next), _format_xp(total_xp)
		]
	)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	xp_label.add_theme_font_size_override(&"font_size", 8)
	xp_label.add_theme_color_override(&"font_color", Color(0.72, 0.74, 0.8))
	_detail_root.add_child(xp_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_root.add_child(scroll)
	DragScroll.enable(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 3)
	scroll.add_child(list)

	var jp: JobPerks = JobRegistry.perks_for(StringName(_selected_slug))
	if jp != null and not jp.source_items.is_empty():
		var sources_title := Label.new()
		sources_title.text = "Can gather"
		sources_title.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.55))
		sources_title.add_theme_font_size_override(&"font_size", 12)
		list.add_child(sources_title)
		for i: int in jp.source_items.size():
			var item: Item = jp.source_items[i]
			if item == null:
				continue
			var req: int = jp.source_levels[i] if i < jp.source_levels.size() else 0
			list.add_child(_make_source_row(item, req, level))
	elif jp != null and jp.has_recipe_guide():
		var recipes_title := Label.new()
		recipes_title.text = "Can craft"
		recipes_title.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.55))
		recipes_title.add_theme_font_size_override(&"font_size", 12)
		list.add_child(recipes_title)
		for entry: Dictionary in jp.recipe_guide_entries():
			var item: Item = entry.get("item", null) as Item
			if item == null:
				continue
			var req: int = int(entry.get("level", 0))
			list.add_child(_make_source_row(item, req, level))
	else:
		var empty := Label.new()
		empty.text = "No source list authored for this skill yet."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override(&"font_color", Color(0.65, 0.66, 0.7))
		empty.add_theme_font_size_override(&"font_size", 11)
		list.add_child(empty)


func _make_source_row(item: Item, required_level: int, player_level: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = item.item_icon
	row.add_child(icon)

	var name_label := Label.new()
	name_label.text = String(item.item_name)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override(&"font_size", 11)
	var locked: bool = required_level > player_level
	name_label.add_theme_color_override(
		&"font_color",
		Color(0.55, 0.55, 0.58) if locked else Color(0.9, 0.9, 0.92)
	)
	row.add_child(name_label)

	var lvl := Label.new()
	if required_level <= 0:
		lvl.text = "Any"
	else:
		lvl.text = "Lv %d" % required_level
	lvl.add_theme_font_size_override(&"font_size", 10)
	lvl.add_theme_color_override(
		&"font_color",
		Color(0.9, 0.45, 0.4) if locked else Color(0.75, 0.85, 1.0)
	)
	row.add_child(lvl)
	return row


func _get_skill_icon(skill_name: String) -> Texture2D:
	var job := JobRegistry.perks_for(StringName(skill_name))
	if job == null:
		return null
	if job.icon != null:
		return job.icon
	if not job.source_items.is_empty() and job.source_items[0] != null:
		return job.source_items[0].item_icon
	if not job.recipe_items.is_empty() and job.recipe_items[0] != null:
		return job.recipe_items[0].item_icon
	return null


func _apply_tile_styles(tile: Button) -> void:
	var normal := _make_cell_style()
	var hover := _make_cell_style()
	hover.border_color = Color(0.92, 0.82, 0.28, 1.0)
	hover.bg_color = Color(0.20, 0.18, 0.14, 0.98)
	var pressed := _make_cell_style()
	pressed.border_color = Color(1.0, 0.92, 0.35, 1.0)
	tile.add_theme_stylebox_override(&"normal", normal)
	tile.add_theme_stylebox_override(&"hover", hover)
	tile.add_theme_stylebox_override(&"pressed", pressed)
	tile.add_theme_stylebox_override(&"focus", normal)


func _make_cell_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.15, 0.14, 0.97)
	style.border_color = Color(0.48, 0.44, 0.38, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 2
	style.content_margin_right = 2
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


func _make_total_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.02, 0.95)
	style.border_color = Color(0.42, 0.38, 0.32, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(1)
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	return style


func _make_bar_bg() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.1, 0.95)
	style.set_corner_radius_all(2)
	return style


func _make_bar_fill() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.75, 0.28, 1.0)
	style.set_corner_radius_all(2)
	return style


func _format_xp(value: int) -> String:
	var text := str(maxi(0, value))
	var out := ""
	var count: int = 0
	for i: int in range(text.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = text[i] + out
		count += 1
	return out


func _place_panel() -> void:
	var hud := get_parent() as Control
	if hud == null:
		return
	size = PANEL_SIZE
	position = Vector2(
		hud.size.x - PANEL_SIZE.x - RIGHT_MARGIN,
		hud.size.y - PANEL_SIZE.y - BOTTOM_CLEARANCE
	)
