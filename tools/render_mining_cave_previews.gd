extends SceneTree
## Render Mining Cave previews for review.
## Close-ups are 1024×576 at 1:1 zoom to match the reference screenshots.
##   godot --path . --mode=client -s tools/render_mining_cave_previews.gd

const OUT_DIR := "/opt/cursor/artifacts/screenshots"
const SCENE := "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	# Whole map, zoomed out.
	await _shot("mining-cave-overview", Vector2(1024, 736), 0.5, Vector2i(1100, 800))
	# Reference-scale close-ups.
	await _shot("mining-cave-entrance", Vector2(400, 1160), 1.0, Vector2i(1024, 576))
	await _shot("mining-cave-junction", Vector2(1060, 870), 1.0, Vector2i(1024, 576))
	await _shot("mining-cave-north-hall", Vector2(900, 420), 1.0, Vector2i(1024, 576))
	await _shot("mining-cave-east-gallery", Vector2(1660, 960), 1.0, Vector2i(1024, 576))
	print("MINING_CAVE_PREVIEW_PASS")
	quit(0)


func _shot(name: String, cam_pos: Vector2, zoom: float, size: Vector2i) -> void:
	var packed: PackedScene = load(SCENE)
	var sv := SubViewport.new()
	sv.size = size
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sv.world_2d = World2D.new()
	root.add_child(sv)
	var map: Node2D = packed.instantiate() as Node2D
	sv.add_child(map)
	var cam := Camera2D.new()
	cam.position = cam_pos
	cam.zoom = Vector2(zoom, zoom)
	map.add_child(cam)
	cam.make_current()
	for _i in 14:
		await process_frame
	var out := "%s/%s.png" % [OUT_DIR, name]
	sv.get_texture().get_image().save_png(out)
	print("SAVED ", out)
	sv.queue_free()
	await process_frame
