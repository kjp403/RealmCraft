extends VBoxContainer
## Character-menu skills grid — the 7 live skills in OSRS-style cells.
## Displays existing server-provided jobs without changing XP or progression.

const _SkillsHostScript = preload(
	"res://source/client/ui/compact_menus/compact_skills_host.gd"
)
const TILE_SIZE := Vector2(120.0, 40.0)

@onready var skill_list: VBoxContainer = %SkillList

var _skills: Dictionary = {}


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	ClientState.gather_succeeded.connect(_on_gather_succeeded)
	Client.subscribe(&"skills.get", _on_skills_received)
	_refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()


func _on_gather_succeeded(_result: Dictionary) -> void:
	_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return

	Client.request_data(
		&"skills.get",
		_on_skills_received,
		{},
		InstanceClient.current.name
	)


func _on_skills_received(data: Dictionary) -> void:
	_skills = data.get("skills", {})
	_build_skills_grid()


func _build_skills_grid() -> void:
	for child in skill_list.get_children():
		child.queue_free()

	var outer_row := HBoxContainer.new()
	outer_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_list.add_child(outer_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_row.add_child(spacer)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(280, 280)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override(&"panel", _make_panel_style())
	outer_row.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 10)
	margin.add_theme_constant_override(&"margin_top", 10)
	margin.add_theme_constant_override(&"margin_right", 10)
	margin.add_theme_constant_override(&"margin_bottom", 10)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	margin.add_child(content)

	var total_level := 0
	for skill_name in _skills:
		var info: Dictionary = _skills[skill_name]
		total_level += int(info.get("level", 1))

	var title := Label.new()
	title.text = "Skills"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 16)
	title.add_theme_color_override(&"font_color", Color(0.98, 0.92, 0.35))
	content.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 4)
	content.add_child(grid)

	for slug: String in _SkillsHostScript.SKILL_ORDER:
		if _skills.has(slug):
			grid.add_child(_create_skill_tile(slug, _skills[slug]))
		else:
			grid.add_child(
				_create_skill_tile(
					slug,
					{
						"display_name": JobRegistry.display_name(StringName(slug)),
						"level": 1,
						"xp": 0,
						"xp_to_next": 1,
					}
				)
			)

	var total_panel := PanelContainer.new()
	total_panel.add_theme_stylebox_override(&"panel", _make_total_bar_style())
	var total_label := Label.new()
	total_label.text = "Total level: %d" % total_level
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label.add_theme_font_size_override(&"font_size", 13)
	total_label.add_theme_color_override(&"font_color", Color(1.0, 1.0, 0.0))
	total_panel.add_child(total_label)
	content.add_child(total_panel)


func _create_skill_tile(skill_name: String, info: Dictionary) -> Control:
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
	tile.focus_mode = Control.FOCUS_NONE
	tile.clip_contents = true
	tile.flat = true
	if at_cap:
		tile.tooltip_text = "%s\nLv %d — Max level\nTotal XP: %s\nClick for sources" % [
			display, level, _format_xp(total_xp)
		]
	else:
		tile.tooltip_text = "%s\nLv %d — %s / %s XP\n%s XP to next\nTotal XP: %s\nClick for sources" % [
			display, level, _format_xp(xp), _format_xp(xp_to_next), _format_xp(remaining), _format_xp(total_xp)
		]
	tile.pressed.connect(_open_skill_detail.bind(skill_name, info))
	tile.add_theme_stylebox_override(&"normal", _make_tile_style())
	tile.add_theme_stylebox_override(&"hover", _make_tile_style())
	tile.add_theme_stylebox_override(&"pressed", _make_tile_style())

	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.texture = _get_skill_icon(skill_name)
	icon.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	icon.offset_left = 4
	icon.offset_top = 4
	icon.offset_right = 36
	icon.offset_bottom = -4
	tile.add_child(icon)

	_add_level_labels(tile, level, Color(1.0, 1.0, 0.0))
	return tile


