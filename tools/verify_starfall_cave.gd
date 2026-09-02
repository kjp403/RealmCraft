extends Node
## Strict layout audit for the Starfall Mining Cave.
##
##   godot --path . --mode=client res://tools/verify_starfall_cave.tscn
##
## Scene mode, not `-s`: the map instances NPC/warper scenes that reach the
## Client autoloads a `-s` run does not provide.
##
## This checks the BUILT SCENE, not the generator's own bookkeeping. The
## generator reasons about a `blocked` dictionary; the player is stopped by
## TileSet collision polygons. Those are two different things and the whole
## point of this gate is that they agree — a wall the generator thinks is solid
## but that carries no polygon is a hole a player walks through, and it looks
## completely correct in a screenshot.
##
## What it refuses to ship:
##   * a vein inside rock, off the floor, or unreachable from the entrance
##   * an unreachable pocket of floor anywhere in the map
##   * a floating wall cell with no wall neighbour (the classic autotile hole)
##   * a walkable cell with no ground tile under it (background showing through)
##   * collision on the overhead Ceiling layer
##   * a vein whose approach is a 1-tile pinch, which is a two-player traffic jam
##   * veins closer than 1.5x GATHER_RANGE, where one click hits two nodes

const SCENE := "res://source/common/gameplay/maps/maps/starfall_mining_cave/starfall_mining_cave.tscn"
const TILE := 32
## HarvestController.GATHER_RANGE
const GATHER_RANGE := 48.0

var _bad: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _fail(msg: String) -> void:
	_bad += 1
	print("  FAIL ", msg)
	push_error(msg)


