extends VBoxContainer
## Compact skills grid.
## Displays existing server-provided jobs without changing XP or progression.

@onready var skill_list: VBoxContainer = %SkillList

var _skills: Dictionary = {}


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	ClientState.gather_succeeded.connect(_on_gather_succeeded)
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

	# This spacer pushes the compact panel toward the right side.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_row.add_child(spacer)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 410)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override(&"panel", _make_panel_style())
	outer_row.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", 14)
	margin.add_theme_constant_override(&"margin_top", 12)
	margin.add_theme_constant_override(&"margin_right", 14)
	margin.add_theme_constant_override(&"margin_bottom", 14)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 10)
	margin.add_child(content)

	var total_level := 0
	for skill_name in _skills:
		var info: Dictionary = _skills[skill_name]
		total_level += int(info.get("level", 1))

	var title := Label.new()
	title.text = "Skills — Total Lv %d" % total_level
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 18)
	title.add_theme_color_override(
		&"font_color",
		Color(0.96, 0.82, 0.55)
	)
	content.add_child(title)

	content.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override(&"h_separation", 7)
	grid.add_theme_constant_override(&"v_separation", 7)
	content.add_child(grid)

	var entries: Array = []

	for skill_name in _skills:
		entries.append({
			"slug": String(skill_name),
			"info": _skills[skill_name]
		})

	entries.sort_custom(_sort_skills)

	for entry in entries:
		grid.add_child(
			_create_skill_tile(
				entry["slug"],
				entry["info"]
			)
		)

	# Add locked-looking empty spaces until the grid contains 16 tiles.
	while grid.get_child_count() < 16:
		grid.add_child(_create_locked_tile())


func _sort_skills(a: Dictionary, b: Dictionary) -> bool:
	var a_info: Dictionary = a["info"]
	var b_info: Dictionary = b["info"]

	var a_category := String(a_info.get("category", ""))
	var b_category := String(b_info.get("category", ""))

	var a_category_order := 0 if a_category == "gathering" else 1
	var b_category_order := 0 if b_category == "gathering" else 1

	if a_category_order != b_category_order:
		return a_category_order < b_category_order

	return int(a_info.get("order", 0)) < int(
		b_info.get("order", 0)
	)


func _create_skill_tile(
	skill_name: String,
	info: Dictionary
) -> Control:
	var level: int = int(info.get("level", 1))
	var xp: int = int(info.get("xp", 0))
	var xp_to_next: int = maxi(1, int(info.get("xp_to_next", 1)))
	var display: String = str(
		info.get("display_name", skill_name.capitalize())
	)
	var remaining: int = maxi(0, xp_to_next - xp)

	var tile := Button.new()
	tile.custom_minimum_size = Vector2(76, 88)
	tile.focus_mode = Control.FOCUS_NONE
	tile.clip_contents = true
	tile.tooltip_text = "%s\nLv %d — %d / %d XP\n%d XP to next\nClick for sources" % [
		display, level, xp, xp_to_next, remaining
	]
	tile.pressed.connect(_open_skill_detail.bind(skill_name, info))
	tile.add_theme_stylebox_override(&"normal", _make_tile_style())
	tile.add_theme_stylebox_override(&"hover", _make_tile_style())
	tile.add_theme_stylebox_override(&"pressed", _make_tile_style())

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override(&"separation", 1)
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 4
	stack.offset_top = 4
	stack.offset_right = -4
	stack.offset_bottom = -4
	tile.add_child(stack)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = _get_skill_icon(skill_name)
	stack.add_child(icon)

	if icon.texture == null:
		var fallback := Label.new()
		fallback.text = skill_name.left(1).to_upper()
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fallback.add_theme_font_size_override(&"font_size", 22)
		fallback.add_theme_color_override(
			&"font_color",
			Color(0.82, 0.72, 0.52)
		)
		icon.add_child(fallback)
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var level_row := HBoxContainer.new()
	level_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(level_row)

	var level_label := Label.new()
	level_label.text = "Lv %d" % level
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_label.add_theme_font_size_override(&"font_size", 11)
	level_label.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.88, 0.55)
	)
	level_row.add_child(level_label)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = xp_to_next
	bar.value = xp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(bar)

	return tile


func _open_skill_detail(skill_name: String, info: Dictionary) -> void:
	var display: String = str(info.get("display_name", skill_name.capitalize()))
	var level: int = int(info.get("level", 1))
	var xp: int = int(info.get("xp", 0))
	var xp_to_next: int = maxi(1, int(info.get("xp_to_next", 1)))
	var lines: PackedStringArray = [
		"%s — Lv %d" % [display, level],
		"%d / %d XP (%d to next level)" % [xp, xp_to_next, maxi(0, xp_to_next - xp)],
		"",
	]
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
	Toaster.toast("\n".join(lines), 4.0)


func _create_locked_tile() -> Control:
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(76, 76)
	tile.modulate = Color(1.0, 1.0, 1.0, 0.48)
	tile.add_theme_stylebox_override(
		&"panel",
		_make_tile_style()
	)

	var lock := Label.new()
	lock.text = "LOCK"
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock.add_theme_font_size_override(&"font_size", 11)
	lock.add_theme_color_override(
		&"font_color",
		Color(0.55, 0.52, 0.46)
	)
	tile.add_child(lock)

	return tile


func _get_skill_icon(skill_name: String) -> Texture2D:
	var job := JobRegistry.perks_for(StringName(skill_name))

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


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.055, 0.075, 0.97)
	style.border_color = Color(0.50, 0.38, 0.23)
	style.set_border_width_all(3)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 5
	return style


func _make_tile_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.045, 0.065, 1.0)
	style.border_color = Color(0.17, 0.16, 0.19)
	style.set_border_width_all(2)
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	return style
