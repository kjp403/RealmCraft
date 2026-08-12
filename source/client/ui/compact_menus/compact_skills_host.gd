extends PanelContainer
## Dock Skills panel — OSRS-style cells for live skills, plus a Combat tab
## that lists mastery-gated weapons per profession (Swordsmanship, etc.).

const PANEL_SIZE := Vector2(248.0, 320.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 72.0
const GRID_COLUMNS := 2
## Inventory-like skill cells: fixed block per skill (icon + levels).
const TILE_SIZE := Vector2(112.0, 48.0)

## Live skills only (slug keys match JobRegistry / save data).
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
	# Combat skill (category == &"combat"), listed last so the existing
	# gathering/crafting tiles keep their grid positions.
	"slayer",
]

## Slayer's detail page is hand-built (masters + task tables), not a JobPerks
## source/recipe list like every other skill — see _build_slayer_guide.
const SLAYER_SLUG: String = "slayer"

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
## Gathering skill detail sub-tab: &"resources" (sources) or &"tools".
var _detail_section: StringName = &"resources"
var _back_button: Button
## Latest slayer.info snapshot + the box that renders it, for the Slayer guide's
## "Current task" section.
var _slayer_info: Dictionary = {}
var _slayer_task_box: VBoxContainer
## slug -> { "button": Button, "cur": Label, "base": Label } — updated in place
## on gather so the XP tooltip under the mouse is not destroyed/recreated.
var _skill_tiles: Dictionary = {}
## Coalesce gather-driven skills.get while the dock is open.
var _skills_refresh_queued: bool = false
## Detail header widgets updated in place on XP ticks (avoids wiping the
## sources/recipes list — which can file-I/O deferred craft guides).
var _detail_level_label: Label
var _detail_xp_bar: ProgressBar
var _detail_xp_label: Label
var _style_tile_normal: StyleBoxFlat
var _style_tile_hover: StyleBoxFlat
var _style_tile_pressed: StyleBoxFlat
var _style_compact_normal: StyleBoxFlat
var _style_compact_hover: StyleBoxFlat
var _style_compact_pressed: StyleBoxFlat


func _ready() -> void:
	_ensure_shared_styles()
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
	# Keep the Slayer guide's "Current task" line ticking with the kill pushes,
	# same as the HUD tracker does.
	Client.subscribe(&"slayer.update", func(_payload: Dictionary) -> void:
		if visible and _selected_slug == SLAYER_SLUG:
			_request_slayer_info())

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
	_skills_grid.add_theme_constant_override(&"h_separation", 5)
	_skills_grid.add_theme_constant_override(&"v_separation", 5)
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
	_ensure_shared_styles()
	btn.add_theme_stylebox_override(&"normal", _style_compact_normal)
	btn.add_theme_stylebox_override(&"hover", _style_compact_hover)
	btn.add_theme_stylebox_override(&"pressed", _style_compact_pressed)
	btn.add_theme_stylebox_override(&"focus", _style_compact_normal)


func _ensure_shared_styles() -> void:
	if _style_compact_normal != null:
		return
	_style_compact_normal = StyleBoxFlat.new()
	_style_compact_normal.bg_color = Color(0.12, 0.11, 0.10, 0.95)
	_style_compact_normal.border_color = Color(0.48, 0.40, 0.28, 0.9)
	_style_compact_normal.set_border_width_all(1)
	_style_compact_normal.set_corner_radius_all(2)
	_style_compact_normal.content_margin_left = 4
	_style_compact_normal.content_margin_right = 4
	_style_compact_normal.content_margin_top = 1
	_style_compact_normal.content_margin_bottom = 1
	_style_compact_hover = _style_compact_normal.duplicate() as StyleBoxFlat
	_style_compact_hover.border_color = Color(0.92, 0.72, 0.28, 1.0)
	_style_compact_pressed = _style_compact_normal.duplicate() as StyleBoxFlat
	_style_compact_pressed.bg_color = Color(0.20, 0.15, 0.08, 1.0)
	_style_compact_pressed.border_color = Color(1.0, 0.82, 0.30, 1.0)

	_style_tile_normal = _make_cell_style()
	_style_tile_hover = _make_cell_style()
	_style_tile_hover.border_color = Color(0.92, 0.82, 0.28, 1.0)
	_style_tile_hover.bg_color = Color(0.20, 0.18, 0.14, 0.98)
	_style_tile_pressed = _make_cell_style()
	_style_tile_pressed.border_color = Color(1.0, 0.92, 0.35, 1.0)


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
	if not visible or _mode != Mode.SKILLS:
		return
	_queue_skills_refresh()


