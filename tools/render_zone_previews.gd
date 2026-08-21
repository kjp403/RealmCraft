extends Node
## Whole-zone screenshots for review: the woodland east wing, the original
## beach, and Pirate's Cove. Framed with a Camera2D so a zone larger than a
## sensible image still fits in one picture.
##   godot --path . --mode=client res://tools/render_zone_previews.tscn

const TILE: int = 16

const SHOTS: Array[Dictionary] = [
	{
		"scene": "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn",
		"file": "woodland-east-overview.png",
		# The east wing runs from tile 60 to the map edge at 332, 100 tall.
		"center": Vector2(196 * TILE, 50 * TILE), "zoom": 0.42, "size": Vector2i(1830, 672),
	},
	{
		"scene": "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn",
		"file": "woodland-east-ponds.png",
		# The Swamp Hermit and his six ponds, at 1:1.
		"center": Vector2(300 * TILE, 42 * TILE), "zoom": 1.0, "size": Vector2i(1100, 700),
	},
	{
		"scene": "res://source/common/gameplay/maps/maps/woodland/woodland_beach.tscn",
		"file": "beach-woodland-full.png",
		"center": Vector2(416, 256), "zoom": 1.0, "size": Vector2i(832, 512),
	},
	{
		"scene": "res://source/common/gameplay/maps/maps/woodland/deep_shoals.tscn",
		"file": "pirates-cove-full.png",
		"center": Vector2(960, 544), "zoom": 0.85, "size": Vector2i(1632, 925),
	},
]


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://previews"))
	for shot: Dictionary in SHOTS:
		var sv := SubViewport.new()
		sv.size = shot["size"]
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		sv.world_2d = World2D.new()
		add_child(sv)
		var map: Node2D = (load(shot["scene"]) as PackedScene).instantiate() as Node2D
		sv.add_child(map)
		var cam := Camera2D.new()
		cam.position = shot["center"]
		cam.zoom = Vector2.ONE * float(shot["zoom"])
		map.add_child(cam)
		cam.make_current()
		for _i in 24:
			await get_tree().process_frame
		var path: String = "res://previews/%s" % shot["file"]
		sv.get_texture().get_image().save_png(path)
		print("SAVED ", path)
		sv.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
