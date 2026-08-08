extends MenuShell
## Large area map (M). Wider SubViewport of the live World2D than the HUD
## minimap, plus a zone legend of discovery-enabled biomes. Click-to-move on
## the map surface matches the minimap.


const VIEW_SIZE: Vector2i = Vector2i(720, 420)
const MAP_ZOOM: float = 0.09


var _sub_viewport: SubViewport
var _map_camera: Camera2D
var _map_texture: TextureRect
var _area_label: Label
var _legend: VBoxContainer
var _player_marker: Label


func _ready() -> void:
	build_shell("World Map", null, true)
	_build_body()
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)
	hide()


func open(_arg: Variant = null) -> void:
	_refresh_legend()
	_attach_world()
	set_process(true)


func _on_visibility_changed() -> void:
	set_process(visible)
	if visible:
		_attach_world()
		_refresh_legend()


func _process(_delta: float) -> void:
	if not visible:
		return
	var player: LocalPlayer = ClientState.local_player
	if is_instance_valid(player) and _map_camera != null:
		_map_camera.global_position = player.global_position
		_update_player_marker(player)


func _build_body() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	var map_column := VBoxContainer.new()
	map_column.add_theme_constant_override(&"separation", 6)
	map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(map_column)

	_area_label = Label.new()
	_area_label.text = "Exploring…"
	_area_label.add_theme_font_size_override(&"font_size", 16)
	_area_label.add_theme_color_override(&"font_color", Color(0.95, 0.82, 0.55))
	map_column.add_child(_area_label)

	var hint := Label.new()
	hint.text = "Hold and drag is free look via the camera follow. Click the map to walk there. Press M to close."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override(&"font_size", 12)
	hint.add_theme_color_override(&"font_color", Color(0.65, 0.68, 0.75))
	map_column.add_child(hint)

	var map_frame := PanelContainer.new()
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_frame.custom_minimum_size = Vector2(VIEW_SIZE)
	map_frame.clip_contents = true
	map_frame.add_theme_stylebox_override(&"panel", _frame_style())
	map_column.add_child(map_frame)

	var map_host := Control.new()
	map_host.custom_minimum_size = Vector2(VIEW_SIZE)
	map_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_host.clip_contents = true
	map_frame.add_child(map_host)

	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "WorldMapViewport"
	_sub_viewport.size = VIEW_SIZE
	_sub_viewport.disable_3d = true
	_sub_viewport.gui_disable_input = true
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub_viewport)

	_map_camera = Camera2D.new()
	_map_camera.name = "WorldMapCamera"
	_map_camera.zoom = Vector2.ONE * MAP_ZOOM
	_map_camera.enabled = true
	_sub_viewport.add_child(_map_camera)

	_map_texture = TextureRect.new()
	_map_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_map_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_texture.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_texture.texture = _sub_viewport.get_texture()
	_map_texture.gui_input.connect(_on_map_gui_input)
	map_host.add_child(_map_texture)

	_player_marker = Label.new()
	_player_marker.text = "◆"
	_player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_marker.add_theme_font_size_override(&"font_size", 18)
	_player_marker.add_theme_color_override(&"font_color", Color(0.35, 0.95, 1.0))
	_player_marker.add_theme_color_override(&"font_outline_color", Color(0.05, 0.06, 0.1, 0.9))
	_player_marker.add_theme_constant_override(&"outline_size", 4)
	map_host.add_child(_player_marker)

	var legend_panel := PanelContainer.new()
	legend_panel.custom_minimum_size = Vector2(220, 0)
	legend_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	legend_panel.add_theme_stylebox_override(&"panel", _legend_style())
	row.add_child(legend_panel)

	var legend_margin := MarginContainer.new()
	legend_margin.add_theme_constant_override(&"margin_left", 10)
	legend_margin.add_theme_constant_override(&"margin_right", 10)
	legend_margin.add_theme_constant_override(&"margin_top", 10)
	legend_margin.add_theme_constant_override(&"margin_bottom", 10)
	legend_panel.add_child(legend_margin)

	var legend_col := VBoxContainer.new()
	legend_col.add_theme_constant_override(&"separation", 8)
	legend_margin.add_child(legend_col)

	var legend_title := Label.new()
	legend_title.text = "Known Regions"
	legend_title.add_theme_font_size_override(&"font_size", 15)
	legend_title.add_theme_color_override(&"font_color", Color(0.95, 0.82, 0.55))
	legend_col.add_child(legend_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	legend_col.add_child(scroll)

	_legend = VBoxContainer.new()
	_legend.add_theme_constant_override(&"separation", 6)
	_legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_legend)
	DragScroll.enable(scroll)


func _attach_world() -> void:
	if _sub_viewport == null or not is_inside_tree():
		return
	_sub_viewport.world_2d = get_viewport().find_world_2d()
	var map: Node = (
		InstanceClient.current.instance_map
		if InstanceClient.current != null
		else null
	)
	_area_label.text = (
		String(map.name).replace("_", " ")
		if map != null
		else "World Map"
	)


func _refresh_legend() -> void:
	if _legend == null:
		return
	for child: Node in _legend.get_children():
		child.queue_free()

	const PATH := "res://source/common/gameplay/maps/instance/instance_collection/"
	var zones: Array[InstanceResource] = []
	for file_path: String in FileUtils.get_all_file_at(PATH, "*.tres"):
		var loaded: Resource = ResourceLoader.load(file_path)
		if loaded is InstanceResource:
			var res: InstanceResource = loaded
			if res.show_discovery:
				zones.append(res)
	zones.sort_custom(func(a: InstanceResource, b: InstanceResource) -> bool:
		return a.level_min < b.level_min
	)

	if zones.is_empty():
		var empty := Label.new()
		empty.text = "No regions indexed yet."
		empty.add_theme_color_override(&"font_color", Color(0.6, 0.62, 0.7))
		_legend.add_child(empty)
		return

	for zone: InstanceResource in zones:
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override(&"separation", 1)
		var title := Label.new()
		title.text = zone.display_title()
		title.add_theme_font_size_override(&"font_size", 13)
		title.add_theme_color_override(&"font_color", Color(0.92, 0.93, 0.96))
		entry.add_child(title)
		var band := Label.new()
		var band_text: String = zone.level_band()
		band.text = band_text if not band_text.is_empty() else "Open area"
		band.add_theme_font_size_override(&"font_size", 11)
		band.add_theme_color_override(&"font_color", Color(0.7, 0.74, 0.8))
		entry.add_child(band)
		_legend.add_child(entry)


func _on_map_gui_input(event: InputEvent) -> void:
	var local_pos := Vector2.ZERO
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		local_pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		local_pos = event.position
	else:
		return
	var player: LocalPlayer = ClientState.local_player
	if not is_instance_valid(player):
		return
	# Same projection as NavigationMinimap: camera follows the player, so world
	# = player + (click - view centre) / zoom.
	var world_position: Vector2 = (
		player.global_position
		+ (local_pos - Vector2(VIEW_SIZE) * 0.5) / MAP_ZOOM
	)
	player.set_click_move_target(world_position)
	if _map_texture != null:
		_map_texture.accept_event()


func _update_player_marker(_player: LocalPlayer) -> void:
	if _player_marker == null or _map_texture == null:
		return
	# Camera follows the player — marker stays centred on the view.
	var center: Vector2 = _map_texture.size * 0.5
	_player_marker.position = center - Vector2(8, 12)


func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.95)
	style.border_color = Color(0.53, 0.37, 0.22)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style


func _legend_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.055, 0.08, 0.96)
	style.border_color = Color(0.35, 0.32, 0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style
