extends Node
## Report what the woodland east wing actually contains: extent of each layer,
## where ground is missing (the black voids), and how the ponds are built.
##   godot --path . --mode=client res://tools/audit_woodland_east.tscn

const MAP: String = "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
const EAST_FROM: int = 60   # tiles; the east wing starts around here


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node = (load(MAP) as PackedScene).instantiate()
	var layers: Array[String] = ["Ground", "Features", "Decor", "Walls", "WallDecor", "Trees"]
	var ground_cells: Dictionary = {}
	for name: String in layers:
		var layer: TileMapLayer = root.get_node_or_null(name) as TileMapLayer
		if layer == null:
			continue
		var used: Rect2i = layer.get_used_rect()
		var east: int = 0
		var sources: Dictionary = {}
		for cell: Vector2i in layer.get_used_cells():
			if cell.x >= EAST_FROM:
				east += 1
				var sid: int = layer.get_cell_source_id(cell)
				var atlas: Vector2i = layer.get_cell_atlas_coords(cell)
				var key: String = "%d:%d,%d" % [sid, atlas.x, atlas.y]
				sources[key] = int(sources.get(key, 0)) + 1

		print("%-10s rect %s, %d cells east of x%d" % [name, used, east, EAST_FROM])
		var keys: Array = sources.keys()
		keys.sort_custom(func(a, b): return sources[a] > sources[b])
		for k: String in keys.slice(0, 6):
			print("    tile %-12s x%d" % [k, sources[k]])

	# Holes in the ground layer inside the east wing's bounding box = black void.
	var ground: TileMapLayer = root.get_node("Ground") as TileMapLayer
	for cell: Vector2i in ground.get_used_cells():
		ground_cells[cell] = true
	var rect: Rect2i = ground.get_used_rect()
	var holes: int = 0
	var samples: PackedStringArray = []
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(maxi(EAST_FROM, rect.position.x), rect.end.x):
			if not ground_cells.has(Vector2i(x, y)):
				holes += 1
				if samples.size() < 10:
					samples.append("(%d,%d)" % [x, y])
	print("ground holes east of x%d: %d  e.g. %s" % [EAST_FROM, holes, ", ".join(samples)])
	# Compare with the finished west half: if the west has no holes, the east
	# voids are simply missing ground rather than deliberate empty space.
	var west_holes: int = 0
	for wy: int in range(rect.position.y, rect.end.y):
		for wx: int in range(rect.position.x, mini(EAST_FROM, rect.end.x)):
			if not ground_cells.has(Vector2i(wx, wy)):
				west_holes += 1
	print("ground holes WEST of x%d: %d (of %d cells)" % [
		EAST_FROM, west_holes, (EAST_FROM - rect.position.x) * rect.size.y
	])
	root.free()
	get_tree().quit(0)
