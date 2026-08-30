extends SceneTree
## Combined preview of the three 32px sewer biomes: a whole-map overview and a
## gameplay-zoom crop for each, stacked into one sheet.
##
## Both scales are needed. An overview renders each tile at a few pixels and
## only shows topology; a crop only shows a few hundred tiles and cannot show
## whether the zone reads as open. Judging the art needs both.
##
##   godot --path . -s tools/render_sewer_biome_32.gd

const MAPS := "res://source/common/gameplay/maps/maps/sewers/"

const ZONES: Array[Dictionary] = [
	{"map": "sewers.tscn", "world": Vector2(4480, 3360), "crop": Vector2(2240, 1900), "z": 1.0},
	{"map": "gutterworks.tscn", "world": Vector2(6400, 4800), "crop": Vector2(3200, 1700), "z": 1.0},
	{"map": "drowned_cistern.tscn", "world": Vector2(7040, 5280), "crop": Vector2(3520, 2640), "z": 1.0},
]

const OVER := Vector2i(1160, 420)
const CROP := Vector2i(1160, 300)
const PAD := 8

var _out: String = "build/sewer_biome_32px_full_preview.png"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr("--out=".length())
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var images: Array[Image] = []
	for zone in ZONES:
		var packed: PackedScene = load(MAPS + zone["map"])
		if packed == null:
			printerr("FAIL could not load ", zone["map"])
			quit(1)
			return
		var world: Vector2 = zone["world"]
		var fit: float = minf(float(OVER.x) / world.x, float(OVER.y) / world.y) * 0.97
		images.append(await _shot(packed, OVER, world * 0.5, fit))
		images.append(await _shot(packed, CROP, zone["crop"], zone["z"]))

	var height: int = 0
	for img in images:
		height += img.get_height() + PAD
	var sheet := Image.create(OVER.x, height, false, images[0].get_format())
	sheet.fill(Color(0.06, 0.06, 0.08))
	var y: int = 0
	for img in images:
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(0, y))
		y += img.get_height() + PAD

	var abs_out := ProjectSettings.globalize_path("res://" + _out)
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	sheet.save_png(abs_out)
	print("SAVED ", abs_out)
	print("SEWER_BIOME_32_PREVIEW_OK")
	quit(0)


func _shot(packed: PackedScene, size: Vector2i, at: Vector2, zoom: float) -> Image:
	var sub := SubViewport.new()
	sub.size = size
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sub.world_2d = World2D.new()
	root.add_child(sub)

	var map: Node2D = packed.instantiate() as Node2D
	sub.add_child(map)
	var cam := Camera2D.new()
	cam.position = at
	cam.zoom = Vector2(zoom, zoom)
	map.add_child(cam)
	cam.make_current()

	for _i in 24:
		await process_frame
	var img := sub.get_texture().get_image()
	sub.queue_free()
	await process_frame
	return img