func _queue_skills_refresh() -> void:
	if _skills_refresh_queued:
		return
	_skills_refresh_queued = true
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		_skills_refresh_queued = false
		if visible and _mode == Mode.SKILLS:
			_refresh()
	, CONNECT_ONE_SHOT)


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
		# Prefer in-place XP/header updates so gather ticks don't rebuild the
		# full sources/recipes list (deferred craft guides do file I/O).
		if not _update_detail_header_inplace():
			_rebuild_detail()
	else:
		title_label.text = "Skills"
		# Prefer in-place tile updates so a hover tooltip survives gather XP ticks.
		_build_skills_grid(false)
		_total_level_bar.text = "Total level: %d" % total_level


func _update_detail_header_inplace() -> bool:
	if (
		_detail_level_label == null
		or _detail_xp_bar == null
		or _detail_xp_label == null
		or not is_instance_valid(_detail_level_label)
		or not is_instance_valid(_detail_xp_bar)
		or not is_instance_valid(_detail_xp_label)
	):
		return false
	if _selected_slug.is_empty() or not _skills.has(_selected_slug):
		return false
	var info: Dictionary = _skills[_selected_slug]
	var level: int = int(info.get("level", 1))
	var xp: int = int(info.get("xp", 0))
	var raw_next: int = int(info.get("xp_to_next", 1))
	var at_cap: bool = raw_next <= 0 or level >= SkillXp.LEVEL_CAP
	var xp_to_next: int = 1 if at_cap else maxi(1, raw_next)
	_detail_level_label.text = "Lv %d / %d" % [level, level]
	_detail_xp_bar.max_value = xp_to_next
	_detail_xp_bar.value = xp_to_next if at_cap else xp
	var total_xp: int = SkillXp.total_xp_for_level(level) + (0 if at_cap else xp)
	_detail_xp_label.text = (
		"Max · Total XP: %s" % _format_xp(total_xp) if at_cap
		else "%s / %s XP · Total %s" % [
			_format_xp(xp), _format_xp(xp_to_next), _format_xp(total_xp)
		]
	)
	return true


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
	_build_skills_grid(true)
	_total_level_bar.text = "Total level: %d" % _total_unlocked_level()


func _show_detail(slug: String) -> void:
	_selected_slug = slug
	_detail_section = &"resources"
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
		# Read progression from ClientState's mirrors — player_resource is
		# server-only and always null here, which pinned this to 0 and rendered
		# every row locked.
		var player_level: int = 0
		if _selected_combat_category == MasteryEquipmentGuide.ARMOR_CATEGORY:
			# Armor may gate on character level or any mastery — use character
			# level so "locked" rows match can_equip's level check.
			player_level = ClientState.player_level
			var gear := item as GearItem
			if gear != null and gear.required_mastery_level > 0:
				if gear.required_mastery_categories.has(&"any"):
					player_level = ClientState.best_mastery_level()
				else:
					player_level = 0
					for cat: StringName in gear.required_mastery_categories:
						player_level = maxi(
							player_level, ClientState.mastery_level(cat)
						)
		else:
			player_level = ClientState.mastery_level(_selected_combat_category)
		list.add_child(_make_source_row(item, req, player_level))


func _skill_info_for(slug: String) -> Dictionary:
	if _skills.has(slug):
		return _skills[slug] as Dictionary
	return {
		"display_name": JobRegistry.display_name(StringName(slug)),
		"level": 1,
		"xp": 0,
		"xp_to_next": 1,
	}


func _build_skills_grid(force_rebuild: bool = true) -> void:
	if (
		not force_rebuild
		and _skill_tiles.size() == SKILL_ORDER.size()
		and _skills_grid.get_child_count() == SKILL_ORDER.size()
	):
		for slug: String in SKILL_ORDER:
			_update_skill_tile(slug, _skill_info_for(slug))
		return

	for child: Node in _skills_grid.get_children():
		_skills_grid.remove_child(child)
		child.queue_free()
	_skill_tiles.clear()

	for slug: String in SKILL_ORDER:
		_skills_grid.add_child(_create_skill_tile(slug, _skill_info_for(slug)))


func _skill_tooltip(display: String, level: int, xp: int, xp_to_next: int, at_cap: bool, total_xp: int) -> String:
	if at_cap:
		return "%s\nLv %d — Max level\nTotal XP: %s\nClick for details" % [
			display, level, _format_xp(total_xp)
		]
	var remaining: int = maxi(0, xp_to_next - xp)
	return "%s\nLv %d — %s / %s XP\n%s XP to next level\nTotal XP: %s\nClick for details" % [
		display, level, _format_xp(xp), _format_xp(xp_to_next), _format_xp(remaining), _format_xp(total_xp)
	]


