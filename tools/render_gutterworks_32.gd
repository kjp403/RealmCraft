extends SceneTree
## Preview sheet for the 32px Gutterworks: one whole-map overview plus two
## gameplay-zoom crops, because an overview alone renders each tile at a couple
## of pixels and cannot show whether the art actually reads.
##
##   godot --path . -s tools/render_gutterworks_32.gd -- --out=build/gutterworks_32px_preview.png

const MAP := "res://source/common/gameplay/maps/maps/sewers/gutterworks.tscn"

const SHOTS: Array[Dictionary] = [
	{"name": "overview", "size": Vector2i(1200, 900), "at": Vector2(3328, 2496), "zoom": 0.175},
	{"name": "junction", "size": Vector2i(1200, 450), "at": Vector2(3328, 2560), "zoom": 1.6},
	{"name": "channel", "size": Vector2i(1200, 450), "at": Vector2(2200, 1280), "zoom": 1.6},
]

var _out: String = "build/gutterworks_32px_preview.png"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr("--out=".length())
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var packed: PackedScene = load(MAP)
	if packed == null:
		printerr("FAIL could not load ", MAP)
		quit(1)
		return

	var images: Array[Image] = []
	for shot in SHOTS:
		images.append(await _shot(packed, shot))

	var width: int = 0
	var height: int = 0
	for img in images:
		width = maxi(width, img.get_width())
		height += img.get_height() + 6
	var sheet := Image.create(width, height, false, images[0].get_format())
	sheet.fill(Color(0.07, 0.07, 0.09))
	var y: int = 0
	for img in images:
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(0, y))
		y += img.get_height() + 6

	var abs_out: String = ProjectSettings.globalize_path("res://" + _out) if not _out.begins_with("/") and _out.find(":") < 0 else _out
	DirAccess.make_dir_recursive_absolute(abs_out.get_base_dir())
	sheet.save_png(abs_out)
	print("SAVED ", abs_out)
	print("GUTTERWORKS_32_PREVIEW_OK")
	quit(0)


func _shot(packed: PackedScene, shot: Dictionary) -> Image:
	var sub := SubViewport.new()
	sub.size = shot["size"]
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	sub.world_2d = World2D.new()
	root.add_child(sub)

	var map: Node2D = packed.instantiate() as Node2D
	sub.add_child(map)
	var cam := Camera2D.new()
	cam.position = shot["at"]
	var z: float = shot["zoom"]
	cam.zoom = Vector2(z, z)
	map.add_child(cam)
	cam.make_current()

	for _i in 24:
		await process_frame
	var img := sub.get_texture().get_image()
	sub.queue_free()
	await process_frame
	return img
