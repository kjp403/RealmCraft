extends Node
## Pick alcove cells for the Dragon/Obsidian/Celestial/Astralite veins: open floor,
## 3+ open sides, and > 1.5x gather range from every other vein.
##   godot --path . --mode=client res://tools/plan_high_ore_slots.tscn

const SCENE: String = "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"
const TILE: int = 32
const MIN_DIST: float = 84.0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node = (load(SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var ground: TileMapLayer = root.get_node("Tiles/Ground") as TileMapLayer
	var walls: TileMapLayer = root.get_node("Tiles/Walls") as TileMapLayer

	var taken: Array[Vector2] = []
	for node: Node in root.get_node("MineableNodes").get_children():
		var name_str: String = String(node.name)
		if name_str.begins_with("Dragon") or name_str.begins_with("Obsidian") \
				or name_str.begins_with("Celestial") or name_str.begins_with("Astralite"):
			continue
		taken.append((node as Node2D).position)

	var candidates: Array[Vector2i] = []
	for cell: Vector2i in ground.get_used_cells():
		if cell.x < 52 or walls.get_cell_source_id(cell) >= 0:
			continue
		var open_sides: int = 0
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if walls.get_cell_source_id(cell + step) < 0:
				open_sides += 1
		if open_sides >= 3:
			candidates.append(cell)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y * 1000 + a.x < b.y * 1000 + b.x)

	var picked: Array[Vector2] = []
	for cell: Vector2i in candidates:
		var pos := Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
		var ok: bool = true
		for other: Vector2 in taken + picked:
			if pos.distance_to(other) < MIN_DIST:
				ok = false
				break
		if ok:
			picked.append(pos)
	print("usable slots (", picked.size(), "):")
	for pos: Vector2 in picked:
		print("  Vector2(%d, %d)" % [pos.x, pos.y])
	root.free()
	get_tree().quit(0)
