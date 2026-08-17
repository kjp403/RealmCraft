class_name NavigationMinimap
extends PanelContainer
## Compact top-right minimap. It renders the live World2D through a dedicated
## SubViewport, follows the local player, shows the tracked VISIT target, and
## converts minimap clicks back into world coordinates for click-to-move.

const PANEL_SIZE: Vector2 = Vector2(150.0, 112.0)
const VIEW_SIZE: Vector2i = Vector2i(140, 82)
const MAP_ZOOM: float = 0.12
const EDGE_PADDING: float = 9.0
const VISIT_PREFIX: String = "Speak with "
const TARGET_FIX_VERSION: String = "2026-08-07-c"
const PLAYER_DIAMOND_COLOR := Color(0.35, 0.55, 1.0)
const FRIEND_DIAMOND_COLOR := Color(0.28, 0.92, 0.42)
const SELF_DIAMOND_COLOR := Color(0.35, 0.95, 1.0)

var _sub_viewport: SubViewport
var _map_camera: Camera2D
var _map_texture: TextureRect
var _area_label: Label
var _target_label: Label
var _player_marker: Label
var _other_player_markers: Array[Label] = []
var _map_frame: Control
var _target_marker: Label
var _click_marker: Label

var _quest_target_key: StringName = &""
var _quest_target_name: String = ""
var _quest_target: Node2D
var _resolved_map: Node
var _refresh_retry: float = 0.0


func _ready() -> void:
	name = "NavigationMinimap"
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -158.0
	offset_top = 8.0
	offset_right = -8.0
	offset_bottom = 120.0
	custom_minimum_size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	clip_contents = true
	add_theme_stylebox_override(&"panel", _make_panel_style())

	_build_interface()
	_connect_updates()
	call_deferred(&"_attach_world")
	_refresh_quest()


func _process(delta: float) -> void:
	var should_be_visible: bool = not ClientState.menu_open
	if visible != should_be_visible:
		visible = should_be_visible
	if not should_be_visible:
		return

	var player: LocalPlayer = ClientState.local_player
	if not is_instance_valid(player):
		return
	if _map_camera != null:
		_map_camera.global_position = player.global_position

	var current_map: Node = (
		InstanceClient.current.instance_map
		if InstanceClient.current != null
		else null
	)
	if current_map != _resolved_map:
		_resolved_map = current_map
		_attach_world()
		# Re-read the objectives on every map change. An ANY quest can contain
		# several NPC targets; the correct marker is the unfinished target that
		# actually exists in the destination map.
		_refresh_quest()

	if not is_instance_valid(_quest_target):
		_refresh_retry -= delta
		if _refresh_retry <= 0.0:
			_refresh_retry = 0.5
			_resolve_quest_target()

	_update_markers(player)


