extends Node
## Print free floor cells in the Mining Cave's high-ore alcove (x >= 52) so new
## adamant/runite veins can be hand-placed into mining_cave.tscn without
## re-running build_mining_cave.gd, which would wipe the hand-added skeletons,
## courier, bats and music the scene has picked up since it was generated.
##
## Scene, not `-s`: the map pulls in scripts that reference the client
## autoloads, which a bare SceneTree does not have.
##   godot --path . --mode=client res://tools/find_alcove_ore_slots.tscn

const SCENE: String = "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"
const TILE: int = 32
const MIN_SPACING: int = 2


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var packed: PackedScene = load(SCENE) as PackedScene
	var root: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var ground: TileMapLayer = root.get_node("Tiles/Ground") as TileMapLayer
	var walls: TileMapLayer = root.get_node("Tiles/Walls") as TileMapLayer

	var wall_cells: Dictionary = {}
	for cell: Vector2i in walls.get_used_cells():
		wall_cells[cell] = true

	var taken: Array[Vector2i] = []
	for node: Node in root.get_node("MineableNodes").get_children():
		var pos: Vector2 = (node as Node2D).position
		taken.append(Vector2i(int((pos.x - TILE / 2.0) / TILE), int((pos.y - TILE / 2.0) / TILE)))

	var free: Array[Vector2i] = []
	for cell: Vector2i in ground.get_used_cells():
		if cell.x < 52 or wall_cells.has(cell):
			continue
		var clear: bool = true
		for used: Vector2i in taken:
			if absi(used.x - cell.x) < MIN_SPACING and absi(used.y - cell.y) < MIN_SPACING:
				clear = false
				break
		if clear:
			free.append(cell)
	free.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y * 1000 + a.x < b.y * 1000 + b.x)

	print("existing veins: ", taken.filter(func(c: Vector2i) -> bool: return c.x >= 52))
	print("free alcove cells (", free.size(), "):")
	for cell: Vector2i in free:
		print("  ", cell, " -> Vector2(%.1f, %.1f)" % [cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0])
	root.free()
	get_tree().quit(0)