func _go() -> void:
	# A gate that hangs is worse than one that fails: if the scene will not
	# parse, say so and quit rather than sitting in the client forever.
	var packed: PackedScene = load(SCENE) as PackedScene
	if packed == null:
		_fail("%s failed to load — the scene text is malformed" % SCENE)
		print("STARFALL_CAVE bad=", _bad)
		get_tree().quit(1)
		return
	var root: Node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	var tiles: Node = root.get_node("Tiles")
	var ground: TileMapLayer = tiles.get_node("Ground") as TileMapLayer
	var walls: TileMapLayer = tiles.get_node("Walls") as TileMapLayer
	var props: TileMapLayer = tiles.get_node("Props") as TileMapLayer
	var ceiling: TileMapLayer = tiles.get_node("Ceiling") as TileMapLayer

	# --- solidity comes from the TILESET, not from any list this tool keeps ---
	var solid: Dictionary = {}
	for layer: TileMapLayer in [walls, props]:
		for cell: Vector2i in layer.get_used_cells():
			var data: TileData = layer.get_cell_tile_data(cell)
			if data != null and data.get_collision_polygons_count(0) > 0:
				solid[cell] = true

	# The overhead layer draws above the player and must never stop them.
	var ceiling_solid: int = 0
	for cell: Vector2i in ceiling.get_used_cells():
		var data: TileData = ceiling.get_cell_tile_data(cell)
		if data != null and data.get_collision_polygons_count(0) > 0:
			ceiling_solid += 1
	if ceiling_solid > 0:
		_fail("Ceiling layer has %d colliding tiles — it renders above the player" % ceiling_solid)

	# --- walkable = a ground tile with nothing solid on it ---
	var walk: Dictionary = {}
	for cell: Vector2i in ground.get_used_cells():
		if not solid.has(cell):
			walk[cell] = true

	# --- entrance + reachability ---
	var entrance_node: Node2D = root.get_node_or_null("Entrance") as Node2D
	if entrance_node == null:
		_fail("no Entrance warper")
		_finish(root)
		return
	var entrance := Vector2i(
		int(entrance_node.position.x) / TILE, int(entrance_node.position.y) / TILE
	)
	if not walk.has(entrance):
		_fail("Entrance at %s is not on walkable floor" % entrance)
	var reached := _flood(walk, entrance)
	if reached.size() != walk.size():
		_fail("unreachable floor: %d of %d cells cannot be walked to from the entrance"
			% [walk.size() - reached.size(), walk.size()])

	# --- floating wall segments ---
	var floating: int = 0
	for cell: Vector2i in walls.get_used_cells():
		var touching: bool = false
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if walls.get_cell_source_id(cell + step) >= 0:
				touching = true
				break
		if not touching:
			floating += 1
	if floating > 0:
		_fail("%d floating wall cells with no wall neighbour" % floating)

	# --- background bleed: every walkable cell needs ground under it ---
	var bleed: int = 0
	for cell: Vector2i in walk.keys():
		if ground.get_cell_source_id(cell) < 0:
			bleed += 1
	if bleed > 0:
		_fail("%d walkable cells have no Ground tile — background shows through" % bleed)

	# --- veins ---
	var veins: Array[Node] = []
	for node: Node in root.get_node("MineableNodes").get_children():
		veins.append(node)
	var by_tier: Dictionary = {}
	var pinched: int = 0
	for node: Node in veins:
		var pos: Vector2 = (node as Node2D).position
		var cell := Vector2i(int(pos.x) / TILE, int(pos.y) / TILE)
		var tier: String = str(node.name).replace("Vein", "").rstrip("0123456789")
		by_tier[tier] = int(by_tier.get(tier, 0)) + 1
		if solid.has(cell):
			_fail("%s is inside rock at %s" % [node.name, cell])
			continue
		if not walk.has(cell):
			_fail("%s at %s is not on walkable floor" % [node.name, cell])
			continue
		if not reached.has(cell):
			_fail("%s at %s is unreachable from the entrance" % [node.name, cell])
			continue
		var open: int = 0
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if walk.has(cell + step):
				open += 1
		if open < 3:
			_fail("%s at %s has only %d open sides — players will block each other"
				% [node.name, cell, open])
		# A vein reachable only through a 1-tile pinch is a traffic jam. Remove
		# each neighbouring cell in turn; if that cuts the vein off, it is one.
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var gate: Vector2i = cell + step
			if not walk.has(gate):
				continue
			var without: Dictionary = walk.duplicate()
			without.erase(gate)
			if without.has(entrance) and not _flood(without, entrance).has(cell):
				pinched += 1
				_fail("%s is reachable only through the single cell %s" % [node.name, gate])
				break

	# --- spacing ---
	var closest: float = 1e9
	var pair: String = ""
	for i: int in veins.size():
		for j: int in range(i + 1, veins.size()):
			var d: float = (veins[i] as Node2D).position.distance_to((veins[j] as Node2D).position)
			if d < closest:
				closest = d
				pair = "%s <-> %s" % [veins[i].name, veins[j].name]
	if closest <= GATHER_RANGE * 1.5:
		_fail("veins %s are %.0fpx apart; one click would hit both" % [pair, closest])

	# --- the way home ---
	var portal: Node2D = root.get_node_or_null("GrovePortal") as Node2D
	if portal == null:
		_fail("no GrovePortal — players cannot leave")
	elif not walk.has(Vector2i(int(portal.position.x) / TILE, int(portal.position.y) / TILE)):
		_fail("GrovePortal is not on walkable floor")

	print("floor=%d reachable=%d solid=%d ceiling=%d(0 solid) veins=%d closest=%.0fpx pinched=%d" % [
		walk.size(), reached.size(), solid.size(), ceiling.get_used_cells().size(),
		veins.size(), closest, pinched,
	])
	var tiers: Array = by_tier.keys()
	tiers.sort()
	for tier: String in tiers:
		print("  %-10s %d veins" % [tier, int(by_tier[tier])])
	_finish(root)


func _finish(root: Node) -> void:
	print("STARFALL_CAVE bad=", _bad)
	if _bad == 0:
		print("VERIFY_PASS starfall_cave")
	root.free()
	get_tree().quit(0)


func _flood(walk: Dictionary, start: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	if not walk.has(start):
		return seen
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next: Vector2i = cell + step
			if walk.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen
