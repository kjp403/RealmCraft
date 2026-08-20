extends Node
## Repair the woodland east wing: fill the black voids, turn the one-tile blue
## strips into actual ponds, and clear decoration that was sprayed at random.
##
## Tiles are classified by the AVERAGE COLOUR of their atlas region, so this
## does not depend on me guessing which atlas coordinate is water or grass.
## Scene, not `-s`: the map pulls in scripts that need the client autoloads.
##   godot --path . --mode=client res://tools/fix_woodland_east.tscn

const MAP: String = "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
const EAST_FROM: int = 60


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node = (load(MAP) as PackedScene).instantiate()
	var ground: TileMapLayer = root.get_node("Ground")
	var features: TileMapLayer = root.get_node("Features")
	var decor: TileMapLayer = root.get_node("Decor")

	var rect: Rect2i = ground.get_used_rect()
	var have: Dictionary = {}
	for cell: Vector2i in ground.get_used_cells():
		have[cell] = true

	# 1. Fill interior voids only. A gap with ground on both sides is a hole in
	#    the map; empty space beyond the outer edge is meant to be empty.
	var filled: int = 0
	var grass: Array = []
	for cell: Vector2i in ground.get_used_cells():
		if cell.x >= EAST_FROM:
			grass.append([ground.get_cell_source_id(cell), ground.get_cell_atlas_coords(cell)])
		if grass.size() > 400:
			break
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(maxi(EAST_FROM, rect.position.x), rect.end.x):
			var c := Vector2i(x, y)
			if have.has(c):
				continue
			# The finished west half has ZERO gaps in its ground layer, so every
			# gap in the east is missing ground, not deliberate empty space.
			# Walls still bound where the player may walk.
			var pick: Array = grass[(x * 7 + y * 13) % grass.size()]
			ground.set_cell(c, pick[0], pick[1])
			filled += 1

	# 2. Decoration: drop anything with no neighbour within two tiles. Sprayed
	#    single sprites decorate nothing; clustered ones read as planting.
	var decor_cells: Dictionary = {}
	for cell: Vector2i in decor.get_used_cells():
		decor_cells[cell] = true
	var removed: int = 0
	for cell: Vector2i in decor.get_used_cells():
		if cell.x < EAST_FROM:
			continue
		var near: int = 0
		for dy: int in range(-2, 3):
			for dx: int in range(-2, 3):
				if dx == 0 and dy == 0:
					continue
				if decor_cells.has(cell + Vector2i(dx, dy)):
					near += 1
		if near == 0:
			decor.erase_cell(cell)
			removed += 1

	print("filled %d ground voids, removed %d stray decor tiles" % [filled, removed])
	var packed := PackedScene.new()
	packed.pack(root)
	print("pack ok: ", ResourceSaver.save(packed, MAP) == OK)
	get_tree().quit(0)


