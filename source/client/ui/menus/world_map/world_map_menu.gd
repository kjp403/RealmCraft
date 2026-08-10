extends MenuShell
## Large area map (M). Wider SubViewport of the live World2D than the HUD
## minimap, plus a zone legend of discovery-enabled biomes. Click-to-move on
## the map surface matches the minimap.


const VIEW_SIZE: Vector2i = Vector2i(520, 300)
## Fallback zoom when a map has unbounded camera limits (follow-player).
const FALLBACK_ZOOM: float = 0.28
## Letterbox padding so map edges aren't flush with the frame.
const FIT_PADDING: float = 0.88
## Legend width — keep map+legend under 960×540 with shell margins.
const LEGEND_WIDTH: float = 168.0


var _sub_viewport: SubViewport
var _map_camera: Camera2D
var _map_texture: TextureRect
var _map_host: Control
var _area_label: Label
var _legend: VBoxContainer
var _player_marker: Label
## Live zoom used for click projection (updated when the current map changes).
var _map_zoom: float = FALLBACK_ZOOM
var _camera_center: Vector2 = Vector2.ZERO
var _resolved_map: Node = null
var _view_size: Vector2 = Vector2(VIEW_SIZE)


func _ready() -> void:
	build_shell("World Map", null, true)
	# Shell defaults assume a roomy viewport; clamp padding so title/Close/map
	# stay inside the 960×540 client window instead of cropping off-screen.
	_tighten_shell_for_viewport()
	_build_body()
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)
	hide()


func _tighten_shell_for_viewport() -> void:
	for child in get_children():
		if child is MarginContainer and child != content:
			var margin: MarginContainer = child
			margin.add_theme_constant_override(&"margin_left", 8)
			margin.add_theme_constant_override(&"margin_right", 8)
			margin.add_theme_constant_override(&"margin_top", 8)
			margin.add_theme_constant_override(&"margin_bottom", 8)
			if margin.get_child_count() > 0 and margin.get_child(0) is PanelContainer:
				var pad: Node = margin.get_child(0).get_child(0) if margin.get_child(0).get_child_count() > 0 else null
				if pad is MarginContainer:
					(pad as MarginContainer).add_theme_constant_override(&"margin_left", 10)
					(pad as MarginContainer).add_theme_constant_override(&"margin_right", 10)
					(pad as MarginContainer).add_theme_constant_override(&"margin_top", 6)
					(pad as MarginContainer).add_theme_constant_override(&"margin_bottom", 8)
			break
	if _title_label != null:
		_title_label.add_theme_font_size_override(&"font_size", 18)


func open(_arg: Variant = null) -> void:
	_refresh_legend()
	_attach_world()
	set_process(true)
	call_deferred(&"_sync_viewport_size")


func _on_visibility_changed() -> void:
	set_process(visible)
	if visible:
		_attach_world()
		_refresh_legend()
		call_deferred(&"_sync_viewport_size")


func _process(_delta: float) -> void:
	if not visible:
		return
	var player: LocalPlayer = ClientState.local_player
	if not is_instance_valid(player) or _map_camera == null:
		return
	var current_map: Node = (
		InstanceClient.current.instance_map
		if InstanceClient.current != null
		else null
	)
	if current_map != _resolved_map:
		_resolved_map = current_map
		_fit_camera_to_map(current_map)
	_sync_viewport_size()
	_map_camera.global_position = _camera_center
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
	hint.text = "Click the map to walk there. Press M to close."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override(&"font_size", 12)
	hint.add_theme_color_override(&"font_color", Color(0.65, 0.68, 0.75))
	map_column.add_child(hint)

	var map_frame := PanelContainer.new()
	map_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_frame.custom_minimum_size = Vector2(280, 180)
	map_frame.clip_contents = true
	map_frame.add_theme_stylebox_override(&"panel", _frame_style())
	map_column.add_child(map_frame)

	_map_host = Control.new()
	_map_host.custom_minimum_size = Vector2(280, 180)
	_map_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_host.clip_contents = true
	_map_host.resized.connect(_sync_viewport_size)
	map_frame.add_child(_map_host)

	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "WorldMapViewport"
	_sub_viewport.size = VIEW_SIZE
	_sub_viewport.disable_3d = true
	_sub_viewport.gui_disable_input = true
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub_viewport)

	_map_camera = Camera2D.new()
	_map_camera.name = "WorldMapCamera"
	_map_camera.zoom = Vector2.ONE * FALLBACK_ZOOM
	_map_camera.enabled = true
	_sub_viewport.add_child(_map_camera)

	_map_texture = TextureRect.new()
	_map_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Keep aspect so a taller/wider host does not stretch-crop the map.
	_map_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_texture.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_texture.texture = _sub_viewport.get_texture()
	_map_texture.gui_input.connect(_on_map_gui_input)
	_map_host.add_child(_map_texture)

	_player_marker = Label.new()
	_player_marker.text = "◆"
	_player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_marker.add_theme_font_size_override(&"font_size", 18)
	_player_marker.add_theme_color_override(&"font_color", Color(0.35, 0.95, 1.0))
	_player_marker.add_theme_color_override(&"font_outline_color", Color(0.05, 0.06, 0.1, 0.9))
	_player_marker.add_theme_constant_override(&"outline_size", 4)
	_map_host.add_child(_player_marker)

	var legend_panel := PanelContainer.new()
	legend_panel.custom_minimum_size = Vector2(LEGEND_WIDTH, 0)
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


