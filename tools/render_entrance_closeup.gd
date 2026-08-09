extends SceneTree
## Close-up of Woodland Mining Cave portal at the cliff face.
## Run: xvfb-run -a godot --path . -s tools/render_entrance_closeup.gd

func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	var peer := OfflineMultiplayerPeer.new()
	root.multiplayer.multiplayer_peer = peer
	var packed = load("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn")
	var sv := SubViewport.new()
	sv.size = Vector2i(800, 520)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.world_2d = World2D.new()
	root.add_child(sv)
	var map = packed.instantiate()
	sv.add_child(map)
	var cam := Camera2D.new()
	cam.position = Vector2(1640, 632)
	cam.zoom = Vector2(1.35, 1.35)
	cam.make_current()
	map.add_child(cam)
	for i in 16:
		await process_frame
	sv.get_texture().get_image().save_png("/opt/cursor/artifacts/screenshots/woodland-mining-entrance-closeup.png")
	print("SAVED closeup")
	quit(0)
