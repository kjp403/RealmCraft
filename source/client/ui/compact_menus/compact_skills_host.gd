extends PanelContainer
## Dock Skills panel: job icons with XP bars. Click a skill (e.g. Mining) to see
## level progress and what sources / recipes unlock at which level.

const PANEL_SIZE := Vector2(220.0, 300.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 52.0
const GRID_COLUMNS := 3
const TILE_SIZE := Vector2(60.0, 64.0)

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

var _skills: Dictionary = {}
var _skills_grid: GridContainer
var _grid_root: Control
var _detail_root: VBoxContainer
var _selected_slug: String = ""
var _back_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

	content.add_theme_constant_override(&"margin_left", 6)
	content.add_theme_constant_override(&"margin_right", 6)

	header_spacer.hide()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "Skills"

	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()

	_build_layout()

	close_button.pressed.connect(_on_close_pressed)
	visibility_changed.connect(_on_visibility_changed)
	ClientState.gather_succeeded.connect(_on_gather_succeeded)

	var hud := get_parent() as Control
	if hud != null:
		hud.resized.connect(_place_panel)

	call_deferred(&"_place_panel")
	hide()


func _build_layout() -> void:
	_grid_root = Control.new()
	_grid_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(_grid_root)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	_detail_root = VBoxContainer.new()
	_detail_root.visible = false
	_detail_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_root.add_theme_constant_override(&"separation", 6)
	_detail_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_child(_detail_root)


func _on_close_pressed() -> void:
	if _detail_root.visible:
		_show_grid()
		return
	hide()


func _on_visibility_changed() -> void:
	if visible:
		_show_grid()
		_refresh()
	else:
		_selected_slug = ""


func _on_gather_succeeded(_result: Dictionary) -> void:
	if visible:
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
	var total_level: int = 0
	for skill_name: Variant in _skills:
		total_level += int((_skills[skill_name] as Dictionary).get("level", 1))
	if _detail_root.visible and _selected_slug != "":
		title_label.text = str(
			(_skills.get(_selected_slug, {}) as Dictionary).get(
				"display_name", _selected_slug.capitalize()
			)
		)
		_rebuild_detail()
	else:
		title_label.text = "Skills · %d" % total_level
		_build_skills_grid()


func _show_grid() -> void:
	_selected_slug = ""
	_detail_root.visible = false
	_grid_root.visible = true
	var total_level: int = 0
	for skill_name: Variant in _skills:
		total_level += int((_skills[skill_name] as Dictionary).get("level", 1))
	title_label.text = "Skills · %d" % total_level
	_build_skills_grid()


func _show_detail(slug: String) -> void:
	_selected_slug = slug
	_grid_root.visible = false
	_detail_root.visible = true
	_rebuild_detail()


func _build_skills_grid() -> void:
	for child: Node in _skills_grid.get_children():
		_skills_grid.remove_child(child)
		child.queue_free()

	var entries: Array[Dictionary] = []
	for skill_name: Variant in _skills:
		entries.append({
			"slug": String(skill_name),
			"info": _skills[skill_name],
		})
	entries.sort_custom(_sort_skills)

	for entry: Dictionary in entries:
		_skills_grid.add_child(
			_create_skill_tile(String(entry["slug"]), entry["info"])
		)


func _sort_skills(a: Dictionary, b: Dictionary) -> bool:
	var a_info: Dictionary = a["info"]
	var b_info: Dictionary = b["info"]
	var a_category_order: int = 0 if str(a_info.get("category", "")) == "gathering" else 1
	var b_category_order: int = 0 if str(b_info.get("category", "")) == "gathering" else 1
	if a_category_order != b_category_order:
		return a_category_order < b_category_order
	return int(a_info.get("order", 0)) < int(b_info.get("order", 0))


func _create_skill_tile(skill_name: String, info: Dictionary) -> Button:
	var level: int = int(info.get("level", 1))
	var xp: int = int(info.get("xp", 0))
	var raw_next: int = int(info.get("xp_to_next", 1))
	var at_cap: bool = raw_next <= 0 or level >= SkillXp.LEVEL_CAP
	var xp_to_next: int = 1 if at_cap else maxi(1, raw_next)
	var display: String = str(info.get("display_name", skill_name.capitalize()))
	var remaining: int = 0 if at_cap else maxi(0, xp_to_next - xp)

	var tile := Button.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.size = TILE_SIZE
	tile.clip_contents = true
	tile.focus_mode = Control.FOCUS_NONE
	if at_cap:
		tile.tooltip_text = "%s\nLv %d — Max level\nClick for details" % [display, level]
	else:
		tile.tooltip_text = "%s\nLv %d — %d / %d XP\n%d XP to next level\nClick for details" % [
			display, level, xp, xp_to_next, remaining
		]
	tile.pressed.connect(_show_detail.bind(skill_name))
	_apply_tile_styles(tile)

	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _get_skill_icon(skill_name)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 10
	icon.offset_top = 4
	icon.offset_right = -10
	icon.offset_bottom = -22
	tile.add_child(icon)

	if icon.texture == null:
		var fallback := Label.new()
		fallback.text = skill_name.left(1).to_upper()
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.add_theme_font_size_override(&"font_size", 20)
		fallback.add_theme_color_override(&"font_color", Color(0.82, 0.72, 0.52))
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.add_child(fallback)

	var level_label := Label.new()
	level_label.text = str(level)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.add_theme_font_size_override(&"font_size", 10)
	level_label.add_theme_color_override(&"font_color", Color(1.0, 0.88, 0.55))
	level_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	level_label.offset_left = -18
	level_label.offset_top = 2
	level_label.offset_right = -3
	level_label.offset_bottom = 14
	tile.add_child(level_label)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = xp_to_next
	bar.value = xp_to_next if at_cap else xp
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 4
	bar.offset_top = -10
	bar.offset_right = -4
	bar.offset_bottom = -3
	bar.add_theme_stylebox_override(&"background", _make_bar_bg())
	bar.add_theme_stylebox_override(&"fill", _make_bar_fill())
	tile.add_child(bar)

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
	var remaining: int = 0 if at_cap else maxi(0, xp_to_next - xp)
	title_label.text = display

	_back_button = Button.new()
	_back_button.text = "← All skills"
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.pressed.connect(_show_grid)
	_detail_root.add_child(_back_button)

	var header := Label.new()
	header.text = "Lv %d" % level
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override(&"font_size", 16)
	header.add_theme_color_override(&"font_color", Color(1.0, 0.92, 0.7))
	_detail_root.add_child(header)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = xp_to_next
	bar.value = xp_to_next if at_cap else xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.add_theme_stylebox_override(&"background", _make_bar_bg())
	bar.add_theme_stylebox_override(&"fill", _make_bar_fill())
	_detail_root.add_child(bar)

	var xp_label := Label.new()
	xp_label.text = (
		"Max level (%d)" % SkillXp.LEVEL_CAP if at_cap
		else "%d / %d XP  (%d to next)" % [xp, xp_to_next, remaining]
	)
	xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	xp_label.add_theme_font_size_override(&"font_size", 11)
	xp_label.add_theme_color_override(&"font_color", Color(0.72, 0.74, 0.8))
	_detail_root.add_child(xp_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_root.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 4)
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
	elif jp != null and not jp.recipe_items.is_empty():
		var recipes_title := Label.new()
		recipes_title.text = "Can craft"
		recipes_title.add_theme_color_override(&"font_color", Color(0.95, 0.85, 0.55))
		recipes_title.add_theme_font_size_override(&"font_size", 12)
		list.add_child(recipes_title)
		for i: int in jp.recipe_items.size():
			var item: Item = jp.recipe_items[i]
			if item == null:
				continue
			var req: int = jp.recipe_levels[i] if i < jp.recipe_levels.size() else 0
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
	if not job.source_items.is_empty() and job.source_items[0] != null:
		return job.source_items[0].item_icon
	if not job.recipe_items.is_empty() and job.recipe_items[0] != null:
		return job.recipe_items[0].item_icon
	return null


func _apply_tile_styles(tile: Button) -> void:
	tile.add_theme_stylebox_override(
		&"normal",
		_make_tile_style(Color(0.035, 0.03, 0.055, 0.82), Color(0.42, 0.28, 0.18, 0.85))
	)
	tile.add_theme_stylebox_override(
		&"hover",
		_make_tile_style(Color(0.10, 0.075, 0.08, 0.92), Color(0.86, 0.57, 0.25, 1.0))
	)
	tile.add_theme_stylebox_override(
		&"pressed",
		_make_tile_style(Color(0.16, 0.11, 0.07, 0.96), Color(1.0, 0.72, 0.30, 1.0))
	)


func _make_tile_style(background_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
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


func _place_panel() -> void:
	var hud := get_parent() as Control
	if hud == null:
		return
	size = PANEL_SIZE
	position = Vector2(
		hud.size.x - PANEL_SIZE.x - RIGHT_MARGIN,
		hud.size.y - PANEL_SIZE.y - BOTTOM_CLEARANCE
	)
