extends SceneTree
## Build Desert / Fire Forge / Sewers with the shared map toolkit.
##
## Layouts are organic masks, wall rims resolve from neighbours, ground blends
## and props come from verified atlas rectangles. No hand-stamped rectangles.
##   godot --headless --path . -s tools/build_stub_biomes.gd

const MapKit := preload("res://tools/lib/mapkit.gd")

const DESERT_TS := "res://source/common/gameplay/maps/tilesets/desert_tileset.tres"
const FORGE_TS := "res://source/common/gameplay/maps/tilesets/fire_forge_tileset.tres"
const SEWERS_TS := "res://source/common/gameplay/maps/tilesets/sewers_tileset.tres"

const WARPER := "res://source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn"
const PORTAL := "res://source/common/gameplay/maps/components/interaction_areas/warper/portal/portal.tscn"
const HUB := "res://source/common/gameplay/maps/instance/instance_collection/overworld.tres"
const CAMP := "res://source/common/gameplay/lighting/campfire.tscn"
const GLOW := "res://source/common/gameplay/lighting/light_radial.tres"
const MAP_SCRIPT := "res://source/common/gameplay/maps/map.gd"
const RP_SCRIPT := "res://source/common/network/sync/replicated_props.gd"
const CRITTER_SCN := "res://source/common/gameplay/props/ambient_critter.tscn"
const DECO_SCN := "res://source/common/gameplay/props/animated_deco.tscn"
const HOSTILE_SCN := "res://source/common/gameplay/characters/npc/hostile_npc.tscn"
const TYPES := "res://source/common/gameplay/characters/npc/types/"

var W: int = 64
var H: int = 48
var _bounds := Rect2i(0, 0, 64, 48)


# --- Surface map world scale --------------------------------------------------
#
# All three surface maps share it. 2x, not 3x: at 3x a screen holds one
# material and one torch, which needs an authored content pass, not a knob.
#
# Layout coordinates multiply; atlas cells never do, which is why the tiling
# looks the same at any scale — every tile is chosen either from its neighbours
# or from a per-cell hash, and neither knows how big the map is.

const SURFACE_S := 2

## Wobble has to be bumped, not just carried. `MapKit.blob` samples its wobble on
## the unit circle and `MapKit.tunnel` parameterises wander by t, so a scaled
## cavern otherwise keeps the *same number of lobes*, each S times longer, and
## reads rounder and lazier than the 1x map did.
const SURFACE_WOBBLE := 1.3


func _sc(x: int, y: int) -> Vector2i:
	return Vector2i(x * SURFACE_S, y * SURFACE_S)


func _sr(v: float) -> float:
	return v * float(SURFACE_S)


func _sn(n: int) -> int:
	return n * SURFACE_S


func _sw(w: float) -> float:
	# Capped: past ~0.45 the outline stops reading as rock and starts fraying.
	return minf(w * SURFACE_WOBBLE, 0.45)


## Hazard radii scale by sqrt(S), not S.
##
## Rooms and corridors are read at map scale, so they scale linearly. A lava
## pool is read at *screen* scale: scaled linearly at 3x the central Forge pool
## stopped being a thing you walk around and became a wall of orange filling the
## viewport, with the lava tiles' horizontal seams banding across it. sqrt keeps
## it a landmark in a bigger room instead of a room-sized hazard.
func _sh(v: float) -> float:
	return v * sqrt(float(SURFACE_S))


func _initialize() -> void:
	_build_desert()
	_build_fire_forge()
	_build_sewers()
	print("STUB_BIOMES_PASS")
	quit(0)


func _set_size(w: int, h: int) -> void:
	W = w
	H = h
	_bounds = Rect2i(0, 0, w, h)


func _b64(layer: TileMapLayer) -> String:
	return Marshalls.raw_to_base64(layer.tile_map_data)


func _tile_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 16 + 8, cell.y * 16 + 8)


func _pick_open(mask: Dictionary, wanted: Vector2i) -> Vector2i:
	if mask.has(wanted):
		return wanted
	var best := wanted
	var best_d := 1 << 30
	for cell: Vector2i in mask.keys():
		var d: int = (cell - wanted).length_squared()
		if d < best_d:
			best_d = d
			best = cell
	return best


## Shared shaping: chambers joined by wandering tunnels, smoothed, trimmed to a
## solid margin, and reduced to the single region containing `anchor`.
func _carve(chambers: Array, links: Array, margin: int, anchor: Vector2i) -> Dictionary:
	var mask: Dictionary = {}
	for ch in chambers:
		MapKit.blob(mask, ch[0], ch[1], ch[2], int(ch[3]), _bounds)
	for link in links:
		MapKit.tunnel(mask, link[0], link[1], link[2], link[3], int(link[4]), _bounds)
	var trimmed: Dictionary = {}
	for cell: Vector2i in mask.keys():
		if (
			cell.x >= margin and cell.y >= margin + 2
			and cell.x < W - margin and cell.y < H - margin
		):
			trimmed[cell] = true
	var smoothed := MapKit.smooth(trimmed, _bounds, 2, 5, 4)
	return MapKit.largest_region(smoothed, _pick_open(smoothed, anchor))