func _build_interface() -> void:
	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override(&"margin_left", 5)
	outer_margin.add_theme_constant_override(&"margin_right", 5)
	outer_margin.add_theme_constant_override(&"margin_top", 4)
	outer_margin.add_theme_constant_override(&"margin_bottom", 5)
	add_child(outer_margin)

	var main_column := VBoxContainer.new()
	main_column.add_theme_constant_override(&"separation", 3)
	outer_margin.add_child(main_column)

	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0.0, 20.0)
	main_column.add_child(header)

	_area_label = Label.new()
	_area_label.text = "Map"
	_area_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_area_label.add_theme_font_size_override(&"font_size", 12)
	_area_label.add_theme_color_override(
		&"font_color",
		Color(0.95, 0.82, 0.55)
	)
	header.add_child(_area_label)

	_target_label = Label.new()
	_target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_target_label.add_theme_font_size_override(&"font_size", 11)
	_target_label.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.72, 0.26)
	)
	header.add_child(_target_label)

	_map_frame = Control.new()
	_map_frame.custom_minimum_size = Vector2(VIEW_SIZE)
	_map_frame.clip_contents = true
	_map_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	main_column.add_child(_map_frame)
	var map_frame: Control = _map_frame

	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "MapViewport"
	_sub_viewport.size = VIEW_SIZE
	_sub_viewport.disable_3d = true
	_sub_viewport.gui_disable_input = true
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sub_viewport)

	_map_camera = Camera2D.new()
	_map_camera.name = "MapCamera"
	_map_camera.zoom = Vector2.ONE * MAP_ZOOM
	_map_camera.enabled = true
	_map_camera.position_smoothing_enabled = false
	_sub_viewport.add_child(_map_camera)

	_map_texture = TextureRect.new()
	_map_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_texture.stretch_mode = TextureRect.STRETCH_SCALE
	_map_texture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_texture.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_texture.texture = _sub_viewport.get_texture()
	_map_texture.gui_input.connect(_on_map_gui_input)
	map_frame.add_child(_map_texture)

	_player_marker = _make_marker(UiGlyphs.diamond(), SELF_DIAMOND_COLOR)
	_player_marker.tooltip_text = "You"
	map_frame.add_child(_player_marker)

	_target_marker = _make_marker("!", Color(1.0, 0.68, 0.18))
	_target_marker.add_theme_font_size_override(&"font_size", 17)
	_target_marker.hide()
	map_frame.add_child(_target_marker)

	_click_marker = _make_marker("×", Color(0.65, 1.0, 0.72))
	_click_marker.hide()
	map_frame.add_child(_click_marker)


func _connect_updates() -> void:
	ClientState.tracked_quest_changed.connect(
		func(_quest_id: int): _refresh_quest()
	)
	Client.subscribe(
		&"quest.update",
		func(_data: Dictionary): _refresh_quest()
	)
	ClientState.local_player_ready.connect(
		func(_player: LocalPlayer):
			_attach_world()
			_refresh_quest()
	)
	Client.instance_manager.instance_changed.connect(
		func(_instance: InstanceClient):
			call_deferred(&"_attach_world")
			call_deferred(&"_resolve_quest_target")
	)


func _attach_world() -> void:
	if _sub_viewport == null or not is_inside_tree():
		return
	_sub_viewport.world_2d = get_viewport().find_world_2d()
	_resolved_map = (
		InstanceClient.current.instance_map
		if InstanceClient.current != null
		else null
	)
	_area_label.text = (
		String(_resolved_map.name).replace("_", " ")
		if _resolved_map != null
		else "Map"
	)


func _refresh_quest() -> void:
	if InstanceClient.current == null:
		_clear_quest_target()
		return
	Client.request_data(
		&"quest.list",
		_on_quest_list_received,
		{},
		InstanceClient.current.name
	)


func _on_quest_list_received(data: Dictionary) -> void:
	if ClientState.tracked_quest_id == -1:
		_clear_quest_target()
		return

	var tracked: Dictionary = {}
	var first_active: Dictionary = {}
	for quest: Dictionary in data.get("quests", []):
		if str(quest.get("state", "")) != "active":
			continue
		if first_active.is_empty():
			first_active = quest
		if int(quest.get("id", 0)) == ClientState.tracked_quest_id:
			tracked = quest

	if tracked.is_empty():
		tracked = first_active
	if tracked.is_empty() or bool(tracked.get("complete", false)):
		_clear_quest_target()
		return

	_clear_quest_target()
	var first_target_key: StringName = &""
	var first_target_name: String = ""
	var current_map: Node = (
		InstanceClient.current.instance_map
		if InstanceClient.current != null
		else null
	)

	for objective: Dictionary in tracked.get("objectives", []):
		var count: int = int(objective.get("count", 0))
		var required: int = int(objective.get("required", 1))
		if count >= required:
			continue

		var target_key := StringName(
			str(objective.get("target_giver", ""))
		)
		var target_name: String = str(
			objective.get("target_name", "")
		).strip_edges()
		if target_name.is_empty():
			var description: String = str(
				objective.get("desc", "")
			).strip_edges()
			if description.begins_with(VISIT_PREFIX):
				target_name = description.substr(
					VISIT_PREFIX.length()
				).strip_edges()
				var loc_sep: int = target_name.find(" · ")
				if loc_sep >= 0:
					target_name = target_name.substr(0, loc_sep).strip_edges()

		if target_key.is_empty() and target_name.is_empty():
			continue

		if first_target_key.is_empty() and first_target_name.is_empty():
			first_target_key = target_key
			first_target_name = target_name

		# Prefer an unfinished objective whose NPC is physically present in the
		# current map. This prevents an absent first alternative from hiding a
		# valid Foreman marker later in the same ANY-objective quest.
		_quest_target_key = target_key
		_quest_target_name = target_name
		if current_map != null:
			var present_target: Node2D = _find_target(current_map)
			if present_target != null:
				_quest_target = present_target
				return

	# Keep the first unfinished target as a cross-map direction fallback. When
	# the player enters its map, the refresh above resolves the live NPC.
	_quest_target_key = first_target_key
	_quest_target_name = first_target_name
	_resolve_quest_target()


