extends Node
## ASCII dump of the Mining Cave's high-ore alcove so the carve and the vein
## spread can be reasoned about as a map instead of a list of coordinates.
##   godot --path . --mode=client res://tools/map_alcove.tscn

const SCENE: String = "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"
const TILE: int = 32
const X0: int = 44
const X1: int = 70
const Y0: int = 2
const Y1: int = 24


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node = (load(SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var ground: TileMapLayer = root.get_node("Tiles/Ground") as TileMapLayer
	var walls: TileMapLayer = root.get_node("Tiles/Walls") as TileMapLayer
	var ore: Dictionary = {}
	for node: Node in root.get_node("MineableNodes").get_children():
		var pos: Vector2 = (node as Node2D).position
		var cell := Vector2i(int((pos.x - TILE / 2.0) / TILE), int((pos.y - TILE / 2.0) / TILE))
		ore[cell] = String(node.name).substr(0, 1)
	print("    " + "".join(range(X0, X1).map(func(x: int) -> String: return str(x % 10))))
	for y: int in range(Y0, Y1):
		var row: String = "%3d " % y
		for x: int in range(X0, X1):
			var cell := Vector2i(x, y)
			if ore.has(cell):
				row += String(ore[cell])
			elif walls.get_cell_source_id(cell) >= 0:
				row += "#"
			elif ground.get_cell_source_id(cell) >= 0:
				row += "."
			else:
				row += " "
		print(row)
	root.free()
	get_tree().quit(0)