func _void_of(floor_mask: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for y in H:
		for x in W:
			var cell := Vector2i(x, y)
			if not floor_mask.has(cell):
				out[cell] = true
	return out


func _walkable(floor_mask: Dictionary, blocked: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in floor_mask.keys():
		if not blocked.has(cell):
			out[cell] = true
	return out


func _rim(
	source: int,
	fill: Array,
	n: Array,
	s: Array,
	w: Array,
	e: Array,
	nw: Vector2i,
	ne: Vector2i,
	sw: Vector2i,
	se: Vector2i
) -> MapKit.RimSpec:
	var spec := MapKit.RimSpec.new()
	spec.source = source
	spec.fill.assign(fill)
	spec.n.assign(n)
	spec.s.assign(s)
	spec.w.assign(w)
	spec.e.assign(e)
	spec.nw = nw
	spec.ne = ne
	spec.sw = sw
	spec.se = se
	spec.face_rows = 0
	return spec


func _scatter_props(
	props: TileMapLayer,
	source: int,
	cells: Array,
	rects: Array,
	density: float,
	spacing: int,
	seed_value: int,
	allowed: Dictionary,
	solid: Dictionary
) -> void:
	if rects.is_empty():
		return
	for cell in MapKit.scatter(cells, density, spacing, seed_value):
		if not allowed.has(cell):
			continue
		var r: Array = rects[MapKit.hash2(cell.x, cell.y, seed_value + 1) % rects.size()]
		var cluster := MapKit.rect_cluster(r[0], r[1], r[2], r[3])
		var placed := MapKit.stamp_cluster(props, source, cluster, cell, allowed, _bounds)
		for c: Vector2i in placed:
			allowed.erase(c)
			solid[c] = true


# --- Population --------------------------------------------------------------

## Place one entry on the nearest free walkable cell to its authored spot,
## reserving `gap` cells around it so packs never stack on each other or on a
## warper.
func _place(walk: Dictionary, taken: Dictionary, wanted: Vector2i, gap: int) -> Vector2i:
	var pool: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not taken.has(cell):
			pool[cell] = true
	if pool.is_empty():
		return wanted
	var cell := _pick_open(pool, wanted)
	for oy in range(-gap, gap + 1):
		for ox in range(-gap, gap + 1):
			taken[cell + Vector2i(ox, oy)] = true
	return cell


## Expand a pack plan into hostiles. Entries are
## `[base_name, type_slug, spot, count]`; a count above one spreads that many of
## the same type around the spot, which is how a zone this size gets populated
## without a hand-written line per body.
func _mobs(walk: Dictionary, taken: Dictionary, plan: Array, gap: int) -> Array:
	var out: Array = []
	for entry: Array in plan:
		var base: String = entry[0]
		var slug: String = entry[1]
		var spot: Vector2i = entry[2]
		var count: int = int(entry[3]) if entry.size() > 3 else 1
		for i in count:
			var cell := _place(walk, taken, spot, gap)
			out.append({
				"name": base if i == 0 else "%s%d" % [base, i + 1],
				"type": TYPES + slug + ".tres",
				"pos": _tile_pos(cell),
			})
	return out


## Props that must not block movement (flat ground detail).
func _scatter_flat(
	props: TileMapLayer,
	source: int,
	cells: Array,
	tiles: Array,
	density: float,
	spacing: int,
	seed_value: int,
	taken: Dictionary
) -> void:
	if tiles.is_empty():
		return
	for cell in MapKit.scatter(cells, density, spacing, seed_value):
		if taken.has(cell) or props.get_cell_source_id(cell) >= 0:
			continue
		var t: Array = tiles[MapKit.hash2(cell.x, cell.y, seed_value + 2) % tiles.size()]
		props.set_cell(cell, source, Vector2i(t[0], t[1]))


# --- Sewers -----------------------------------------------------------------
# Flooded cisterns joined by winding culverts, cut from the pixel-dungeon room
# template: rows 1-2 are floor, row 0 the north wall, row 4 the south wall.

func _build_sewers() -> void:
	_set_size(_sn(112), _sn(84))
	var ts: TileSet = load(SEWERS_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts

	var entrance_hint := _sc(56, 72)
	var floor_mask := _carve(
		[
			[_sc(56, 71), _sr(9.0), _sw(0.26), 11],
			[_sc(48, 62), _sr(6.5), _sw(0.30), 12],
			[_sc(64, 62), _sr(6.5), _sw(0.30), 13],
			[_sc(24, 50), _sr(9.5), _sw(0.26), 14],
			[_sc(88, 50), _sr(9.5), _sw(0.26), 15],
			[_sc(56, 44), _sr(10.0), _sw(0.24), 16],
			[_sc(30, 24), _sr(9.0), _sw(0.28), 17],
			[_sc(82, 24), _sr(9.0), _sw(0.28), 18],
			[_sc(56, 16), _sr(8.0), _sw(0.28), 19],
		],
		[
			[_sc(56, 64), _sc(56, 54), _sr(2.6), _sr(2.5), 31],
			[_sc(50, 60), _sc(30, 52), _sr(2.2), _sr(3.0), 32],
			[_sc(62, 60), _sc(82, 52), _sr(2.2), _sr(3.0), 33],
			[_sc(26, 44), _sc(30, 32), _sr(2.2), _sr(3.0), 34],
			[_sc(86, 44), _sc(82, 32), _sr(2.2), _sr(3.0), 35],
			[_sc(36, 22), _sc(50, 17), _sr(2.2), _sr(2.5), 36],
			[_sc(76, 22), _sc(62, 17), _sr(2.2), _sr(2.5), 37],
			[_sc(48, 42), _sc(34, 28), _sr(2.0), _sr(3.5), 38],
			[_sc(64, 42), _sc(78, 28), _sr(2.0), _sr(3.5), 39],
		],
		_sn(4),
		entrance_hint
	)

	var floors := [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
	]
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, 0, MapKit._pick(floors, cell, 41))

	var void_mask := _void_of(floor_mask)
	var spec := _rim(
		0,
		[Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0), Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)],
		[Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)],
		[Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)],
		[Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3)],
		Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 4), Vector2i(5, 4)
	)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 0, Vector2i(7, 0))
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, spec, _bounds, blocked)

	var walk := _walkable(floor_mask, blocked)
	var entrance := _pick_open(walk, entrance_hint)
	walk = MapKit.largest_region(walk, entrance)
	var portal := _pick_open(walk, entrance + Vector2i(0, _sn(5)))

	var keepout: Dictionary = {}
	for spot in [entrance, portal]:
		for oy in range(-3, 4):
			for ox in range(-3, 4):
				keepout[spot + Vector2i(ox, oy)] = true

	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not keepout.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	# Brick pillars and rubble against the culvert walls.
	_scatter_props(props, 0, edges, [[6, 4, 1, 2], [7, 4, 1, 2], [8, 4, 1, 2]], 0.16, 4, 71, free, solid)
	_scatter_props(props, 0, inner, [[6, 3, 1, 1], [7, 3, 1, 1], [8, 3, 1, 1]], 0.05, 6, 72, free, solid)
	_scatter_flat(props, 0, inner, [[9, 4], [9, 5], [7, 7], [8, 6]], 0.07, 3, 73, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	var decos: Array = []
	var ti := 0
	for spot in [
		_sc(24, 50), _sc(88, 50), _sc(56, 44), _sc(30, 24),
		_sc(82, 24), _sc(56, 16), _sc(48, 62), _sc(64, 62),
		_sc(56, 71),
		# The authored list has to grow with the span or the culverts go dark.
		_sc(56, 54), _sc(40, 56), _sc(72, 56), _sc(27, 37), _sc(85, 37),
		_sc(40, 22), _sc(72, 22), _sc(56, 30), _sc(56, 62), _sc(20, 50),
		_sc(92, 50), _sc(44, 44), _sc(68, 44),
	]:
		var cell := _pick_open(walk, spot)
		ti += 1
		decos.append({
			"name": "SewerTorch%d" % ti,
			"frames": "deco_torch" if ti % 3 != 0 else "deco_candle_a",
			"pos": _tile_pos(cell),
			"scale": 1.4,
			"light": 0.95,
			"color": "Color(0.55, 0.95, 0.6, 1)" if ti % 3 == 0 else "Color(1, 0.72, 0.38, 1)",
		})

	# --- Population ----------------------------------------------------------
	# Banded to the instance's 15-20 gate: the sewer-family types only. The
	# Bloated Sovereign holds the north cistern, the chamber furthest from the
	# hub portal, with a wide keepout so it never leashes into a trash pack.
	var boss_cell := _place(walk, {}, _sc(56, 16), 0)
	var world_cell := _place(walk, {}, _sc(88, 22), 0)
	var taken: Dictionary = {}
	for spot in [entrance, portal]:
		for oy in range(-_sn(6), _sn(6) + 1):
			for ox in range(-_sn(6), _sn(6) + 1):
				taken[spot + Vector2i(ox, oy)] = true
	for spot in [boss_cell, world_cell]:
		for oy in range(-_sn(9), _sn(9) + 1):
			for ox in range(-_sn(9), _sn(9) + 1):
				taken[spot + Vector2i(ox, oy)] = true
	var hostiles := _mobs(walk, taken, [
		["Slime", "trpg/trpg_slime", _sc(48, 62), 3],
		["SlimeE", "trpg/trpg_slime", _sc(64, 62), 3],
		["Bat", "trpg/trpg_bat", _sc(24, 50), 3],
		["BatE", "trpg/trpg_bat", _sc(88, 50), 3],
		["SewerSkeleton", "trpg/trpg_sewer_skeleton", _sc(56, 44), 3],
		["AcidOoze", "trpg/trpg_acid_ooze", _sc(30, 24), 2],
		["AcidOozeE", "trpg/trpg_acid_ooze", _sc(82, 24), 2],
		["Crawler", "trpg/trpg_carrion_crawler", _sc(38, 40), 2],
		["CrawlerE", "trpg/trpg_carrion_crawler", _sc(74, 40), 2],
		["ZombieGiant", "trpg/trpg_zombie_giant", _sc(30, 34), 2],
		["ZombieGiantE", "trpg/trpg_zombie_giant", _sc(82, 34), 2],
		["SewerGorgon", "trpg/trpg_sewer_gorgon", _sc(44, 30), 2],
		["SewerGorgonE", "trpg/trpg_sewer_gorgon", _sc(68, 30), 2],
		["Devourer", "trpg/trpg_intellect_devourer", _sc(56, 34), 2],
		["CisternHulk", "trpg/trpg_cistern_hulk", _sc(56, 24), 2],
	], _sn(5))
	hostiles.append({
		"name": "UnboundSovereign",
		"type": TYPES + "bosses/cistern_sovereign_world.tres",
		"pos": _tile_pos(world_cell),
	})

	assert(walk.has(entrance) and walk.has(portal), "sewers spawn blocked")
	assert(walk.size() > 900 * SURFACE_S * SURFACE_S, "sewers too small: %d" % walk.size())
	print("sewers walk=", walk.size(), " floor=", floor_mask.size())

	_write_map({
		"root": "sewers",
		"out": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
		"tileset": SEWERS_TS,
		"bg": "Color(0.015, 0.025, 0.02, 1)",
		"modulate": "Color(0.72, 0.82, 0.74, 1)",
		"music": "res://assets/audio/music/alone.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"critters": [],
		"decos": decos,
		"hostiles": hostiles,
		"entrance": _tile_pos(entrance),
		"portal": _tile_pos(portal),
		"entrance_id": 28,
		"portal_id": 128,
		"portal_color": "Color(0, 0.53, 0.27, 1)",
		"walk_count": walk.size(),
		"wall_count": walls.get_used_cells().size(),
		"prop_count": props.get_used_cells().size(),
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
		"lights": "",
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [
				str(_tile_pos(entrance + _sc(2, -2)).x),
				str(_tile_pos(entrance + _sc(2, -2)).y),
			]
		),
	})