func _resolve_quest_target() -> void:
	_quest_target = null
	_refresh_retry = 0.5
	if _quest_target_key.is_empty() and _quest_target_name.is_empty():
		return
	if InstanceClient.current == null:
		return
	var map: Node = InstanceClient.current.instance_map
	if map == null:
		return
	_quest_target = _find_target(map)


func _find_target(root: Node) -> Node2D:
	if root is NPC:
		var npc := root as NPC
		var key_matches: bool = (
			not _quest_target_key.is_empty()
			and npc.giver_key() == _quest_target_key
		)
		var expected_name: String = _normalize_name(_quest_target_name)
		var node_matches: bool = (
			not expected_name.is_empty()
			and _normalize_name(String(npc.name)) == expected_name
		)
		var resource_matches: bool = false
		var resource: NPCResource = npc.npc_resource
		if resource != null and not expected_name.is_empty():
			resource_matches = (
				_normalize_name(resource.npc_name)
				== expected_name
			)
		if key_matches or node_matches or resource_matches:
			return npc

	for child: Node in root.get_children():
		var found: Node2D = _find_target(child)
		if found != null:
			return found
	return null


func _normalize_name(raw_name: String) -> String:
	var normalized: String = raw_name.strip_edges().to_lower()
	if normalized.begins_with("the "):
		normalized = normalized.substr(4).strip_edges()
	return normalized


func _clear_quest_target() -> void:
	_quest_target_key = &""
	_quest_target_name = ""
	_quest_target = null
	_target_label.text = ""
	if _target_marker != null:
		_target_marker.hide()


func _update_markers(player: LocalPlayer) -> void:
	var center: Vector2 = Vector2(VIEW_SIZE) * 0.5
	_set_marker_center(_player_marker, center)
	_update_other_player_markers(player, center)

	if not is_instance_valid(_quest_target):
		_target_marker.hide()
		_target_label.text = ""
		return

	var relative: Vector2 = (
		_quest_target.global_position - player.global_position
	) * MAP_ZOOM
	var raw_position: Vector2 = center + relative
	var safe_rect := Rect2(
		Vector2.ONE * EDGE_PADDING,
		Vector2(VIEW_SIZE) - Vector2.ONE * EDGE_PADDING * 2.0
	)
	var inside: bool = safe_rect.has_point(raw_position)
	var marker_position: Vector2 = Vector2(
		clampf(raw_position.x, safe_rect.position.x, safe_rect.end.x),
		clampf(raw_position.y, safe_rect.position.y, safe_rect.end.y)
	)
	_target_marker.text = "!" if inside else _direction_arrow(relative)
	_target_marker.tooltip_text = _quest_target_name
	_set_marker_center(_target_marker, marker_position)
	_target_marker.show()
	_target_label.text = "%s  %s" % [
		_direction_arrow(relative),
		_quest_target_name,
	]


