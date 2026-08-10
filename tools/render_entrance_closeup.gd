extends SceneTree
func _initialize() -> void:
	call_deferred("_go")
func _go() -> void:
	var peer := OfflineMultiplayerPeer.new()
	root.multiplayer.multiplayer_peer = peer
	DirAccess.make_dir_recursive_absolute("/opt/cursor/artifacts/screenshots")
	var packed = load("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn")
	var sv := SubViewport.new()
	sv.size = Vector2i(960, 640)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.world_2d = World2D.new()
	root.add_child(sv)
	var map = packed.instantiate()
	sv.add_child(map)
	var cam := Camera2D.new()
	cam.position = Vector2(1600, 600)
	cam.zoom = Vector2(1.2, 1.2)
	cam.make_current()
	map.add_child(cam)
	for i in 16: await process_frame
	sv.get_texture().get_image().save_png("/opt/cursor/artifacts/screenshots/hotfix-woodland-portal.png")
	print("SAVED")
	quit(0)
