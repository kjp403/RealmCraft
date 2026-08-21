extends SceneTree
## Rebuild the Boss Hunt arena at a size you can actually fight in, and print the
## tile data so the scene can be patched as TEXT.
##
## Deliberately NOT saved with PackedScene.pack(): packing a live scene rewrote
## the woodland map's nodes and dropped properties that matched defaults. Only
## the three tile_map_data strings come out of here.
##   godot --headless --path . -s tools/build_boss_arena.gd

const ARENA: String = "res://source/common/gameplay/maps/maps/boss_hunt/boss_hunt_arena.tscn"
## 60x40 tiles at 16px = 960x640: roughly four times the old floor area, enough
## to kite a slam and still see the walls.
const COLS: int = 60
const ROWS: int = 40
const WALL_THICKNESS: int = 2


func _init() -> void:
	var packed: PackedScene = load(ARENA)
	var root: Node = packed.instantiate()
	var ground: TileMapLayer = root.get_node("Map_tiles/Ground")
	var walls: TileMapLayer = root.get_node("Map_tiles/Walls")
	var props: TileMapLayer = root.get_node("Map_tiles/Props")

	# Reuse whatever the room is already made of, so the art stays consistent.
	# Take the floor's MOST COMMON tile as the base. Cycling through every
	# variant with a positional index drew a diagonal stripe across the room.
	var counts: Dictionary = {}
	for cell: Vector2i in ground.get_used_cells():
		if walls.get_cell_source_id(cell) >= 0:
			continue
		var key: String = "%d|%s" % [ground.get_cell_source_id(cell), ground.get_cell_atlas_coords(cell)]
		counts[key] = int(counts.get(key, 0)) + 1
	var ranked: Array = counts.keys()
	ranked.sort_custom(func(a, b): return counts[a] > counts[b])
	var floor_tiles: Array = []
	for key: String in ranked.slice(0, 1):
		var parts: PackedStringArray = key.split("|")
		var xy: PackedStringArray = parts[1].replace("(", "").replace(")", "").split(", ")
		floor_tiles.append([int(parts[0]), Vector2i(int(xy[0]), int(xy[1]))])
	print("floor variants kept: %d of %d" % [floor_tiles.size(), ranked.size()])
	var wall_tiles: Array = []
	for cell: Vector2i in walls.get_used_cells():
		wall_tiles.append([walls.get_cell_source_id(cell), walls.get_cell_atlas_coords(cell)])
	if floor_tiles.is_empty() or wall_tiles.is_empty():
		push_error("could not sample the existing arena tiles")
		quit(1)
		return
	print("sampled %d floor tiles and %d wall tiles" % [floor_tiles.size(), wall_tiles.size()])

	ground.clear()
	walls.clear()
	props.clear()
	for y: int in ROWS:
		for x: int in COLS:
			var pick: Array = floor_tiles[0]
			ground.set_cell(Vector2i(x, y), pick[0], pick[1])
	for y: int in ROWS:
		for x: int in COLS:
			var edge: bool = (
				x < WALL_THICKNESS or y < WALL_THICKNESS
				or x >= COLS - WALL_THICKNESS or y >= ROWS - WALL_THICKNESS
			)
			if edge:
				var w: Array = wall_tiles[(x * 5 + y * 11) % wall_tiles.size()]
				walls.set_cell(Vector2i(x, y), w[0], w[1])

	for layer: TileMapLayer in [ground, walls, props]:
		# The serialised blob lags the set_cell calls until internals refresh; in
		# a -s run nothing pumps that, so ask explicitly or you export the OLD
		# room and think you resized it.
		layer.update_internals()
		print("  %s now holds %d cells" % [layer.name, layer.get_used_cells().size()])
		var data: PackedByteArray = layer.tile_map_data
		print("LAYER %s = %s" % [layer.name, Marshalls.raw_to_base64(data)])
	root.free()
	quit(0)
