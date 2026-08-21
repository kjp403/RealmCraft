extends Node
## Open up the Mining Cave's high-ore alcove and re-space its adamant/runite
## veins.
##
## Thirteen veins were hand-placed into a chamber about ten tiles across, which
## put several of them one tile (32px) apart — well inside HarvestController's
## 48px gather range, so clicking one vein could grab a neighbour instead.
##
## The chamber is widened as an organic blob (never a stamped rectangle — the
## rest of this cave is carved from masks) and the veins are re-laid on a
## minimum 3-tile spacing, runite toward the back of the chamber and adamant
## nearer the approach.
##
## Prints base64 tile data + node positions; the scene is patched as TEXT by
## scratchpad/patch_alcove.py. Deliberately NOT re-running build_mining_cave.gd,
## which would wipe the hand-added skeletons, courier, bats and music.
##   godot --path . --mode=client res://tools/expand_ore_alcove.tscn

const MapKit := preload("res://tools/lib/mapkit.gd")

const SCENE: String = "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"
const TILE: int = 32
const W: int = 64
const H: int = 46
const VOID_FILL := Vector2i(4, 3)
const GROUND_PLAIN: Array[Vector2i] = [
	Vector2i(32, 28), Vector2i(33, 28), Vector2i(32, 29), Vector2i(33, 29),
]

## The chamber: an ellipse with a jittered edge, clamped so at least three
## columns of rock remain against the east map edge.
const CENTER := Vector2(55.5, 12.0)
const RADIUS := Vector2(9.0, 8.0)
const MAX_X: int = 60
const MIN_X: int = 46
const MIN_Y: int = 3
const MAX_Y: int = 21

