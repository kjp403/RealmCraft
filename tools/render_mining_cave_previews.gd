extends SceneTree
## Preview renders for Mining Cave + Woodland entrance (before PR).
## Run: godot --headless --path . -s tools/render_mining_cave_previews.gd


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var peer := OfflineMultiplayerPeer.new()
	root.multiplayer.multiplayer_peer = peer
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/screenshots")

	await _shot(
		"res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn",
		Vector2(560, 336),
		Vector2i(1100, 640),
		"/opt/cursor/artifacts/screenshots/mining-cave-overview.png",
		1.0
	)
	await _shot(
		"res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn",
		Vector2(160, 336),
		Vector2i(720, 480),
		"/opt/cursor/artifacts/screenshots/mining-cave-entrance-chamber.png",
		1.0
	)
	await _shot(
		"res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn",
		Vector2(480, 176),
		Vector2i(720, 480),
		"/opt/cursor/artifacts/screenshots/mining-cave-copper-spur.png",
		1.0
	)
	await _shot(
		"res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn",
		Vector2(976, 320),
		Vector2i(720, 480),
		"/opt/cursor/artifacts/screenshots/mining-cave-coal-chamber.png",
		1.0
	)
	await _shot(
		"res://source/common/gameplay/maps/maps/fungus_cave/fungus_cave.tscn",
		Vector2(0, -400),
		Vector2i(960, 640),
		"/opt/cursor/artifacts/screenshots/fungus-cave-compare.png",
		1.0
	)
	await _shot(
		"res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn",
		Vector2(1640, 680),
		Vector2i(960, 640),
		"/opt/cursor/artifacts/screenshots/woodland-mining-entrance.png",
		1.0
	)

	print("PREVIEWS_OK")
	quit(0)


func _shot(scene_path: String, cam_pos: Vector2, size: Vector2i, out_path: String, zoom: float) -> void:
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("failed to load " + scene_path)
		return
	var sv := SubViewport.new()
	sv.size = size
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.transparent_bg = false
	sv.world_2d = World2D.new()
	root.add_child(sv)

	var map: Node2D = packed.instantiate() as Node2D
	sv.add_child(map)

	var cam := Camera2D.new()
	cam.position = cam_pos
	cam.zoom = Vector2(zoom, zoom)
	cam.make_current()
	map.add_child(cam)

	for _i: int in 16:
		await process_frame

	var image: Image = sv.get_texture().get_image()
	image.save_png(out_path)
	print("SAVED ", out_path, " size=", image.get_size())
	sv.queue_free()
	await process_frame
