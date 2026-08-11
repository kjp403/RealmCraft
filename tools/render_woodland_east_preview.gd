extends SceneTree
## Overview + east-gate closeup of Goblin Woodland after 5x east expansion.
##   godot --path . -s tools/render_woodland_east_preview.gd

const MAP := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
const OUT := "/opt/cursor/artifacts/screenshots"

func _initialize() -> void:
	call_deferred(&"_go")

func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	DirAccess.make_dir_recursive_absolute(OUT)
	await _shot(Vector2(8536, 800), 0.08, "%s/woodland-east-overview.png" % OUT, Vector2i(1600, 700))
	await _shot(Vector2(2900, 640), 0.55, "%s/woodland-east-gate.png" % OUT, Vector2i(960, 720))
	await _shot(Vector2(4500, 250), 0.45, "%s/woodland-east-desert.png" % OUT, Vector2i(960, 720))
	await _shot(Vector2(4500, 800), 0.45, "%s/woodland-east-swamp.png" % OUT, Vector2i(960, 720))
	await _shot(Vector2(4500, 1300), 0.45, "%s/woodland-east-volcano.png" % OUT, Vector2i(960, 720))
	print("WOODLAND_EAST_PREVIEW_PASS")
	quit(0)

func _shot(center: Vector2, zoom: float, path: String, size: Vector2i) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(vp)
	var world: Node2D = load(MAP).instantiate() as Node2D
	vp.add_child(world)
	var cam := Camera2D.new()
	cam.enabled = true
	cam.position = center
	cam.zoom = Vector2(zoom, zoom)
	world.add_child(cam)
	cam.make_current()
	await process_frame
	await process_frame
	await process_frame
	var img: Image = vp.get_texture().get_image()
	img.save_png(path)
	print("wrote ", path)
	vp.queue_free()
	await process_frame