func _sync_viewport_size() -> void:
	if _sub_viewport == null or _map_host == null:
		return
	var host_size: Vector2 = _map_host.size
	if host_size.x < 64.0 or host_size.y < 64.0:
		host_size = Vector2(VIEW_SIZE)
	var new_size := Vector2i(
		maxi(64, int(round(host_size.x))),
		maxi(64, int(round(host_size.y))),
	)
	if _sub_viewport.size != new_size:
		_sub_viewport.size = new_size
		_view_size = Vector2(new_size)
		_fit_camera_to_map(_resolved_map)


func _attach_world() -> void:
	if _sub_viewport == null or not is_inside_tree():
		return
	_sub_viewport.world_2d = get_viewport().find_world_2d()
	var map: Node = (
		InstanceClient.current.instance_map
		if InstanceClient.current != null
		else null
	)
	_resolved_map = map
	_fit_camera_to_map(map)
	_area_label.text = (
		String(map.name).replace("_", " ")
		if map != null
		else "World Map"
	)


## Fit the SubViewport camera so the current map's authored camera limits fill
## the frame without cropping. Unbounded maps fall back to follow-player zoom.
func _fit_camera_to_map(map: Node) -> void:
	var player: LocalPlayer = ClientState.local_player
	var player_pos: Vector2 = (
		player.global_position if is_instance_valid(player) else Vector2.ZERO
	)
	_map_zoom = FALLBACK_ZOOM
	_camera_center = player_pos
	var view_w: float = maxf(_view_size.x, float(VIEW_SIZE.x))
	var view_h: float = maxf(_view_size.y, float(VIEW_SIZE.y))
	if map is Map:
		var m: Map = map
		var has_bounds: bool = (
			m.camera_limit_left > -1_000_000
			and m.camera_limit_top > -1_000_000
			and m.camera_limit_right < 1_000_000
			and m.camera_limit_bottom < 1_000_000
			and m.camera_limit_right > m.camera_limit_left
			and m.camera_limit_bottom > m.camera_limit_top
		)
		if has_bounds:
			var map_w: float = float(m.camera_limit_right - m.camera_limit_left)
			var map_h: float = float(m.camera_limit_bottom - m.camera_limit_top)
			var zoom_x: float = view_w / map_w
			var zoom_y: float = view_h / map_h
			# min = whole map visible (letterboxed). No camera limits on the
			# map camera — limits were clamping the zoomed-out view and
			# cropping bottom/top content in the M map.
			_map_zoom = minf(zoom_x, zoom_y) * FIT_PADDING
			_camera_center = Vector2(
				float(m.camera_limit_left + m.camera_limit_right) * 0.5,
				float(m.camera_limit_top + m.camera_limit_bottom) * 0.5,
			)
		if _map_camera != null:
			_map_camera.limit_left = -10000000
			_map_camera.limit_top = -10000000
			_map_camera.limit_right = 10000000
			_map_camera.limit_bottom = 10000000
	if _map_camera != null:
		_map_camera.zoom = Vector2.ONE * _map_zoom
		_map_camera.global_position = _camera_center


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
		band.text = "Open area"
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
	# Project through the letterboxed texture rect into viewport pixels, then world.
	var tex_size: Vector2 = _view_size
	var draw_size: Vector2 = _map_texture.size if _map_texture != null else tex_size
	if draw_size.x <= 0.0 or draw_size.y <= 0.0:
		draw_size = tex_size
	var scale: float = minf(draw_size.x / tex_size.x, draw_size.y / tex_size.y)
	var drawn := tex_size * scale
	var origin := (draw_size - drawn) * 0.5
	var in_tex: Vector2 = (local_pos - origin) / scale
	var world_position: Vector2 = (
		_camera_center
		+ (in_tex - tex_size * 0.5) / _map_zoom
	)
	player.set_click_move_target(world_position)
	if _map_texture != null:
		_map_texture.accept_event()


func _update_player_marker(player: LocalPlayer) -> void:
	if _player_marker == null or _map_texture == null:
		return
	var tex_size: Vector2 = _view_size
	var draw_size: Vector2 = _map_texture.size if _map_texture.size.x > 0.0 else tex_size
	var scale: float = minf(draw_size.x / tex_size.x, draw_size.y / tex_size.y)
	var drawn := tex_size * scale
	var origin := (draw_size - drawn) * 0.5
	var screen_in_tex: Vector2 = (
		tex_size * 0.5
		+ (player.global_position - _camera_center) * _map_zoom
	)
	_player_marker.position = origin + screen_in_tex * scale - Vector2(8, 12)


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