func _update_skill_tile(skill_name: String, info: Dictionary) -> void:
	var entry: Variant = _skill_tiles.get(skill_name, null)
	if entry == null or not (entry is Dictionary):
		return
	var tile_data: Dictionary = entry
	var tile: Button = tile_data.get("button") as Button
	var cur: Label = tile_data.get("cur") as Label
	var base: Label = tile_data.get("base") as Label
	if tile == null or cur == null or base == null:
		return

	var level: int = int(info.get("level", 1))
	var xp: int = int(info.get("xp", 0))
	var raw_next: int = int(info.get("xp_to_next", 1))
	var at_cap: bool = raw_next <= 0 or level >= SkillXp.LEVEL_CAP
	var xp_to_next: int = 1 if at_cap else maxi(1, raw_next)
	var display: String = str(info.get("display_name", skill_name.capitalize()))
	var total_xp: int = SkillXp.total_xp_for_level(level) + (0 if at_cap else xp)

	cur.text = str(level)
	base.text = str(level)
	tile.tooltip_text = _skill_tooltip(display, level, xp, xp_to_next, at_cap, total_xp)


func _create_skill_tile(skill_name: String, info: Dictionary) -> Button:
	var level: int = int(info.get("level", 1))
	var xp: int = int(info.get("xp", 0))
	var raw_next: int = int(info.get("xp_to_next", 1))
	var at_cap: bool = raw_next <= 0 or level >= SkillXp.LEVEL_CAP
	var xp_to_next: int = 1 if at_cap else maxi(1, raw_next)
	var display: String = str(info.get("display_name", skill_name.capitalize()))
	var total_xp: int = SkillXp.total_xp_for_level(level) + (0 if at_cap else xp)

	var tile := Button.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.custom_maximum_size = TILE_SIZE
	tile.size = TILE_SIZE
	tile.clip_contents = true
	tile.focus_mode = Control.FOCUS_NONE
	# flat=true skips StyleBox draws — keep false so each skill is a visible block.
	tile.flat = false
	tile.tooltip_text = _skill_tooltip(display, level, xp, xp_to_next, at_cap, total_xp)
	tile.pressed.connect(_show_detail.bind(skill_name))
	_apply_tile_styles(tile)

	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _get_skill_icon(skill_name)
	icon.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	icon.offset_left = 4
	icon.offset_top = 4
	icon.offset_right = 48
	icon.offset_bottom = -4
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

	_skill_tiles[skill_name] = {
		"button": tile,
		"cur": cur,
		"base": base,
	}
	return tile


func _rebuild_detail() -> void:
	for child: Node in _detail_root.get_children():
		_detail_root.remove_child(child)
		child.queue_free()
	_detail_level_label = null
	_detail_xp_bar = null
	_detail_xp_label = null

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
	_detail_level_label = header

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = xp_to_next
	bar.value = xp_to_next if at_cap else xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 7)
	bar.add_theme_stylebox_override(&"background", _make_bar_bg())
	bar.add_theme_stylebox_override(&"fill", _make_bar_fill())
	_detail_root.add_child(bar)
	_detail_xp_bar = bar

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
	_detail_xp_label = xp_label

	# Slayer has no gather/craft table — its "sources" are the MASTERS and the
	# tasks they hand out, so it renders its own guide (see _build_slayer_guide).
	var skill_slug := StringName(_selected_slug)
	var show_tools_tab: bool = (
		_selected_slug != SLAYER_SLUG and SkillToolsGuide.has_tools(skill_slug)
	)
	if show_tools_tab:
		_detail_root.add_child(_make_detail_section_tabs())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_root.add_child(scroll)
	DragScroll.enable(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 3)
	scroll.add_child(list)

	if _selected_slug == SLAYER_SLUG:
		_build_slayer_guide(list)
		return

	if show_tools_tab and _detail_section == &"tools":
		_fill_tools_list(list, skill_slug, level)
		return

	var jp: JobPerks = JobRegistry.perks_for(skill_slug)
	if jp != null and not jp.source_items.is_empty():
		if not show_tools_tab:
			var sources_title := Label.new()
			sources_title.text = "Resources"
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


# --- Slayer guide ------------------------------------------------------------

