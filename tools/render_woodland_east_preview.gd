extends SceneTree
## Preview shots for East Wilds hub + biome stubs.
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
		"name": "woodland-east-wilds",
		"path": MAPS + "woodland_east_wilds.tscn",
		"size_cells": Vector2i(88, 64),
		"overview": true,
	},
	{
		"name": "woodland-east-dunes",
		"path": MAPS + "east_dunes.tscn",
		"size_cells": Vector2i(104, 76),
		"overview": true,
	},
	{
		"name": "woodland-east-wetlands",
		"path": MAPS + "east_wetlands.tscn",
		"size_cells": Vector2i(112, 84),
		"overview": true,
	},
	{
		"name": "woodland-east-ash",
		"path": MAPS + "east_ash_fields.tscn",
		"size_cells": Vector2i(112, 84),
		"overview": true,
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
			var vp_size := Vector2i(1400, 1100)
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
