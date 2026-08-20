extends Node
## Screenshot slices of the woodland east wing so the void fill, the ponds and
## the decoration can be judged as pictures.
##   godot --path . --mode=client res://tools/render_woodland_east.tscn

const MAP: String = "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
const TILE: int = 16
## Tile-space windows across the east wing.
## Centred on the Swamp Hermit at tile (300, 42), where the ponds are.
const SHOTS: Array[Vector2i] = [Vector2i(262, 20), Vector2i(300, 20)]
const SIZE := Vector2i(80, 50)


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var out: String = ProjectSettings.globalize_path("res://previews")
	DirAccess.make_dir_recursive_absolute(out)
	var map: Node2D = (load(MAP) as PackedScene).instantiate() as Node2D
	for i: int in SHOTS.size():
		var sv := SubViewport.new()
		sv.size = SIZE * TILE
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		sv.disable_3d = true
		get_tree().root.add_child(sv)
		if map.get_parent() != null:
			map.get_parent().remove_child(map)
		map.position = -Vector2(SHOTS[i] * TILE)
		sv.add_child(map)
		for _f: int in 10:
			await get_tree().process_frame
		var img: Image = sv.get_texture().get_image()
		img.save_png(out.path_join("east-%d.png" % i))
		print("SAVED east-%d.png at tile %s" % [i, SHOTS[i]])
		sv.remove_child(map)
		sv.queue_free()
		await get_tree().process_frame
	map.free()
	get_tree().quit(0)
