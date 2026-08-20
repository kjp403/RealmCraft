extends Node
## Screenshot both beaches whole, so the composed coastline, the prop placement
## and the fishing holes can be judged as a picture rather than as coordinates.
##   godot --path . --mode=client res://tools/render_beach_previews.tscn

const SHOTS: Array[Dictionary] = [
	{
		"scene": "res://source/common/gameplay/maps/maps/woodland/woodland_beach.tscn",
		"file": "beach-woodland.png", "size": Vector2i(832, 512),
	},
	{
		"scene": "res://source/common/gameplay/maps/maps/woodland/woodland_east_link.tscn",
		"file": "beach-east-link.png", "size": Vector2i(768, 512),
	},
	{
		"scene": "res://source/common/gameplay/maps/maps/woodland/deep_shoals.tscn",
		"file": "beach-deep-shoals.png", "size": Vector2i(1088, 640),
	},
]


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var out_abs: String = ProjectSettings.globalize_path("res://previews")
	DirAccess.make_dir_recursive_absolute(out_abs)
	for shot: Dictionary in SHOTS:
		var sv := SubViewport.new()
		sv.size = shot["size"]
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		sv.transparent_bg = false
		sv.disable_3d = true
		get_tree().root.add_child(sv)

		var packed: PackedScene = load(shot["scene"]) as PackedScene
		if packed == null:
			push_error("could not load %s" % shot["scene"])
			continue
		var map: Node = packed.instantiate()
		sv.add_child(map)
		for _i: int in 12:
			await get_tree().process_frame
		var image: Image = sv.get_texture().get_image()
		var dest: String = out_abs.path_join(str(shot["file"]))
		image.save_png(dest)
		print("SAVED ", dest, " ", image.get_size())
		map.queue_free()
		sv.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	get_tree().quit(0)