# --- Fire Forge -------------------------------------------------------------
# Foundry halls cut into rock, walled with the DG Fire masonry ring (cols 1-4,
# rows 1-3) and pooled with lava from the 16x16 lava pack.

func _build_fire_forge() -> void:
	_set_size(_sn(112), _sn(84))
	var ts: TileSet = load(FORGE_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts

	var entrance_hint := _sc(56, 72)
	var bays: Array[Vector2i] = [
		_sc(56, 71), _sc(56, 60), _sc(26, 52), _sc(86, 52),
		_sc(56, 42), _sc(24, 24), _sc(88, 24), _sc(56, 18),
	]
	var links: Array = [
		[_sc(56, 64), _sc(56, 52), _sr(2.8), _sr(2.0), 61],
		[_sc(48, 58), _sc(30, 54), _sr(2.4), _sr(3.0), 62],
		[_sc(64, 58), _sc(82, 54), _sr(2.4), _sr(3.0), 63],
		[_sc(28, 44), _sc(26, 32), _sr(2.4), _sr(3.0), 64],
		[_sc(84, 44), _sc(86, 32), _sr(2.4), _sr(3.0), 65],
		[_sc(32, 20), _sc(48, 18), _sr(2.4), _sr(2.5), 66],
		[_sc(80, 20), _sc(64, 18), _sr(2.4), _sr(2.5), 67],
		[_sc(50, 38), _sc(34, 28), _sr(2.2), _sr(3.5), 68],
		[_sc(62, 38), _sc(78, 28), _sr(2.2), _sr(3.5), 69],
	]
	var floor_mask := _carve(
		[
			[_sc(56, 71), _sr(8.5), _sw(0.26), 51],
			[_sc(56, 60), _sr(7.0), _sw(0.28), 52],
			[_sc(26, 52), _sr(9.0), _sw(0.26), 53],
			[_sc(86, 52), _sr(9.0), _sw(0.26), 54],
			[_sc(56, 42), _sr(10.0), _sw(0.24), 55],
			[_sc(24, 24), _sr(9.0), _sw(0.28), 56],
			[_sc(88, 24), _sr(9.0), _sw(0.28), 57],
			[_sc(56, 18), _sr(8.5), _sw(0.26), 58],
		],
		links,
		_sn(4),
		entrance_hint
	)

	var void_mask := _void_of(floor_mask)
	# DG Fire masonry: the ring sits at cols 1-4 / rows 1-3, not at row 0.
	var spec := _rim(
		3,
		[Vector2i(2, 2), Vector2i(3, 2)],
		[Vector2i(2, 1), Vector2i(3, 1)],
		[Vector2i(2, 3), Vector2i(3, 3)],
		[Vector2i(1, 2)],
		[Vector2i(4, 2)],
		Vector2i(1, 1), Vector2i(4, 1), Vector2i(1, 3), Vector2i(4, 3)
	)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 3, Vector2i(2, 2))
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, spec, _bounds, blocked)

	var walk := _walkable(floor_mask, blocked)
	var entrance := _pick_open(walk, entrance_hint)
	walk = MapKit.largest_region(walk, entrance)
	var portal := _pick_open(walk, entrance + Vector2i(0, _sn(5)))

	# Lava pools sunk into the foundry floors — hazards, not decoration.
	var lava_cells: Dictionary = {}
	for spot in [
		[_sc(24, 24), _sh(4.0), 81], [_sc(88, 24), _sh(4.0), 82],
		[_sc(26, 52), _sh(3.6), 83], [_sc(86, 52), _sh(3.6), 84],
		[_sc(56, 42), _sh(4.4), 85],
	]:
		var pool: Dictionary = {}
		MapKit.blob(pool, spot[0], spot[1], _sw(0.30), int(spot[2]), _bounds)
		pool = MapKit.smooth(pool, _bounds, 1, 5, 4)
		for cell: Vector2i in pool.keys():
			if walk.has(cell):
				lava_cells[cell] = true
	# --- Floor ---------------------------------------------------------------
	# Painted now rather than straight after the carve, because where the lava
	# ends up decides where the ash apron goes and where a work plate must not.
	# See `tools/lib/forgefloor.gd`: the DG Fire bank this used to fill with is
	# six copies of one flat colour.

	# Haul roads: the same tunnel shapes the carver used, re-rasterised narrower.
	# Deriving them from the links instead of drawing straight lines guarantees
	# every road stays inside the corridor it belongs to. The aprons stay well
	# inside the chambers — the point of paving is that a player can see where it
	# goes, and it cannot do that if it is everywhere.
	var paved: Dictionary = {}
	for link: Array in links:
		MapKit.tunnel(paved, link[0], link[1], float(link[2]) * 0.45, float(link[3]), int(link[4]), _bounds)
	for bay: Vector2i in bays:
		ForgeFloor.apron(paved, bay, _sn(3))
	ForgeFloor.apron(paved, entrance, _sn(5))
	ForgeFloor.apron(paved, portal, _sn(3))
	for cell: Vector2i in lava_cells.keys():
		paved.erase(cell)

	var scorch := ForgeFloor.scorch_of(lava_cells, floor_mask, 3)
	var depth := ForgeFloor.depth_field(floor_mask)
	var owned: Dictionary = {}

	# Features first so they can claim their cells before the fills run. Work
	# plates sit off-centre in the bays that hold a lava pool, on centre in the
	# ones that do not; the casting pits go where the haul roads meet.
	# At 3x a single 3x3 stamp is lost in the room, so the plates go down as
	# clusters of three offset by a plate width — the only honest way to make a
	# fixed-size landmark hold a scaled space without new art.
	for spot in [
		_sc(56, 60), _sc(30, 48), _sc(82, 48),
		_sc(50, 38), _sc(28, 20), _sc(84, 20), _sc(56, 15),
	]:
		for offset in [Vector2i(0, 0), Vector2i(4, 3), Vector2i(-4, 3)]:
			for cell: Vector2i in ForgeFloor.hearth(ground, floor_mask, _pick_open(walk, spot + offset)).keys():
				owned[cell] = true
	for spot in [_sc(32, 52), _sc(80, 52), _sc(56, 66)]:
		var pit := _pick_open(walk, spot)
		var placed := ForgeFloor.mold_pit(ground, floor_mask, pit)
		if placed.is_empty():
			continue
		for cell: Vector2i in placed.keys():
			owned[cell] = true
		walk.erase(pit)

	for cell: Vector2i in owned.keys():
		paved.erase(cell)
	for cell: Vector2i in ForgeFloor.pave(ground, paved, floor_mask, depth, 72, 0.28, float(SURFACE_S)).keys():
		owned[cell] = true
	ForgeFloor.paint_slate(ground, floor_mask, depth, 71, {
		"scorch": scorch, "skip": owned, "unit": float(SURFACE_S),
	})

	# Textured lava: the flat fill tile reads as a solid orange shape.
	var lava_tiles := [Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11)]
	for cell: Vector2i in lava_cells.keys():
		ground.set_cell(cell, 0, MapKit._pick(lava_tiles, cell, 86))
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	var keepout: Dictionary = {}
	for spot in [entrance, portal]:
		for oy in range(-3, 4):
			for ox in range(-3, 4):
				keepout[spot + Vector2i(ox, oy)] = true

	var blocked_all := blocked.duplicate()
	for cell: Vector2i in lava_cells.keys():
		blocked_all[cell] = true
	var edges := MapKit.edge_cells(walk, blocked_all)
	var inner := MapKit.interior_cells(walk, blocked_all, 3)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not keepout.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	_scatter_props(props, 3, edges, [[8, 5, 1, 1], [9, 5, 1, 1], [10, 5, 1, 1]], 0.14, 4, 91, free, solid)
	_scatter_props(props, 2, inner, [[1, 0, 1, 1], [2, 0, 1, 1]], 0.05, 6, 92, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	# Slag and broken stone swept against the walls. Flat, non-blocking, and
	# sparse: this is wear on the floor, not another prop pass.
	for cell in MapKit.scatter(edges, 0.11, 3, 93):
		if solid.has(cell) or props.get_cell_source_id(cell) >= 0:
			continue
		props.set_cell(cell, ForgeFloor.SOURCE, MapKit._pick(ForgeFloor.RUBBLE, cell, 94))

	# Torches are an authored list, so the list itself has to grow with the map:
	# carrying the original eight across 3x the span leaves the corridors between
	# bays completely unlit.
	var decos: Array = []
	var ti := 0
	for spot in [
		_sc(24, 24), _sc(88, 24), _sc(56, 18), _sc(56, 42),
		_sc(26, 52), _sc(86, 52), _sc(56, 60), _sc(56, 71),
		# Bay mouths and corridor midpoints.
		_sc(56, 52), _sc(56, 66), _sc(40, 56), _sc(72, 56),
		_sc(27, 38), _sc(85, 38), _sc(40, 22), _sc(72, 22),
		_sc(42, 34), _sc(70, 34), _sc(56, 30), _sc(20, 52),
		_sc(92, 52), _sc(20, 24), _sc(92, 24), _sc(48, 44),
		_sc(64, 44), _sc(48, 64), _sc(64, 64),
	]:
		var cell := _pick_open(walk, spot)
		ti += 1
		decos.append({
			"name": "ForgeTorch%d" % ti,
			"frames": "deco_forge_torch",
			"pos": _tile_pos(cell),
			"scale": 1.3,
			"light": 0.7,
			"color": "Color(1, 0.55, 0.2, 1)",
		})

	var lights := ""
	var li := 0
	for cell: Vector2i in lava_cells.keys():
		# Every ~9th lava cell at 1x. Lava area grows with S^2, so the divisor
		# grows with it or the pools turn into one blown-out white blob.
		if MapKit.hash2(cell.x, cell.y, 95) % (29 * SURFACE_S * SURFACE_S) != 0:
			continue
		li += 1
		var p := _tile_pos(cell)
		lights += (
			"\n[node name=\"LavaGlow%d\" type=\"PointLight2D\" parent=\"SceneProps\"]\n" % li
			+ "position = Vector2(%s, %s)\n" % [str(p.x), str(p.y)]
			+ "color = Color(1, 0.4, 0.12, 1)\nenergy = 0.7\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.3\n"
		)

	# --- Population ----------------------------------------------------------
	# Banded to the instance's 30-35 gate. Vurthek holds the north foundry, the
	# chamber furthest from the hub portal.
	var boss_cell := _place(walk, {}, _sc(56, 18), 0)
	var world_cell := _place(walk, {}, _sc(88, 24), 0)
	var taken: Dictionary = {}
	for spot in [entrance, portal]:
		for oy in range(-_sn(6), _sn(6) + 1):
			for ox in range(-_sn(6), _sn(6) + 1):
				taken[spot + Vector2i(ox, oy)] = true
	for spot in [boss_cell, world_cell]:
		for oy in range(-_sn(9), _sn(9) + 1):
			for ox in range(-_sn(9), _sn(9) + 1):
				taken[spot + Vector2i(ox, oy)] = true
	var hostiles := _mobs(walk, taken, [
		["ArmoredAxeman", "trpg/trpg_armored_axeman", _sc(56, 60), 3],
		["Swordsman", "trpg/trpg_swordsman", _sc(44, 58), 2],
		["Knight", "trpg/trpg_knight", _sc(68, 58), 2],
		["ArmoredOrc", "trpg/trpg_armored_orc", _sc(26, 52), 3],
		["ArmoredOrcE", "trpg/trpg_armored_orc", _sc(86, 52), 3],
		["GreatswordSkeleton", "trpg/trpg_greatsword_skeleton", _sc(34, 44), 2],
		["GreatswordSkeletonE", "trpg/trpg_greatsword_skeleton", _sc(78, 44), 2],
		["Wizard", "trpg/trpg_wizard", _sc(44, 40), 2],
		["WizardE", "trpg/trpg_wizard", _sc(68, 40), 2],
		["EliteOrc", "trpg/trpg_elite_orc", _sc(56, 42), 3],
		["KnightTemplar", "trpg/trpg_knight_templar", _sc(24, 24), 2],
		["KnightTemplarE", "trpg/trpg_knight_templar", _sc(88, 24), 2],
		["Demon", "trpg/trpg_demon_a", _sc(34, 32), 2],
		["DemonE", "trpg/trpg_demon_a", _sc(78, 32), 2],
		["ConjuringOni", "trpg/trpg_conjuring_oni", _sc(40, 22), 2],
		["UmberHulk", "trpg/trpg_umber_hulk", _sc(72, 22), 2],
		["CinderFomorian", "trpg/trpg_cinder_fomorian", _sc(56, 30), 2],
	], _sn(5))
	hostiles.append({
		"name": "UnboundCinderborn",
		"type": TYPES + "bosses/cinderborn_world.tres",
		"pos": _tile_pos(world_cell),
	})

	assert(walk.has(entrance) and walk.has(portal), "forge spawn blocked")
	assert(walk.size() > 900 * SURFACE_S * SURFACE_S, "forge too small: %d" % walk.size())
	print("forge walk=", walk.size(), " lava=", lava_cells.size())

	_write_map({
		"root": "fire_forge",
		"out": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
		"tileset": FORGE_TS,
		"bg": "Color(0.04, 0.015, 0.012, 1)",
		"modulate": "Color(0.82, 0.74, 0.72, 1)",
		"music": "res://assets/audio/music/attack_2.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"critters": [],
		"decos": decos,
		"hostiles": hostiles,
		"entrance": _tile_pos(entrance),
		"portal": _tile_pos(portal),
		"entrance_id": 26,
		"portal_id": 126,
		"portal_color": "Color(0.74, 0.25, 0, 1)",
		"walk_count": walk.size(),
		"wall_count": walls.get_used_cells().size(),
		"prop_count": props.get_used_cells().size(),
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
		"lights": lights,
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [
				str(_tile_pos(entrance + _sc(2, -2)).x),
				str(_tile_pos(entrance + _sc(2, -2)).y),
			]
		),
	})