## The Slayer detail page: your current assignment (so the tracker's information
## is reachable even with the tracker switched off), then every master with its
## gate, payout, and full weighted task table. Masters + tasks are common/
## content (SlayerMasterRegistry), so this reads them directly — no round-trip,
## and masters the player has never met still show up with where to find them.
func _build_slayer_guide(list: VBoxContainer) -> void:
	list.add_child(_slayer_section_label("Current task"))
	_slayer_task_box = VBoxContainer.new()
	_slayer_task_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slayer_task_box.add_theme_constant_override(&"separation", 2)
	list.add_child(_slayer_task_box)
	_render_slayer_task()
	_request_slayer_info()

	var player_level: int = ClientState.skill_level(StringName(SLAYER_SLUG))
	for master_slug: StringName in SlayerMasterRegistry.MASTERS:
		var master: SlayerMasterResource = SlayerMasterRegistry.MASTERS[master_slug]
		if master == null:
			continue
		list.add_child(_slayer_master_header(master, player_level))
		for row: Control in _slayer_task_rows(master, player_level):
			list.add_child(row)


## Master name + the three numbers that decide whether it's worth walking there:
## the Slayer level it wants, what a finished task pays, and the reassign policy.
func _slayer_master_header(
	master: SlayerMasterResource,
	player_level: int
) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 1)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 4)
	box.add_child(name_row)

	var locked: bool = player_level < master.min_slayer_level
	var name_label := Label.new()
	name_label.text = master.master_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override(&"font_size", 12)
	name_label.add_theme_color_override(
		&"font_color",
		Color(0.6, 0.6, 0.64) if locked else Color(0.95, 0.85, 0.55)
	)
	name_row.add_child(name_label)

	var gate := Label.new()
	gate.text = "Any level" if master.min_slayer_level <= 1 else "Lv %d" % master.min_slayer_level
	gate.add_theme_font_size_override(&"font_size", 10)
	gate.add_theme_color_override(
		&"font_color",
		Color(0.9, 0.45, 0.4) if locked else Color(0.75, 0.85, 1.0)
	)
	name_row.add_child(gate)

	if not master.location_hint.is_empty():
		box.add_child(_slayer_note(master.location_hint, Color(0.68, 0.72, 0.8)))
	var payout: String = "%d pts / task  ·  %s" % [
		master.base_points_per_task,
		"free reassign" if master.free_reassign
			else "skip %d pts" % master.reassign_point_cost,
	]
	box.add_child(_slayer_note(payout, Color(0.62, 0.66, 0.72)))
	return box


## One row per pool entry: the task, the quantity range, and how likely it is to
## be rolled (weight as a share of the master's whole table — the number players
## actually want, rather than the raw weight).
func _slayer_task_rows(
	master: SlayerMasterResource,
	player_level: int
) -> Array[Control]:
	var rows: Array[Control] = []
	var total_weight: int = 0
	for entry: SlayerMasterTaskEntry in master.pool:
		if entry != null and entry.task != null and entry.weight > 0:
			total_weight += entry.weight
	if total_weight <= 0:
		rows.append(_slayer_note("No tasks authored.", Color(0.65, 0.66, 0.7)))
		return rows

	var entries: Array[SlayerMasterTaskEntry] = []
	for entry: SlayerMasterTaskEntry in master.pool:
		if entry != null and entry.task != null and entry.weight > 0:
			entries.append(entry)
	# Commonest first — the table reads as "what you'll mostly be sent after".
	entries.sort_custom(func(a: SlayerMasterTaskEntry, b: SlayerMasterTaskEntry) -> bool:
		if a.weight != b.weight:
			return a.weight > b.weight
		return a.task.display_name.nocasecmp_to(b.task.display_name) < 0)

	for entry: SlayerMasterTaskEntry in entries:
		var locked: bool = player_level < entry.task.min_slayer_level
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_theme_constant_override(&"separation", 4)

		var name_label := Label.new()
		name_label.text = "   " + entry.task.display_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override(&"font_size", 10)
		name_label.add_theme_color_override(
			&"font_color",
			Color(0.55, 0.55, 0.58) if locked else Color(0.88, 0.88, 0.92)
		)
		row.add_child(name_label)

		var amount := Label.new()
		amount.text = "%d–%d" % [entry.min_amount, entry.max_amount]
		amount.add_theme_font_size_override(&"font_size", 9)
		amount.add_theme_color_override(&"font_color", Color(0.7, 0.74, 0.8))
		row.add_child(amount)

		var chance := Label.new()
		chance.text = (
			"Lv %d" % entry.task.min_slayer_level if locked
			else "%d%%" % int(round(100.0 * float(entry.weight) / float(total_weight)))
		)
		chance.custom_minimum_size = Vector2(30, 0)
		chance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		chance.add_theme_font_size_override(&"font_size", 9)
		chance.add_theme_color_override(
			&"font_color",
			Color(0.9, 0.45, 0.4) if locked else Color(0.75, 0.85, 1.0)
		)
		row.add_child(chance)
		rows.append(row)
	return rows


