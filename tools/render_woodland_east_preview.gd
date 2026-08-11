extends SceneTree
## Preview shots for contiguous Goblin Woodlands East.
##   godot --path . -s tools/render_woodland_east_preview.gd

const OUT := "/opt/cursor/artifacts/screenshots"
const MAPS := "res://source/common/gameplay/maps/maps/woodland/"

const SHOTS: Array[Dictionary] = [
	{
		"name": "woodland-east-gate",
		"path": MAPS + "woodland_tiles.tscn",
		"center": Vector2(3648, 640),
		"zoom": 0.55,
		"size": Vector2i(1100, 720),
	},
	{
		"name": "woodland-east-overview",
		"path": MAPS + "woodland_east.tscn",
		"size_cells": Vector2i(240, 180),
		"overview": true,
	},
	{
		"name": "woodland-east-crossroads",
		"path": MAPS + "woodland_east.tscn",
		"center": Vector2(1536, 1536),
		"zoom": 0.45,
		"size": Vector2i(1280, 900),
	},
	{
		"name": "woodland-east-dunes",
		"path": MAPS + "woodland_east.tscn",
		"center": Vector2(1536, 640),
		"zoom": 0.5,
		"size": Vector2i(1200, 900),
	},
	{
		"name": "woodland-east-wetlands",
		"path": MAPS + "woodland_east.tscn",
		"center": Vector2(3072, 1472),
		"zoom": 0.5,
		"size": Vector2i(1200, 900),
	},
	{
		"name": "woodland-east-ash",
		"path": MAPS + "woodland_east.tscn",
		"center": Vector2(1664, 2304),
		"zoom": 0.5,
		"size": Vector2i(1200, 900),
	},
]


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	DirAccess.make_dir_recursive_absolute(OUT)
	for shot in SHOTS:
		if shot.get("overview", false):
			var world := Vector2(shot["size_cells"] as Vector2i) * 16.0
			var vp_size := Vector2i(1600, 1200)
			var zoom: float = minf(float(vp_size.x) / world.x, float(vp_size.y) / world.y) * 0.96
			await _shot(shot["path"], vp_size, world * 0.5, zoom, "%s/%s.png" % [OUT, shot["name"]])
		else:
			await _shot(
				shot["path"],
				shot["size"],
				shot["center"],
				shot["zoom"],
				"%s/%s.png" % [OUT, shot["name"]]
			)
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