# --- Desert -----------------------------------------------------------------
# Open sand basin ringed by mesa cliffs, with rock outcrops standing in the
# middle. The cliff art hangs two rows below its cell, so face_rows = 2.
# Dune Scout Ilka is hand-placed at the entrance in desert.tscn (greeter for
# The Builders' Grave). Rebuilds of this map must keep her next to the campfire.

func _build_desert() -> void:
	_set_size(_sn(104), _sn(76))
	var ts: TileSet = load(DESERT_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts

	var entrance_hint := _sc(52, 64)
	var floor_mask := _carve(
		[
			[_sc(52, 63), _sr(10.0), _sw(0.24), 101],
			[_sc(52, 50), _sr(12.0), _sw(0.22), 102],
			[_sc(26, 44), _sr(10.0), _sw(0.26), 103],
			[_sc(78, 44), _sr(10.0), _sw(0.26), 104],
			[_sc(52, 32), _sr(12.0), _sw(0.22), 105],
			[_sc(24, 20), _sr(9.0), _sw(0.28), 106],
			[_sc(80, 20), _sr(9.0), _sw(0.28), 107],
			[_sc(52, 16), _sr(9.0), _sw(0.26), 108],
		],
		[
			[_sc(52, 56), _sc(52, 44), _sr(3.2), _sr(2.0), 111],
			[_sc(40, 48), _sc(30, 46), _sr(2.8), _sr(2.5), 112],
			[_sc(64, 48), _sc(74, 46), _sr(2.8), _sr(2.5), 113],
			[_sc(28, 36), _sc(26, 26), _sr(2.6), _sr(3.0), 114],
			[_sc(76, 36), _sc(78, 26), _sr(2.6), _sr(3.0), 115],
			[_sc(32, 18), _sc(46, 16), _sr(2.6), _sr(2.5), 116],
			[_sc(72, 18), _sc(58, 16), _sr(2.6), _sr(2.5), 117],
		],
		_sn(4),
		entrance_hint
	)

	# Mesa outcrops standing inside the basin.
	for spot in [
		[_sc(38, 40), _sh(3.4), 121], [_sc(66, 40), _sh(3.4), 122],
		[_sc(52, 24), _sh(3.0), 123], [_sc(34, 56), _sh(2.8), 124],
		[_sc(70, 56), _sh(2.8), 125], [_sc(52, 41), _sh(3.2), 126],
	]:
		var mesa: Dictionary = {}
		MapKit.blob(mesa, spot[0], spot[1], _sw(0.28), int(spot[2]), _bounds)
		mesa = MapKit.smooth(mesa, _bounds, 1, 5, 4)
		for cell: Vector2i in mesa.keys():
			floor_mask.erase(cell)
	floor_mask = MapKit.largest_region(floor_mask, _pick_open(floor_mask, entrance_hint))

	# Only the ring's flat interior tiles: the rest carry cliff shading that
	# tiles up as brown wedges scattered over the basin.
	var sand := [
		Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 2),
		Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3),
	]
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, 0, MapKit._pick(sand, cell, 131))

	var void_mask := _void_of(floor_mask)
	var spec := MapKit.RimSpec.new()
	spec.source = 0
	spec.fill = [Vector2i(7, 6)]
	spec.n = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	spec.s = [Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)]
	spec.w = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	spec.e = [Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3)]
	spec.nw = Vector2i(0, 0)
	spec.ne = Vector2i(5, 0)
	spec.sw = Vector2i(0, 4)
	spec.se = Vector2i(5, 4)
	spec.s_face = [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5)]
	spec.s_base = [Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6)]
	spec.sw_face = Vector2i(0, 5)
	spec.sw_base = Vector2i(0, 6)
	spec.se_face = Vector2i(5, 5)
	spec.se_base = Vector2i(5, 6)
	spec.face_rows = 2
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 0, Vector2i(7, 6))
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, spec, _bounds, blocked)

	var walk := _walkable(floor_mask, blocked)
	var entrance := _pick_open(walk, entrance_hint)
	walk = MapKit.largest_region(walk, entrance)
	var portal := _pick_open(walk, entrance + Vector2i(0, _sn(5)))

	var keepout: Dictionary = {}
	for spot in [entrance, portal]:
		for oy in range(-3, 4):
			for ox in range(-3, 4):
				keepout[spot + Vector2i(ox, oy)] = true

	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not keepout.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	# Boulders hug the mesa feet; cacti stand out in the open sand.
	_scatter_props(props, 0, edges, [[10, 7, 2, 2], [12, 7, 2, 2], [10, 1, 2, 2]], 0.10, 5, 141, free, solid)
	_scatter_props(props, 0, inner, [[10, 14, 1, 3], [11, 14, 1, 3], [12, 14, 1, 3]], 0.05, 6, 142, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)
	_scatter_flat(props, 0, inner, [[10, 5], [11, 5], [12, 5], [13, 5], [14, 5]], 0.10, 3, 143, solid)

	var critters: Array = []
	var names := ["critter_stag", "critter_boar", "critter_badger", "critter_wolf"]
	var ci := 0
	for spot in [
		_sc(30, 46), _sc(74, 46), _sc(52, 34), _sc(52, 58),
		_sc(20, 25), _sc(84, 25), _sc(20, 55), _sc(84, 55),
		_sc(40, 18), _sc(64, 18), _sc(36, 62), _sc(68, 62),
		_sc(15, 40), _sc(90, 40), _sc(48, 48), _sc(60, 36),
	]:
		var cell := _pick_open(walk, spot)
		critters.append({
			"name": "DesertCritter%d" % (ci + 1),
			"frames": names[ci % names.size()],
			"pos": _tile_pos(cell),
			"scale": 0.9,
			"wander_radius": 40.0,
		})
		ci += 1

	var decos: Array = []
	var ti := 0
	for spot in [
		_sc(24, 20), _sc(80, 20), _sc(52, 16), _sc(52, 63),
		# Grown with the span so the basin is not dark between oases.
		_sc(26, 44), _sc(78, 44), _sc(52, 32), _sc(52, 50),
		_sc(38, 24), _sc(66, 24), _sc(38, 58), _sc(66, 58),
	]:
		var cell := _pick_open(walk, spot)
		ti += 1
		decos.append({
			"name": "OasisTorch%d" % ti,
			"frames": "deco_torch",
			"pos": _tile_pos(cell),
			"scale": 1.2,
			"light": 0.45,
			"color": "Color(1, 0.82, 0.5, 1)",
		})

	# --- Population ----------------------------------------------------------
	# Ankhemet holds the north basin, the chamber furthest from the hub portal.
	# The Necromancer used to share this map; he now lives in The Ossuary off
	# the Sewers. Unbound Sand King is the desert's style-weapon pad.
	var boss_cell := _place(walk, {}, _sc(52, 16), 0)
	var world_cell := _place(walk, {}, _sc(80, 20), 0)
	var taken: Dictionary = {}
	for spot in [entrance, portal]:
		for oy in range(-_sn(6), _sn(6) + 1):
			for ox in range(-_sn(6), _sn(6) + 1):
				taken[spot + Vector2i(ox, oy)] = true
	for spot in [boss_cell, world_cell]:
		for oy in range(-_sn(9), _sn(9) + 1):
			for ox in range(-_sn(9), _sn(9) + 1):
				taken[spot + Vector2i(ox, oy)] = true
	var hostiles := _mobs(walk, taken, [
		["Archer", "trpg/trpg_archer", _sc(52, 50), 3],
		["Orc", "trpg/trpg_orc", _sc(40, 52), 2],
		["OrcRider", "trpg/trpg_orc_rider", _sc(64, 52), 2],
		["Harpy", "trpg/trpg_clawing_harpy", _sc(26, 44), 3],
		["HarpyE", "trpg/trpg_clawing_harpy", _sc(78, 44), 3],
		["Cockatrice", "trpg/trpg_lacerating_cockatrice", _sc(34, 38), 2],
		["CockatriceE", "trpg/trpg_lacerating_cockatrice", _sc(70, 38), 2],
		["SkeletonArcher", "trpg/trpg_skeleton_archer", _sc(52, 32), 3],
		["Skeleton", "trpg/trpg_skeleton", _sc(40, 30), 2],
		["SkeletonE", "trpg/trpg_skeleton", _sc(64, 30), 2],
		["ArmoredSkeleton", "trpg/trpg_armored_skeleton", _sc(24, 20), 2],
		["ArmoredSkeletonE", "trpg/trpg_armored_skeleton", _sc(80, 20), 2],
		["Lancer", "trpg/trpg_lancer", _sc(32, 26), 2],
		["LancerE", "trpg/trpg_lancer", _sc(72, 26), 2],
		["Gorgon", "trpg/trpg_poisonous_gorgon", _sc(52, 24), 2],
		["Fomorian", "trpg/trpg_wretched_fomorian", _sc(44, 20), 2],
		["Soldier", "trpg/trpg_soldier", _sc(60, 20), 2],
		["Priest", "trpg/trpg_priest", _sc(52, 42), 2],
	], _sn(5))
	hostiles.append({
		"name": "UnboundSandKing",
		"type": TYPES + "bosses/sand_king_world.tres",
		"pos": _tile_pos(world_cell),
	})

	assert(walk.has(entrance) and walk.has(portal), "desert spawn blocked")
	assert(walk.size() > 900 * SURFACE_S * SURFACE_S, "desert too small: %d" % walk.size())
	print("desert walk=", walk.size(), " floor=", floor_mask.size())

	_write_map({
		"root": "desert",
		"out": "res://source/common/gameplay/maps/maps/desert/desert.tscn",
		"tileset": DESERT_TS,
		"bg": "Color(0.09, 0.07, 0.05, 1)",
		"modulate": "Color(1, 0.97, 0.9, 1)",
		"music": "res://assets/audio/music/arabian.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"critters": critters,
		"decos": decos,
		"hostiles": hostiles,
		"entrance": _tile_pos(entrance),
		"portal": _tile_pos(portal),
		"entrance_id": 25,
		"portal_id": 125,
		"portal_color": "Color(0.85, 0.66, 0.25, 1)",
		"walk_count": walk.size(),
		"wall_count": walls.get_used_cells().size(),
		"prop_count": props.get_used_cells().size(),
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
		"lights": "",
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [
				str(_tile_pos(entrance + _sc(2, -2)).x),
				str(_tile_pos(entrance + _sc(2, -2)).y),
			]
		),
	})


