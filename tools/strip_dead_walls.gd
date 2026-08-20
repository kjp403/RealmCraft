extends Node
## Remove the dead-end cliff runs east of the Swamp Hermit — wall segments that
## enclose nothing and just chop the field up. Rects are in TILE space; the
## render rig writes previews from the same coordinates so the result can be
## checked against the picture.
##   godot --path . --mode=client res://tools/strip_dead_walls.tscn

const MAP: String = "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
## Derived from the annotated screenshot: preview origin tile (300, 20), 16px
## tiles, so image pixel / 16 + origin = tile.
const RECTS: Array[Rect2i] = [
	Rect2i(314, 36, 18, 14),   # upper loop, right of the pond path
	Rect2i(313, 51, 18, 16),   # lower loop, south-east of the small pond
	Rect2i(316, 48, 12, 4),    # stub left of the small pond
	Rect2i(314, 65, 10, 5),    # stub south of it
]
## Layers that draw the cliffs.
const LAYERS: Array[String] = ["Walls", "WallDecor"]


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node = (load(MAP) as PackedScene).instantiate()
	var removed: int = 0
	for layer_name: String in LAYERS:
		var layer: TileMapLayer = root.get_node_or_null(layer_name) as TileMapLayer
		if layer == null:
			continue
		for cell: Vector2i in layer.get_used_cells():
			for rect: Rect2i in RECTS:
				if rect.has_point(cell):
					layer.erase_cell(cell)
					removed += 1
					break
	print("removed %d wall cells" % removed)
	var packed := PackedScene.new()
	packed.pack(root)
	print("saved: ", ResourceSaver.save(packed, MAP) == OK)
	get_tree().quit(0)
