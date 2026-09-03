extends Node
## Choose where the six high-tier Farming patches go, and write the coordinates
## to tools/high_tier_herb_spots.json for tools/plant_high_tier_herbs.py to
## stamp into the map scenes.
##
##   godot --headless --path . --mode=client res://tools/pick_high_tier_herb_spots.tscn
##
## Runs as a SCENE, not `-s`: these maps contain hostile NPCs, and their script
## chain reaches the `Client` / `ClientState` autoloads. Under `-s` there are no
## autoloads, so every one of those scripts fails to compile and the map
## instantiates as a wreck with no tile layers to read. Same note
## tools/verify_herblore.gd carries.
##
## WHY THE PICKING IS DONE HERE AND THE PLANTING IN PYTHON
##
## Only Godot can answer "is this cell walkable" honestly: the answer lives in
## the TileSet's collision polygons, not in the atlas coordinates written to the
## .tscn, and a tile that LOOKS like floor can carry a polygon (that is the
## invisible-wall class of bug tools/audit_biome_collision.gd exists to catch).
## So the spatial reasoning runs against a loaded scene, exactly the way that
## audit does.
##
## The four target maps are all fully generator-authored — build_stub_biomes.gd
## writes Desert / Fire Forge / Sewers, build_starfall_mining_cave.gd writes the
## cave — but all four have been HAND-EDITED since (boss pads, zone music,
## wildlife, landmarks, the sewer sludge fix). Re-running a generator to add
## patches would throw that work away. So the planting is a TEXT insert into the
## existing scene, the same discipline tools/plant_farming_herbs.py already uses,
## and it stays in Python where the regex surgery belongs.
##
## PLACEMENT RULES
##
##   reachable   flood-filled from the Entrance warper, so no patch is stranded
##               behind a wall on an island of floor.
##   clearance   every cell in a 1-tile ring around the spot must also be open,
##               so a 32x32 herb sprite never half-buries itself in a rim.
##   spacing     spots are chosen greedily farthest-first, so a patch group
##               spreads across its zone instead of clumping at the entrance —
##               a clump is a single-player gather loop, not a shared one.
##   clear of    existing MineableNodes, hostiles, scene props and the warpers,
##               so a patch never lands on top of an ore vein or a boss pad.

const OUT_PATH := "res://tools/high_tier_herb_spots.json"

## map path -> the patches that grow there, in the order they are picked.
## `count` is per patch type. Six per type across a zone is the density the
## shipped mid-tier herbs use (Bandit Hideout runs 5-8 of each).
const PLAN: Array[Dictionary] = [
	{
		"map": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
		"key": "fire_forge",
		"patches": [
			{"slug": "rust_spore_cap", "prefix": "ForgeRustSpore", "count": 7},
			{"slug": "magma_root", "prefix": "ForgeMagmaRoot", "count": 7},
		],
	},
	{
		"map": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
		"key": "sewers",
		"patches": [
			{"slug": "nightshade_bramble", "prefix": "SewerNightshade", "count": 7},
			{"slug": "gloom_spore_cap", "prefix": "SewerGloomSpore", "count": 7},
		],
	},
	{
		"map": "res://source/common/gameplay/maps/maps/desert/desert.tscn",
		"key": "desert",
		"patches": [
			{"slug": "sun_lit_lotus", "prefix": "DesertSunLotus", "count": 8},
		],
	},
	{
		"map": "res://source/common/gameplay/maps/maps/starfall_mining_cave/starfall_mining_cave.tscn",
		"key": "starfall_mining_cave",
		"patches": [
			{"slug": "iron_spike_thorn", "prefix": "CaveIronSpike", "count": 8},
		],
	},
]

## Minimum pixels between a patch and any pre-existing node in the scene.
const CLEAR_OF_EXISTING_PX := 96.0
## Minimum pixels between two patches picked by this tool, across ALL types on
## the same map — Rust-Spore and Magma Root share the Forge and must not overlap.
const MIN_SPACING_PX := 260.0


func _ready() -> void:
	var out: Dictionary = {}
	var failures: int = 0
	for entry: Dictionary in PLAN:
		var picked: Dictionary = _pick_for_map(entry)
		if picked.is_empty():
			failures += 1
			continue
		out[String(entry["key"])] = picked
	if failures > 0:
		printerr("HERB_SPOTS_FAIL maps=", failures)
		get_tree().quit(1)
		return
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		printerr("could not write ", OUT_PATH)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(out, "  ") + "\n")
	file.close()
	print("HERB_SPOTS_OK -> ", OUT_PATH)
	get_tree().quit(0)


