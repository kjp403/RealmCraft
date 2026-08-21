extends Node
## Rebuild the Boss Hunt arena at a size you can actually fight in, and print the
## tile data so the scene can be patched as TEXT.
##
## Deliberately NOT saved with PackedScene.pack(): packing a live scene rewrote
## the woodland map's nodes and dropped properties that matched defaults. Only
## the three tile_map_data strings come out of here.
## The reference room pulls NPC scenes, so it needs autoloads: run it as a
## SCENE, not with -s.
##   godot --path . --mode=client res://tools/build_boss_arena.tscn

const ARENA: String = "res://source/common/gameplay/maps/maps/boss_hunt/boss_hunt_arena.tscn"
## 60x40 tiles at 16px = 960x640: roughly four times the old floor area, enough
## to kite a slam and still see the walls.
const COLS: int = 60
const ROWS: int = 40
const WALL_THICKNESS: int = 2
## Hand-built room made from the same tileset; the wall art is copied from it.
const REFERENCE_ROOM: String = "res://source/common/gameplay/maps/maps/quest_boss/quest_boss_arena.tscn"


func _ready() -> void:
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
	# Walls are learned BY ROLE from the hand-authored quest boss arena, which is
	# built from the same tileset. Picking a random variant per cell (what this
	# did before) scatters loose planks around the border instead of drawing a
	# wall: these tiles are directional, so a top-edge tile only reads as a wall
	# along the top.
	var wall_by_role: Dictionary = _learn_wall_roles()
	if floor_tiles.is_empty() or wall_by_role.is_empty():
		push_error("could not sample the existing arena tiles")
		get_tree().quit(1)
		return
	print("learned %d wall roles" % wall_by_role.size())

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
			if not edge:
				continue
			var role: int = _role_at(x, y)
			if not wall_by_role.has(role):
				role = 15 # fully enclosed interior wall — always learned
			var w: Array = wall_by_role[role]
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
	get_tree().quit(0)


## A wall cell's role is which of its four neighbours are also wall, as a
## bitmask (1 N, 2 S, 4 W, 8 E). Two cells with the same role want the same
## art: a top-left outer corner has neighbours south and east and nothing else.
func _role_at(x: int, y: int) -> int:
	var role: int = 0
	if _is_wall(x, y - 1):
		role |= 1
	if _is_wall(x, y + 1):
		role |= 2
	if _is_wall(x - 1, y):
		role |= 4
	if _is_wall(x + 1, y):
		role |= 8
	return role


func _is_wall(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= COLS or y >= ROWS:
		return false
	return (
		x < WALL_THICKNESS or y < WALL_THICKNESS
		or x >= COLS - WALL_THICKNESS or y >= ROWS - WALL_THICKNESS
	)


## Read the quest boss arena's wall layer and record, for each role, the tile it
## most commonly uses. That room was placed by hand, so its choices are correct
## by construction.
func _learn_wall_roles() -> Dictionary:
	var packed: PackedScene = load(REFERENCE_ROOM)
	if packed == null:
		return {}
	var root: Node = packed.instantiate()
	var layer: TileMapLayer = root.get_node_or_null("Map_tiles/Walls") as TileMapLayer
	if layer == null:
		root.free()
		return {}
	var used: Dictionary = {}
	for cell: Vector2i in layer.get_used_cells():
		used[cell] = true
	var tally: Dictionary = {}
	for cell: Vector2i in used:
		var role: int = 0
		if used.has(cell + Vector2i.UP):
			role |= 1
		if used.has(cell + Vector2i.DOWN):
			role |= 2
		if used.has(cell + Vector2i.LEFT):
			role |= 4
		if used.has(cell + Vector2i.RIGHT):
			role |= 8
		var key: String = "%d|%s" % [layer.get_cell_source_id(cell), layer.get_cell_atlas_coords(cell)]
		if not tally.has(role):
			tally[role] = {}
		tally[role][key] = int(tally[role].get(key, 0)) + 1
	var out: Dictionary = {}
	for role: int in tally:
		var keys: Array = tally[role].keys()
		keys.sort_custom(func(a, b): return tally[role][a] > tally[role][b])
		var parts: PackedStringArray = String(keys[0]).split("|")
		var xy: PackedStringArray = parts[1].replace("(", "").replace(")", "").split(", ")
		out[role] = [int(parts[0]), Vector2i(int(xy[0]), int(xy[1]))]
	root.free()
	return out