func _write_map(cfg: Dictionary) -> void:
	var critters: Array = cfg.get("critters", [])
	var decos: Array = cfg.get("decos", [])

	var frame_ext := ""
	var frame_ids: Dictionary = {}
	var next_id := 0
	for c in critters:
		var slug: String = c["frames"]
		if frame_ids.has(slug):
			continue
		var eid := "sf%d" % next_id
		next_id += 1
		frame_ids[slug] = eid
		frame_ext += "[ext_resource type=\"SpriteFrames\" path=\"res://source/common/gameplay/characters/sprite_frames/%s.tres\" id=\"%s\"]\n" % [slug, eid]
	for d in decos:
		var slug2: String = d["frames"]
		if frame_ids.has(slug2):
			continue
		var eid2 := "sf%d" % next_id
		next_id += 1
		frame_ids[slug2] = eid2
		frame_ext += "[ext_resource type=\"SpriteFrames\" path=\"res://source/common/gameplay/props/sprite_frames/%s.tres\" id=\"%s\"]\n" % [slug2, eid2]

	var scene_nodes := ""
	for c in critters:
		scene_nodes += (
			"\n[node name=\"%s\" parent=\"SceneProps\" instance=ExtResource(\"critter\")]\n"
			+ "position = Vector2(%s, %s)\n"
			+ "sprite_frames = ExtResource(\"%s\")\n"
			+ "scale_factor = %s\n"
			+ "wander_radius = %s\n"
		) % [
			c["name"], str(c["pos"].x), str(c["pos"].y), frame_ids[c["frames"]],
			str(c.get("scale", 1.0)), str(c.get("wander_radius", 40.0)),
		]
	for d in decos:
		scene_nodes += (
			"\n[node name=\"%s\" parent=\"SceneProps\" instance=ExtResource(\"deco\")]\n"
			+ "position = Vector2(%s, %s)\n"
			+ "sprite_frames = ExtResource(\"%s\")\n"
			+ "scale_factor = %s\n"
			+ "light_energy = %s\n"
			+ "light_color = %s\n"
		) % [
			d["name"], str(d["pos"].x), str(d["pos"].y), frame_ids[d["frames"]],
			str(d.get("scale", 1.0)), str(d.get("light", 0.0)), d.get("color", "Color(1, 0.7, 0.3, 1)"),
		]

	var music_ext := ""
	var music_line := ""
	if cfg.has("music"):
		music_ext = "[ext_resource type=\"AudioStream\" path=\"%s\" id=\"music\"]\n" % cfg["music"]
		music_line = "music = ExtResource(\"music\")\n"

	# --- Hostiles ------------------------------------------------------------
	# Both id maps are baked on the container. A hostile missing from these never
	# replicates to clients — that is the failure mode AGENTS.md calls out for the
	# Hollow golem, and it is silent, so it is written here rather than left to a
	# caller to remember.
	var hostiles: Array = cfg.get("hostiles", [])
	var hostile_ext := ""
	var type_ids: Dictionary = {}
	if not hostiles.is_empty():
		hostile_ext += (
			"[ext_resource type=\"PackedScene\" uid=\"uid://v32667qwpj2l\" path=\"%s\" id=\"hostile\"]\n"
			% HOSTILE_SCN
		)
	for h: Dictionary in hostiles:
		var tpath: String = h["type"]
		if type_ids.has(tpath):
			continue
		var tid := "et%d" % type_ids.size()
		type_ids[tpath] = tid
		hostile_ext += "[ext_resource type=\"Resource\" path=\"%s\" id=\"%s\"]\n" % [tpath, tid]

	var id_to_node := ""
	var node_to_id := ""
	var hostile_nodes := ""
	for i in hostiles.size():
		var h2: Dictionary = hostiles[i]
		var nm: String = h2["name"]
		var sep := ",\n" if i < hostiles.size() - 1 else "\n"
		id_to_node += "%d: NodePath(\"%s\")%s" % [i, nm, sep]
		node_to_id += "NodePath(\"%s\"): %d%s" % [nm, i, sep]
		hostile_nodes += (
			"\n[node name=\"%s\" parent=\"ReplicatedPropsContainer\" instance=ExtResource(\"hostile\")]\n"
			+ "position = Vector2(%s, %s)\n"
			+ "debug_draw_ranges = false\n"
			+ "enemy_data = ExtResource(\"%s\")\n"
			+ "weapon = null\n"
		) % [nm, str(h2["pos"].x), str(h2["pos"].y), type_ids[h2["type"]]]
	var id_map_lines := "id_to_node = {}\nnode_to_id = {}\n"
	if not hostiles.is_empty():
		id_map_lines = "id_to_node = {\n%s}\nnode_to_id = {\n%s}\n" % [id_to_node, node_to_id]

	var cam_r: int = int(cfg.get("cam_right", W * 16 + 16))
	var cam_b: int = int(cfg.get("cam_bottom", H * 16 + 16))

	var text := """[gd_scene format=3]

[ext_resource type=\"Script\" uid=\"uid://7mbux4mybta0\" path=\"%s\" id=\"1_map\"]
[ext_resource type=\"TileSet\" path=\"%s\" id=\"2_tiles\"]
%s[ext_resource type=\"Script\" uid=\"uid://wq8klpndipnu\" path=\"%s\" id=\"4_rp\"]
[ext_resource type=\"PackedScene\" uid=\"uid://b2ckixon7ryh6\" path=\"%s\" id=\"5_warper\"]
[ext_resource type=\"PackedScene\" uid=\"uid://0m5eq6iylq26\" path=\"%s\" id=\"6_portal\"]
[ext_resource type=\"Resource\" uid=\"uid://doc0umc2oovri\" path=\"%s\" id=\"7_hub\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"8_camp\"]
[ext_resource type=\"Texture2D\" path=\"%s\" id=\"9_glow\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"critter\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"deco\"]
%s%s
[node name=\"%s\" type=\"Node2D\" node_paths=PackedStringArray(\"replicated_props_container\")]
y_sort_enabled = true
script = ExtResource(\"1_map\")
replicated_props_container = NodePath(\"ReplicatedPropsContainer\")
map_background_color = %s
%scamera_limit_left = -16
camera_limit_top = -16
camera_limit_right = %d
camera_limit_bottom = %d

[node name=\"CanvasModulate\" type=\"CanvasModulate\" parent=\".\"]
color = %s

[node name=\"Tiles\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true

[node name=\"Ground\" type=\"TileMapLayer\" parent=\"Tiles\"]
z_index = -1
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"2_tiles\")

[node name=\"Walls\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"2_tiles\")

[node name=\"Props\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"2_tiles\")

[node name=\"SceneProps\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true
%s%s%s
[node name=\"ReplicatedPropsContainer\" type=\"Node2D\" parent=\".\" node_paths=PackedStringArray(\"id_to_node\", \"node_to_id\")]
y_sort_enabled = true
script = ExtResource(\"4_rp\")
%s%s
[node name=\"RespawnPoint\" parent=\".\" instance=ExtResource(\"5_warper\")]
position = Vector2(%s, %s)

[node name=\"Entrance\" parent=\".\" instance=ExtResource(\"5_warper\")]
position = Vector2(%s, %s)
warper_id = %d

[node name=\"Portal\" parent=\".\" instance=ExtResource(\"6_portal\")]
position = Vector2(%s, %s)
portal_color = %s
destination_label = \"Castle Garden\"
target_instance = ExtResource(\"7_hub\")
warper_id = %d
target_id = %d
""" % [
		MAP_SCRIPT, cfg["tileset"], music_ext, RP_SCRIPT, WARPER, PORTAL, HUB, CAMP, GLOW,
		CRITTER_SCN, DECO_SCN, frame_ext, hostile_ext,
		cfg["root"], cfg["bg"], music_line, cam_r, cam_b, cfg["modulate"],
		cfg["ground_b64"], cfg["walls_b64"], cfg["props_b64"],
		cfg.get("lights", ""), cfg.get("camps", ""), scene_nodes,
		id_map_lines, hostile_nodes,
		str(cfg["entrance"].x), str(cfg["entrance"].y),
		str(cfg["entrance"].x), str(cfg["entrance"].y), int(cfg["entrance_id"]),
		str(cfg["portal"].x), str(cfg["portal"].y), cfg["portal_color"],
		int(cfg["portal_id"]), int(cfg["entrance_id"]),
	]
	var f := FileAccess.open(cfg["out"], FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print(
		"wrote ", cfg["out"],
		" walk=", cfg.get("walk_count", 0),
		" walls=", cfg.get("wall_count", 0),
		" props=", cfg.get("prop_count", 0),
		" critters=", critters.size(),
		" decos=", decos.size(),
		" mobs=", hostiles.size()
	)