func _pick_for_map(entry: Dictionary) -> Dictionary:
	var path: String = String(entry["map"])
	var scene: PackedScene = load(path)
	if scene == null:
		printerr("could not load ", path)
		return {}
	var map: Node = scene.instantiate()

	var layers: Array[TileMapLayer] = []
	var tiles: Node = map.get_node_or_null("Tiles")
	if tiles != null:
		for child: Node in tiles.get_children():
			if child is TileMapLayer:
				layers.append(child as TileMapLayer)
	if layers.is_empty():
		printerr(path.get_file(), ": no TileMapLayers under Tiles")
		map.free()
		return {}

	# Blocked = any cell whose tile carries a collision polygon on ANY layer.
	# Used = any cell painted on any layer; unpainted space is the void outside
	# the map, which is not walkable either.
	var blocked: Dictionary = {}
	var used: Dictionary = {}
	for layer: TileMapLayer in layers:
		var ts: TileSet = layer.tile_set
		for cell: Vector2i in layer.get_used_cells():
			used[cell] = true
			var src := ts.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
			if src == null:
				continue
			var coords: Vector2i = layer.get_cell_atlas_coords(cell)
			if not src.has_tile(coords):
				continue
			var td: TileData = src.get_tile_data(
				coords, layer.get_cell_alternative_tile(cell)
			)
			if td != null and td.get_collision_polygons_count(0) > 0:
				blocked[cell] = true

	var tile_size: int = layers[0].tile_set.tile_size.x
	var entrance: Node2D = map.get_node_or_null("Entrance") as Node2D
	if entrance == null:
		printerr(path.get_file(), ": no Entrance warper to flood-fill from")
		map.free()
		return {}
	var start := Vector2i(
		int(floor(entrance.position.x / float(tile_size))),
		int(floor(entrance.position.y / float(tile_size)))
	)
	var reachable: Dictionary = _flood(start, blocked, used)
	if reachable.size() < 200:
		printerr(path.get_file(), ": only ", reachable.size(), " reachable cells")
		map.free()
		return {}

	# Existing occupied positions, so a patch never lands on an ore vein, a mob
	# spawn, a torch or a warper.
	var occupied: Array[Vector2] = []
	_collect_positions(map, occupied)

	# Candidates: reachable, with a clear 1-tile ring, and away from everything
	# already in the scene.
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in reachable:
		if not _has_clearance(cell, reachable):
			continue
		var world := Vector2(
			(cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size
		)
		var clear: bool = true
		for p: Vector2 in occupied:
			if world.distance_to(p) < CLEAR_OF_EXISTING_PX:
				clear = false
				break
		if clear:
			candidates.append(cell)
	# Deterministic order in, deterministic spots out: get_used_cells order is an
	# implementation detail, and a tool that shuffles every patch in the map on
	# each run is a tool nobody can review the diff of.
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return a.y < b.y if a.y != b.y else a.x < b.x
	)

	var total: int = 0
	for patch: Dictionary in entry["patches"]:
		total += int(patch["count"])
	var spots: Array[Vector2] = _spread(candidates, total, tile_size)
	if spots.size() < total:
		printerr(path.get_file(), ": only ", spots.size(), " spots for ", total,
			" patches (", candidates.size(), " candidates)")
		map.free()
		return {}

	# Deal the spread round-robin so two patch types on one map interleave across
	# the zone rather than each taking one half of it.
	var result: Dictionary = {}
	var patches: Array = entry["patches"]
	for patch: Dictionary in patches:
		result[String(patch["slug"])] = {
			"prefix": String(patch["prefix"]), "positions": [],
		}
	var i: int = 0
	while i < spots.size():
		var patch: Dictionary = patches[i % patches.size()]
		var bucket: Dictionary = result[String(patch["slug"])]
		if (bucket["positions"] as Array).size() < int(patch["count"]):
			(bucket["positions"] as Array).append([spots[i].x, spots[i].y])
		i += 1

	print(path.get_file(), ": reachable=", reachable.size(),
		" candidates=", candidates.size(), " placed=", total)
	for slug: String in result:
		print("   ", slug, " x", (result[slug]["positions"] as Array).size())
	map.free()
	return result


func _flood(start: Vector2i, blocked: Dictionary, used: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	if blocked.has(start) or not used.has(start):
		return seen
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var qi: int = 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cur + d
			if seen.has(n) or blocked.has(n) or not used.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return seen


## Every one of the eight neighbours must be walkable too. A herb sprite is drawn
## a full tile tall from its origin, so a spot flush against a rim reads as a
## plant growing out of the wall.
func _has_clearance(cell: Vector2i, reachable: Dictionary) -> bool:
	for dy: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			if not reachable.has(cell + Vector2i(dx, dy)):
				return false
	return true


## Farthest-point sampling: repeatedly take the candidate furthest from
## everything chosen so far. Gives an even spread over whatever shape the zone
## happens to be, without needing a hand-authored region per map.
func _spread(candidates: Array[Vector2i], want: int, tile_size: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if candidates.is_empty() or want <= 0:
		return out
	var points: Array[Vector2] = []
	for cell: Vector2i in candidates:
		points.append(Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size))
	# Seed with the candidate nearest the centroid, so the spread grows outward
	# from the middle of the zone rather than from an arbitrary corner.
	var centroid := Vector2.ZERO
	for p: Vector2 in points:
		centroid += p
	centroid /= float(points.size())
	var best: int = 0
	for i: int in points.size():
		if points[i].distance_squared_to(centroid) < points[best].distance_squared_to(centroid):
			best = i
	out.append(points[best])
	var taken: Dictionary = {best: true}

	while out.size() < want:
		var pick: int = -1
		var pick_dist: float = -1.0
		for i: int in points.size():
			if taken.has(i):
				continue
			var nearest: float = INF
			for chosen: Vector2 in out:
				nearest = minf(nearest, points[i].distance_squared_to(chosen))
			if nearest > pick_dist:
				pick_dist = nearest
				pick = i
		if pick < 0 or sqrt(pick_dist) < MIN_SPACING_PX:
			break
		taken[pick] = true
		out.append(points[pick])
	return out


## World positions of everything already placed in the scene, so patches keep
## clear of it. Warpers, portals, mobs, props, lights and existing gather nodes
## all count — anything a player can walk up to or that already owns that spot.
func _collect_positions(node: Node, out: Array[Vector2]) -> void:
	for child: Node in node.get_children():
		if child is TileMapLayer:
			continue
		if child is Node2D and child.get_parent() != null:
			out.append((child as Node2D).global_position)
		_collect_positions(child, out)