func _update_other_player_markers(player: LocalPlayer, center: Vector2) -> void:
	var others: Array[Player] = []
	if InstanceClient.current != null:
		for peer_id: int in InstanceClient.current.players_by_peer_id:
			var other: Player = InstanceClient.current.players_by_peer_id[peer_id]
			if other == null or other == player or not is_instance_valid(other):
				continue
			others.append(other)

	while _other_player_markers.size() < others.size():
		var marker: Label = _make_marker(UiGlyphs.diamond(), PLAYER_DIAMOND_COLOR)
		if _map_frame != null:
			_map_frame.add_child(marker)
		_other_player_markers.append(marker)

	var safe_rect := Rect2(
		Vector2.ONE * EDGE_PADDING,
		Vector2(VIEW_SIZE) - Vector2.ONE * EDGE_PADDING * 2.0
	)
	for i: int in _other_player_markers.size():
		var marker: Label = _other_player_markers[i]
		if i >= others.size():
			marker.hide()
			continue
		var other: Player = others[i]
		var is_friend: bool = (
			other.player_id > 0
			and Character.local_friend_ids.has(other.player_id)
		)
		marker.add_theme_color_override(
			&"font_color",
			FRIEND_DIAMOND_COLOR if is_friend else PLAYER_DIAMOND_COLOR
		)
		marker.tooltip_text = (
			"%s (friend)" % other.display_name if is_friend else other.display_name
		)
		var relative: Vector2 = (
			other.global_position - player.global_position
		) * MAP_ZOOM
		var raw_position: Vector2 = center + relative
		var marker_position: Vector2 = Vector2(
			clampf(raw_position.x, safe_rect.position.x, safe_rect.end.x),
			clampf(raw_position.y, safe_rect.position.y, safe_rect.end.y)
		)
		_set_marker_center(marker, marker_position)
		marker.show()

	if _player_marker != null:
		_player_marker.move_to_front()
	if _target_marker != null:
		_target_marker.move_to_front()
	if _click_marker != null:
		_click_marker.move_to_front()


func _on_map_gui_input(event: InputEvent) -> void:
	if event is not InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if (
		mouse_event.button_index != MOUSE_BUTTON_LEFT
		or not mouse_event.pressed
	):
		return

	var player: LocalPlayer = ClientState.local_player
	if not is_instance_valid(player):
		return
	var local_position: Vector2 = mouse_event.position
	var world_position: Vector2 = (
		player.global_position
		+ (
			local_position - Vector2(VIEW_SIZE) * 0.5
		) / MAP_ZOOM
	)
	if player.has_method(&"set_click_move_target"):
		player.call(&"set_click_move_target", world_position)
		_show_click_marker(local_position)
	accept_event()


func _show_click_marker(local_position: Vector2) -> void:
	_set_marker_center(_click_marker, local_position)
	_click_marker.modulate.a = 1.0
	_click_marker.show()
	var tween := create_tween()
	tween.tween_property(_click_marker, ^"modulate:a", 0.0, 0.55)
	tween.tween_callback(_click_marker.hide)


func _make_marker(text_value: String, color: Color) -> Label:
	var marker := Label.new()
	marker.text = text_value
	marker.custom_minimum_size = Vector2(18.0, 18.0)
	marker.size = Vector2(18.0, 18.0)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker.add_theme_font_size_override(&"font_size", 13)
	marker.add_theme_color_override(&"font_color", color)
	marker.add_theme_color_override(
		&"font_outline_color",
		Color(0.0, 0.0, 0.0, 0.95)
	)
	marker.add_theme_constant_override(&"outline_size", 4)
	return marker


func _set_marker_center(marker: Control, center: Vector2) -> void:
	marker.position = (center - marker.size * 0.5).round()


func _direction_arrow(direction: Vector2) -> String:
	return UiGlyphs.compass(direction)


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.055, 0.94)
	style.border_color = Color(0.62, 0.44, 0.24, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 5
	return style
