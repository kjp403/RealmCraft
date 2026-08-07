extends PanelContainer

const PANEL_SIZE := Vector2(180.0, 262.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 52.0
const GRID_COLUMNS := 3
const TILE_SIZE := Vector2(48.0, 48.0)

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

	close_button.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)
	ClientState.gather_succeeded.connect(_on_gather_succeeded)

	var hud := get_parent() as Control
	if hud != null:
		hud.resized.connect(_place_panel)

	call_deferred(&"_place_panel")
	hide()


func _build_layout() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)

	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_center)

	_skills_grid = GridContainer.new()
	_skills_grid.columns = GRID_COLUMNS
	_skills_grid.add_theme_constant_override(&"h_separation", 5)
	_skills_grid.add_theme_constant_override(&"v_separation", 5)
	grid_center.add_child(_skills_grid)


func _on_visibility_changed() -> void:
	if visible:
		_refresh()


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
		var info: Dictionary = _skills[skill_name]
		total_level += int(info.get("level", 1))

	title_label.text = "Skills · %d" % total_level
	_build_skills_grid()


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
			_create_skill_tile(
				String(entry["slug"]),
				entry["info"]
			)
		)


func _sort_skills(a: Dictionary, b: Dictionary) -> bool:
	var a_info: Dictionary = a["info"]
	var b_info: Dictionary = b["info"]

	var a_category: String = str(
		a_info.get("category", "")
	)
	var b_category: String = str(
		b_info.get("category", "")
	)

	var a_category_order: int = (
		0 if a_category == "gathering" else 1
	)
	var b_category_order: int = (
		0 if b_category == "gathering" else 1
	)

	if a_category_order != b_category_order:
		return a_category_order < b_category_order

	return int(a_info.get("order", 0)) < int(
		b_info.get("order", 0)
	)


func _create_skill_tile(
	skill_name: String,
	info: Dictionary
) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = TILE_SIZE
	tile.size = TILE_SIZE
	tile.clip_contents = true
	tile.focus_mode = Control.FOCUS_NONE
	tile.tooltip_text = "%s\nLevel %d" % [
		str(info.get(
			"display_name",
			skill_name.capitalize()
		)),
		int(info.get("level", 1)),
	]

	_apply_tile_styles(tile)

	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _get_skill_icon(skill_name)
	icon.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	icon.offset_left = 8
	icon.offset_top = 4
	icon.offset_right = -8
	icon.offset_bottom = -13
	tile.add_child(icon)

	if icon.texture == null:
		var fallback := Label.new()
		fallback.text = skill_name.left(1).to_upper()
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.add_theme_font_size_override(&"font_size", 20)
		fallback.add_theme_color_override(
			&"font_color",
			Color(0.82, 0.72, 0.52)
		)
		fallback.set_anchors_and_offsets_preset(
			Control.PRESET_FULL_RECT
		)
		icon.add_child(fallback)

	var short_name := Label.new()
	short_name.text = skill_name.left(3).to_upper()
	short_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	short_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	short_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	short_name.add_theme_font_size_override(&"font_size", 7)
	short_name.add_theme_color_override(
		&"font_color",
		Color(0.68, 0.64, 0.58)
	)
	short_name.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	short_name.offset_left = 3
	short_name.offset_top = -13
	short_name.offset_right = -3
	short_name.offset_bottom = 0
	tile.add_child(short_name)

	var level := Label.new()
	level.text = str(int(info.get("level", 1)))
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level.add_theme_font_size_override(&"font_size", 10)
	level.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.88, 0.55)
	)
	level.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	level.offset_left = 3
	level.offset_top = -14
	level.offset_right = -3
	level.offset_bottom = 0
	tile.add_child(level)

	return tile


func _get_skill_icon(skill_name: String) -> Texture2D:
	var job := JobRegistry.perks_for(
		StringName(skill_name)
	)

	if job == null:
		return null

	if not job.source_items.is_empty():
		var source_item: Item = job.source_items[0]
		if source_item != null:
			return source_item.item_icon

	if not job.recipe_items.is_empty():
		var recipe_item: Item = job.recipe_items[0]
		if recipe_item != null:
			return recipe_item.item_icon

	return null


func _apply_tile_styles(tile: Button) -> void:
	tile.add_theme_stylebox_override(
		&"normal",
		_make_tile_style(
			Color(0.035, 0.03, 0.055, 0.82),
			Color(0.42, 0.28, 0.18, 0.85)
		)
	)
	tile.add_theme_stylebox_override(
		&"hover",
		_make_tile_style(
			Color(0.10, 0.075, 0.08, 0.92),
			Color(0.86, 0.57, 0.25, 1.0)
		)
	)
	tile.add_theme_stylebox_override(
		&"pressed",
		_make_tile_style(
			Color(0.16, 0.11, 0.07, 0.96),
			Color(1.0, 0.72, 0.30, 1.0)
		)
	)


func _make_tile_style(
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

	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

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
