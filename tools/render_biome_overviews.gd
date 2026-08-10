extends SceneTree
## Full-map zoomed-out overviews for QA.
##   godot --path . --mode=client -s tools/render_biome_overviews.gd


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var peer := OfflineMultiplayerPeer.new()
	root.multiplayer.multiplayer_peer = peer
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/screenshots")
	for entry in [
		["forge-full", "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn", Vector2(1024, 768), 0.35],
		["sewers-full", "res://source/common/gameplay/maps/maps/sewers/sewers.tscn", Vector2(1024, 768), 0.35],
		["desert-full", "res://source/common/gameplay/maps/maps/desert/desert.tscn", Vector2(576, 432), 0.55],
		["mining-full", "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn", Vector2(832, 576), 0.45],
	]:
		await _shot(entry[0], entry[1], entry[2], entry[3])
	print("BIOME_OVERVIEW_PASS")
	quit(0)


func _shot(name: String, path: String, cam_pos: Vector2, zoom: float) -> void:
	var packed: PackedScene = load(path)
	var sv := SubViewport.new()
	sv.size = Vector2i(1280, 960)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.world_2d = World2D.new()
	root.add_child(sv)
	var map: Node2D = packed.instantiate() as Node2D
	sv.add_child(map)
	var cam := Camera2D.new()
	cam.position = cam_pos
	cam.zoom = Vector2(zoom, zoom)
	cam.make_current()
	map.add_child(cam)
	for _i: int in 12:
		await process_frame
	var image: Image = sv.get_texture().get_image()
	var out := "/opt/cursor/artifacts/screenshots/biome-%s-overview.png" % name
	image.save_png(out)
	print("SAVED ", out)
	sv.queue_free()
	await process_frame
