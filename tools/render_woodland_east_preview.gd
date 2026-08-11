extends SceneTree
## Contiguous Goblin Woodlands East previews (woodland_tiles only).
##   godot --path . -s tools/render_woodland_east_preview.gd

const OUT := "/opt/cursor/artifacts/screenshots"
const MAP := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"

const SHOTS: Array[Dictionary] = [
	{"name": "woodland-east-FULL", "center": Vector2(2500, 800), "zoom": 0.22, "size": Vector2i(1600, 1000)},
	{"name": "woodland-east-GATE", "center": Vector2(3000, 640), "zoom": 0.5, "size": Vector2i(1200, 800)},
	{"name": "woodland-east-CROSSROADS", "center": Vector2(3400, 672), "zoom": 0.55, "size": Vector2i(1200, 900)},
	{"name": "woodland-east-MEADOW", "center": Vector2(3680, 256), "zoom": 0.6, "size": Vector2i(1200, 900)},
	{"name": "woodland-east-PONDS", "center": Vector2(4800, 672), "zoom": 0.55, "size": Vector2i(1200, 900)},
	{"name": "woodland-east-SHELVES", "center": Vector2(3760, 1152), "zoom": 0.55, "size": Vector2i(1200, 900)},
]


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	DirAccess.make_dir_recursive_absolute(OUT)
	# Remove old misleading preview names
	for old in [
		"woodland-east-overview.png", "woodland-east-crossroads.png", "woodland-east-clearings.png",
		"woodland-east-ponds.png", "woodland-east-shelves.png", "woodland-east-gate.png",
		"woodland-east-dunes.png", "woodland-east-wetlands.png", "woodland-east-ash.png",
		"woodland-east-desert.png", "woodland-east-swamp.png", "woodland-east-volcano.png",
		"woodland-east-wilds.png",
	]:
		var p := "%s/%s" % [OUT, old]
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	for shot in SHOTS:
		await _shot(MAP, shot["size"], shot["center"], shot["zoom"], "%s/%s.png" % [OUT, shot["name"]])
	print("WOODLAND_EAST_PREVIEW_PASS")
	quit(0)


func _shot(path: String, size: Vector2i, center: Vector2, zoom: float, out_path: String) -> void:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(vp)
	var world: Node2D = load(path).instantiate() as Node2D
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
	vp.get_texture().get_image().save_png(out_path)
	print("wrote ", out_path)
	vp.queue_free()
	await process_frame