func _add_level_labels(parent: Control, level: int, color: Color) -> void:
	var cur := Label.new()
	cur.text = str(level)
	cur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cur.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cur.add_theme_font_size_override(&"font_size", 12)
	cur.add_theme_color_override(&"font_color", color)
	cur.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 1))
	cur.add_theme_constant_override(&"shadow_offset_x", 1)
	cur.add_theme_constant_override(&"shadow_offset_y", 1)
	cur.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cur.offset_left = -40
	cur.offset_top = 2
	cur.offset_right = -10
	cur.offset_bottom = 18
	parent.add_child(cur)

	var base := Label.new()
	base.text = str(level)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	base.add_theme_font_size_override(&"font_size", 12)
	base.add_theme_color_override(&"font_color", color)
	base.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 1))
	base.add_theme_constant_override(&"shadow_offset_x", 1)
	base.add_theme_constant_override(&"shadow_offset_y", 1)
	base.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	base.offset_left = -32
	base.offset_top = -18
	base.offset_right = -4
	base.offset_bottom = -2
	parent.add_child(base)

	var slash := Label.new()
	slash.text = "/"
	slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slash.add_theme_font_size_override(&"font_size", 11)
	slash.add_theme_color_override(&"font_color", color)
	slash.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	slash.offset_left = -28
	slash.offset_top = -8
	slash.offset_right = -16
	slash.offset_bottom = 8
	parent.add_child(slash)


func _open_skill_detail(skill_name: String, info: Dictionary) -> void:
	var display: String = str(info.get("display_name", skill_name.capitalize()))
	var level: int = int(info.get("level", 1))
	var xp: int = int(info.get("xp", 0))
	var raw_next: int = int(info.get("xp_to_next", 1))
	var at_cap: bool = raw_next <= 0 or level >= SkillXp.LEVEL_CAP
	var xp_to_next: int = 1 if at_cap else maxi(1, raw_next)
	var total_xp: int = SkillXp.total_xp_for_level(level) + (0 if at_cap else xp)
	var xp_line: String = (
		"Max level (%d) · Total XP: %s" % [SkillXp.LEVEL_CAP, _format_xp(total_xp)] if at_cap
		else "%s / %s XP (%s to next) · Total XP: %s" % [
			_format_xp(xp), _format_xp(xp_to_next), _format_xp(maxi(0, xp_to_next - xp)), _format_xp(total_xp)
		]
	)
	var lines: PackedStringArray = [xp_line]
	var jp: JobPerks = JobRegistry.perks_for(StringName(skill_name))
	if jp != null and not jp.source_items.is_empty():
		lines.append("Can gather:")
		for i: int in jp.source_items.size():
			var item: Item = jp.source_items[i]
			if item == null:
				continue
			var req: int = jp.source_levels[i] if i < jp.source_levels.size() else 0
			var gate: String = "any level" if req <= 0 else ("Lv %d" % req)
			var lock: String = "" if req <= level else " (locked)"
			lines.append("• %s — %s%s" % [String(item.item_name), gate, lock])
	elif jp != null and not jp.recipe_items.is_empty():
		lines.append("Can craft:")
		for i: int in jp.recipe_items.size():
			var item: Item = jp.recipe_items[i]
			if item == null:
				continue
			var req: int = jp.recipe_levels[i] if i < jp.recipe_levels.size() else 0
			var gate: String = "any level" if req <= 0 else ("Lv %d" % req)
			lines.append("• %s — %s" % [String(item.item_name), gate])
	else:
		lines.append("No source list authored for this skill yet.")
	Toaster.toast_group("%s — Lv %d" % [display, level], lines, 4.5)


func _get_skill_icon(skill_name: String) -> Texture2D:
	var job := JobRegistry.perks_for(StringName(skill_name))
	if job == null:
		return null
	if job.icon != null:
		return job.icon
	if not job.source_items.is_empty():
		var source_item: Item = job.source_items[0]
		if source_item != null:
			return source_item.item_icon
	if not job.recipe_items.is_empty():
		var recipe_item: Item = job.recipe_items[0]
		if recipe_item != null:
			return recipe_item.item_icon
	return null


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.184, 0.173, 0.157, 0.97)
	style.border_color = Color(0.455, 0.416, 0.341)
	style.set_border_width_all(2)
	style.set_corner_radius_all(2)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 5
	return style


func _make_tile_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.15, 0.14, 0.97)
	style.border_color = Color(0.48, 0.44, 0.38, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	return style


func _make_total_bar_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.02, 0.95)
	style.border_color = Color(0.42, 0.38, 0.32, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(1)
	style.content_margin_top = 4
	style.content_margin_bottom = 4
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
