extends SceneTree
## Wave-separated and boss-kit shots of The Brimstone Vault.
##   godot --path . --mode=client -s tools/render_hell_dungeon_preview.gd

const SCENE := "res://source/common/gameplay/maps/maps/hell_dungeon/hell_dungeon.tscn"


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var out_dir := ProjectSettings.globalize_path("res://.godot/previews")
	DirAccess.make_dir_recursive_absolute(out_dir)

	await _shot(out_dir, "hell-r1-w0", Vector2(288, -464), 0.95, Vector2i(1024, 640), 0, "Room 1  ·  Wave 1  ·  3 Imps + Damned")
	await _shot(out_dir, "hell-r1-w1", Vector2(288, -464), 0.95, Vector2i(1024, 640), 1, "Room 1  ·  Wave 2  ·  2 Damned + Imp + Twisted")
	await _shot(out_dir, "hell-r1-w2", Vector2(288, -464), 0.95, Vector2i(1024, 640), 2, "Room 1  ·  Wave 3  ·  Twisted + 2 Damned + Imp")
	await _shot(out_dir, "hell-r3-w0", Vector2(336, -2224), 0.72, Vector2i(1100, 720), 0, "Room 3  ·  Wave 1  ·  2 Cinder + 3 Eyes (ring the well)")
	await _shot(out_dir, "hell-r5-w0", Vector2(336, -4144), 0.78, Vector2i(1024, 640), 0, "Room 5  ·  Wave 1  ·  2 Damned + 2 Twisted + 2 Imps")
	await _shot(out_dir, "hell-r5-w1", Vector2(336, -4144), 0.78, Vector2i(1024, 640), 1, "Room 5  ·  Wave 2  ·  2 Bloated + 2 Cinder + Eye")
	await _shot(out_dir, "hell-r5-w2", Vector2(336, -4144), 0.78, Vector2i(1024, 640), 2, "Room 5  ·  Wave 3  ·  Hell Giant + 2 Cinder + 2 Eyes + Imp")
	await _shot(out_dir, "hell-boss-w0", Vector2(1424, -4176), 0.62, Vector2i(1180, 760), 0, "Final  ·  Wave 1  ·  3 Skulls + 3 Imps + 2 Eyes + Bloated")
	await _shot(out_dir, "hell-boss-w1", Vector2(1424, -4176), 0.55, Vector2i(1180, 760), 1, "Final  ·  Wave 2  ·  Queen + 2 Eyes + 2 Skulls + 2 Imps", true)
	print("HELL_WAVE_PREVIEW_PASS ", out_dir)
	quit(0)


func _shot(
	out_dir: String,
	shot_name: String,
	cam_pos: Vector2,
	zoom: float,
	size: Vector2i,
	wave: int,
	caption: String,
	boss_kit: bool = false
) -> void:
	var packed: PackedScene = load(SCENE)
	var sv := SubViewport.new()
	sv.size = size
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.transparent_bg = false
	sv.world_2d = World2D.new()
	root.add_child(sv)
	var map: Node2D = packed.instantiate() as Node2D
	sv.add_child(map)
	var queen: Node2D = _dress_markers(map, wave)
	if boss_kit and queen != null:
		_draw_boss_kit(queen)
	var cam := Camera2D.new()
	cam.position = cam_pos
	cam.zoom = Vector2(zoom, zoom)
	map.add_child(cam)
	cam.make_current()
	var hud := CanvasLayer.new()
	sv.add_child(hud)
	var lab := Label.new()
	lab.text = caption
	lab.position = Vector2(16, 12)
	lab.add_theme_font_size_override("font_size", 22)
	lab.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
	lab.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lab.add_theme_constant_override("outline_size", 6)
	hud.add_child(lab)
	for _i in 16:
		await process_frame
	var out := "%s/%s.png" % [out_dir, shot_name]
	sv.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	sv.queue_free()
	await process_frame


func _dress_markers(map: Node, wave: int) -> Node2D:
	var queen: Node2D = null
	for node: Node in map.find_children("*", "Marker2D", true, false):
		var et: Variant = node.get("enemy_type")
		if et == null or typeof(et) != TYPE_OBJECT:
			continue
		var marker_wave: int = int(node.get("wave"))
		if marker_wave != wave:
			continue
		var skin: Variant = et.get("skin")
		if skin == null or not (skin is SpriteFrames):
			continue
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = skin as SpriteFrames
		spr.animation = &"idle"
		var sc: float = float(et.get("visual_scale"))
		if sc <= 0.0:
			sc = 1.0
		spr.scale = Vector2(sc, sc)
		spr.z_index = 8
		spr.play()
		node.add_child(spr)
		if bool(et.get("is_boss")):
			queen = node as Node2D
	return queen


func _draw_boss_kit(origin: Node2D) -> void:
	# Sear 96, slam 170, meteor spread 230 (8× r58), sweep 320 / 130°, 8 imp adds.
	_ring(origin, 96.0, Color(0.95, 0.35, 0.12, 0.55), 2.0)
	_ring(origin, 170.0, Color(1.0, 0.55, 0.15, 0.85), 3.0)
	_ring(origin, 230.0, Color(1.0, 0.75, 0.2, 0.35), 2.0)
	for i in 8:
		var ang: float = TAU * float(i) / 8.0 + 0.4
		var at := Vector2.from_angle(ang) * 150.0
		_ring_at(origin, at, 58.0, Color(1.0, 0.45, 0.1, 0.7), 2.0)
	_arc(origin, 320.0, 130.0, -0.4, Color(0.55, 0.85, 1.0, 0.7))
	for i in 8:
		var ang2: float = TAU * float(i) / 8.0
		var add := Vector2.from_angle(ang2) * 72.0
		var mark := ColorRect.new()
		mark.size = Vector2(6, 6)
		mark.position = add - Vector2(3, 3)
		mark.color = Color(0.95, 0.2, 0.15, 0.9)
		mark.z_index = 12
		origin.add_child(mark)


func _ring(parent: Node2D, radius: float, color: Color, width: float) -> void:
	_ring_at(parent, Vector2.ZERO, radius, color, width)


func _ring_at(parent: Node2D, offset: Vector2, radius: float, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.z_index = 10
	line.closed = true
	for i in 48:
		var a: float = TAU * float(i) / 48.0
		line.add_point(offset + Vector2.from_angle(a) * radius)
	parent.add_child(line)


func _arc(parent: Node2D, radius: float, arc_deg: float, facing: float, color: Color) -> void:
	var line := Line2D.new()
	line.width = 3.0
	line.default_color = color
	line.z_index = 11
	var half: float = deg_to_rad(arc_deg) * 0.5
	line.add_point(Vector2.ZERO)
	for i in 24:
		var a: float = facing - half + (half * 2.0) * float(i) / 23.0
		line.add_point(Vector2.from_angle(a) * radius)
	line.add_point(Vector2.ZERO)
	parent.add_child(line)