## Chebyshev tiles between two veins. 3 tiles = 96px, double the 48px gather
## range, so a click can only ever resolve to the vein under the cursor.
const MIN_SPACING: int = 3


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node = (load(SCENE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var ground: TileMapLayer = root.get_node("Tiles/Ground") as TileMapLayer
	var walls: TileMapLayer = root.get_node("Tiles/Walls") as TileMapLayer
	var props: TileMapLayer = root.get_node("Tiles/Props") as TileMapLayer

	# A void cell is one the builder backed with solid rock fill; the walls layer
	# also holds the two cliff-face rows below a void, so it cannot be used to
	# recover the mask on its own.
	var void_mask: Dictionary = {}
	for cell: Vector2i in ground.get_used_cells():
		if ground.get_cell_atlas_coords(cell) == VOID_FILL:
			void_mask[cell] = true
	var before: int = void_mask.size()

	var carved: Array[Vector2i] = []
	for y: int in range(MIN_Y, MAX_Y + 1):
		for x: int in range(MIN_X, MAX_X + 1):
			var cell := Vector2i(x, y)
			if not void_mask.has(cell):
				continue
			var d: Vector2 = (Vector2(cell) - CENTER) / RADIUS
			# Jitter the rim by up to ~12% so the chamber edge reads as rock,
			# not as a drawn ellipse.
			var wobble: float = 0.88 + 0.24 * (float(MapKit.hash2(x, y, 77) % 1000) / 1000.0)
			if d.length() <= wobble:
				void_mask.erase(cell)
				carved.append(cell)
	print("carved %d cells (void %d -> %d)" % [carved.size(), before, void_mask.size()])

	for cell: Vector2i in carved:
		ground.set_cell(cell, 0, MapKit._pick(GROUND_PLAIN, cell, 41))
		props.erase_cell(cell)

	# Repaint the whole rim from the new mask. paint_rim is deterministic per
	# cell, so every wall away from the chamber comes back byte-identical.
	walls.clear()
	MapKit.paint_rim(walls, void_mask, _rim_spec(), Rect2i(0, 0, W, H), {})

	_place_veins(root, void_mask, walls)

	for layer: TileMapLayer in [ground, walls, props]:
		layer.update_internals()
		print("LAYER %s = %s" % [layer.name, Marshalls.raw_to_base64(layer.tile_map_data)])
	root.free()
	get_tree().quit(0)


## Lay the 13 veins out again: runite deep in the chamber, adamant on the
## approach side, nothing within MIN_SPACING of anything else and nothing
## pressed against a wall (a vein in a corner can only be mined from one side).
func _place_veins(root: Node, void_mask: Dictionary, walls: TileMapLayer) -> void:
	var open: Array[Vector2i] = []
	for y: int in range(MIN_Y - 1, MAX_Y + 2):
		for x: int in range(MIN_X - 1, MAX_X + 2):
			var cell := Vector2i(x, y)
			if void_mask.has(cell) or walls.get_cell_source_id(cell) >= 0:
				continue
			# Test the WALLS layer, not the void mask: the two cliff-face rows
			# under a void edge are solid too, and testing the mask alone put a
			# vein in a nook with one open side.
			var clear: bool = true
			for oy: int in range(-1, 2):
				for ox: int in range(-1, 2):
					if walls.get_cell_source_id(cell + Vector2i(ox, oy)) >= 0:
						clear = false
			if clear:
				open.append(cell)
	# Deepest (east, then north) first so runite takes the back of the chamber.
	open.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x * 100 - a.y > b.x * 100 - b.y)

	var chosen: Array[Vector2i] = []
	for cell: Vector2i in open:
		var ok: bool = true
		for used: Vector2i in chosen:
			if maxi(absi(used.x - cell.x), absi(used.y - cell.y)) < MIN_SPACING:
				ok = false
				break
		if ok:
			chosen.append(cell)
	print("slots at %d-tile spacing: %d" % [MIN_SPACING, chosen.size()])

	# Interleave the two ores across the chamber instead of stacking all the
	# runite in one pocket: five evenly spread slots go to runite, the rest to
	# adamant, so neither ore is a single clump players crowd around.
	chosen.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y * 100 + a.x < b.y * 100 + b.x)
	var wanted: int = mini(13, chosen.size())
	var runite_at: Dictionary = {}
	for i: int in 5:
		runite_at[int(round(float(i) * float(wanted - 1) / 4.0))] = true
	var runite: Array[Vector2i] = []
	var adamant: Array[Vector2i] = []
	for i: int in wanted:
		if runite_at.has(i):
			runite.append(chosen[i])
		elif adamant.size() < 8:
			adamant.append(chosen[i])
	if runite.size() < 5 or adamant.size() < 8:
		push_error("not enough spaced slots: %d runite, %d adamant" % [runite.size(), adamant.size()])
		get_tree().quit(1)
		return
	for i: int in runite.size():
		print("MOVE RuniteVein%d = %d,%d" % [
			i + 1, runite[i].x * TILE + TILE / 2, runite[i].y * TILE + TILE / 2])
	for i: int in adamant.size():
		print("MOVE AdamantVein%d = %d,%d" % [
			i + 1, adamant[i].x * TILE + TILE / 2, adamant[i].y * TILE + TILE / 2])


func _rim_spec() -> MapKit.RimSpec:
	var spec := MapKit.RimSpec.new()
	spec.source = 0
	spec.fill = [Vector2i(4, 3)]
	spec.n = [Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)]
	spec.s = [Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6)]
	spec.w = [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5)]
	spec.e = [Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5)]
	spec.nw = Vector2i(2, 0)
	spec.ne = Vector2i(7, 0)
	spec.sw = Vector2i(2, 6)
	spec.se = Vector2i(7, 6)
	spec.s_face = [Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7)]
	spec.s_base = [Vector2i(3, 8), Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8)]
	spec.sw_face = Vector2i(2, 7)
	spec.sw_base = Vector2i(2, 8)
	spec.se_face = Vector2i(7, 7)
	spec.se_base = Vector2i(7, 8)
	spec.face_rows = 2
	return spec