func _slayer_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.55))
	return label


func _slayer_note(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", 9)
	label.add_theme_color_override(&"font_color", color)
	return label


func _request_slayer_info() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(
		&"slayer.info",
		func(data: Dictionary) -> void:
			if not bool(data.get("ok", false)):
				return
			_slayer_info = data
			_render_slayer_task(),
		{},
		InstanceClient.current.name
	)


func _render_slayer_task() -> void:
	if not is_instance_valid(_slayer_task_box):
		return
	for child: Node in _slayer_task_box.get_children():
		child.queue_free()

	var has_task: bool = (
		_slayer_info.has("display_name")
		and not str(_slayer_info.get("display_name", "")).is_empty()
	)
	if not has_task:
		_slayer_task_box.add_child(_slayer_note(
			"No task assigned. Visit a master below.", Color(0.65, 0.66, 0.7)
		))
		return

	var assigned: int = int(_slayer_info.get("assigned_amount", 0))
	var remaining: int = int(_slayer_info.get("remaining", 0))
	_slayer_task_box.add_child(_slayer_note(
		"%s — %d / %d killed, %d left" % [
			str(_slayer_info.get("display_name", "?")),
			maxi(0, assigned - remaining),
			assigned,
			remaining,
		],
		Color(0.95, 0.88, 0.6)
	))
	_slayer_task_box.add_child(_slayer_note(
		"%d points  ·  streak %d" % [
			int(_slayer_info.get("points", 0)),
			int(_slayer_info.get("streak", 0)),
		],
		Color(0.7, 0.74, 0.8)
	))
	var notes: String = str(_slayer_info.get("guide_notes", ""))
	if not notes.is_empty():
		_slayer_task_box.add_child(_slayer_note(notes, Color(0.65, 0.7, 0.78)))


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


func _make_detail_section_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 3)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var group := ButtonGroup.new()
	for section: StringName in [&"resources", &"tools"]:
		var btn := Button.new()
		btn.text = "Resources" if section == &"resources" else "Tools"
		btn.toggle_mode = true
		btn.button_group = group
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 18)
		btn.add_theme_font_size_override(&"font_size", 9)
		_apply_compact_button_style(btn)
		btn.button_pressed = _detail_section == section
		btn.pressed.connect(_set_detail_section.bind(section))
		row.add_child(btn)
	return row


func _set_detail_section(section: StringName) -> void:
	if _detail_section == section:
		return
	_detail_section = section
	_rebuild_detail()


func _fill_tools_list(list: VBoxContainer, skill_slug: StringName, player_level: int) -> void:
	var entries: Array[Dictionary] = SkillToolsGuide.tools_for(skill_slug)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "No tools found for this skill."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override(&"font_color", Color(0.65, 0.66, 0.7))
		empty.add_theme_font_size_override(&"font_size", 11)
		list.add_child(empty)
		return

	for entry: Dictionary in entries:
		var tool: ToolItem = entry.get("item", null) as ToolItem
		if tool == null:
			continue
		var req: int = int(entry.get("level", 0))
		list.add_child(_make_tool_row(tool, req, player_level))


func _make_tool_row(tool: ToolItem, required_level: int, player_level: int) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 0)

	var row := _make_source_row(tool, required_level, player_level)
	box.add_child(row)

	var blurb: String = SkillToolsGuide.bonus_blurb(tool)
	if not blurb.is_empty():
		var bonus := Label.new()
		bonus.text = blurb
		bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bonus.add_theme_font_size_override(&"font_size", 8)
		var locked: bool = required_level > player_level
		bonus.add_theme_color_override(
			&"font_color",
			Color(0.5, 0.5, 0.54) if locked else Color(0.62, 0.78, 0.68)
		)
		box.add_child(bonus)
	return box


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
	_ensure_shared_styles()
	tile.add_theme_stylebox_override(&"normal", _style_tile_normal)
	tile.add_theme_stylebox_override(&"hover", _style_tile_hover)
	tile.add_theme_stylebox_override(&"pressed", _style_tile_pressed)
	tile.add_theme_stylebox_override(&"focus", _style_tile_normal)


func _make_cell_style() -> StyleBoxFlat:
	# Match inventory/bank slot blocks: dark inset + warm border.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.03, 0.055, 0.92)
	style.border_color = Color(0.55, 0.36, 0.20, 0.95)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
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
