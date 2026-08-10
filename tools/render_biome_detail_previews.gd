extends SceneTree
## Detail crops for Forge / Sewers / Desert landmarks.
##   godot --path . --mode=client -s tools/render_biome_detail_previews.gd


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var peer := OfflineMultiplayerPeer.new()
	root.multiplayer.multiplayer_peer = peer
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/screenshots")
	for entry in [
		["forge-west-foundry", "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn", Vector2(320, 480)],
		["forge-core", "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn", Vector2(1024, 400)],
		["forge-staging", "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn", Vector2(1024, 1200)],
		["sewers-west-cistern", "res://source/common/gameplay/maps/maps/sewers/sewers.tscn", Vector2(384, 448)],
		["sewers-plaza", "res://source/common/gameplay/maps/maps/sewers/sewers.tscn", Vector2(1024, 640)],
		["desert-oasis-south", "res://source/common/gameplay/maps/maps/desert/desert.tscn", Vector2(400, 680)],
	]:
		await _shot(entry[0], entry[1], entry[2])
	print("BIOME_DETAIL_PREVIEW_PASS")
	quit(0)


func _shot(name: String, path: String, cam_pos: Vector2) -> void:
	var packed: PackedScene = load(path)
	var sv := SubViewport.new()
	sv.size = Vector2i(960, 720)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.world_2d = World2D.new()
	root.add_child(sv)
	var map: Node2D = packed.instantiate() as Node2D
	sv.add_child(map)
	var cam := Camera2D.new()
	cam.position = cam_pos
	cam.make_current()
	map.add_child(cam)
	for _i: int in 10:
		await process_frame
	var image: Image = sv.get_texture().get_image()
	var out := "/opt/cursor/artifacts/screenshots/biome-%s-detail.png" % name
	image.save_png(out)
	print("SAVED ", out)
	sv.queue_free()
	await process_frame
