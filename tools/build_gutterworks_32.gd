extends SceneTree
## Rebuild The Gutterworks on Rafael Matos's 32x32 Epic RPG World Sewers art.
##
## Separate from `build_biome_levels.gd` on purpose. That tool builds the other
## five sub-levels on the 16px `sewers_tileset.tres` and its single-row
## `RimSpec`; this map has moved to a different grid, a different atlas and the
## three-tile `MapKit.WallSpec`, and folding both into one builder would mean
## every shared helper carrying a tile-size branch. The Cistern and the Ossuary
## keep working exactly as they did.
##
## Topology, warper ids, NPC roster and mob plan are carried over unchanged from
## the 16px build — this is an art and geometry pass, not a redesign, so the
## warper round trips `verify_biome_levels` asserts still close.
##
##   godot --headless --path . -s tools/build_gutterworks_32.gd

const TS := "res://source/common/gameplay/maps/tilesets/rpgw_sewers_tileset.tres"
const OUT := "res://source/common/gameplay/maps/maps/sewers/gutterworks.tscn"
const INST := "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const TYPES := "res://source/common/gameplay/characters/npc/types/"
const NPCS := "res://source/common/gameplay/characters/npc/npcs/"

const TILE := 32
## Layout scale. The 16px build used 5; at twice the cell size 2 keeps the world
## slightly tighter than before (6656x4992 against 8320x6240), which puts the
## same 24 hostiles in a denser space rather than spreading them thinner.
const S := 2

# --- atlas banks (see build_rpgw_sewers_tileset.gd for how they were chosen) --
const SRC_TERRAIN := 0
const SRC_WALL := 1
const SRC_SEWAGE := 2
const SRC_PROPS := 3

const FLOOR: Array[Vector2i] = [
	Vector2i(26, 2), Vector2i(27, 2), Vector2i(28, 2),
	Vector2i(26, 3), Vector2i(27, 3), Vector2i(28, 3),
	Vector2i(26, 4), Vector2i(27, 4), Vector2i(28, 4),
]
## Flat dark masonry. Doubles as the void fill so no transparent hole is ever
## left behind the geometry, and as the dry apron beside the slime.
const DARK: Array[Vector2i] = [Vector2i(28, 37), Vector2i(29, 37), Vector2i(33, 37)]
const SLIME := Vector2i(2, 47)
## Uniform dark wall interior from the wall sheet (luma 0.18, zero texture).
## The void needs to sit clearly below the walkway in value or the map reads as
## one flat mass — an earlier pass used the same dark masonry for both and you
## could not tell floor from wall.
const VOID: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]


## The sewage channel's authored border ring. Read off the rounded-square
## template at Tileset-Terrain (27..31, 53..57): the fill sits at its centre and
## the eight surrounding roles are the stone banks the liquid laps against.
func _slime_spec() -> MapKit.BlobSpec:
	var spec := MapKit.BlobSpec.new()
	spec.source = SRC_TERRAIN
	spec.fill = Vector2i(29, 55)
	spec.n = Vector2i(29, 53)
	spec.s = Vector2i(29, 57)
	spec.w = Vector2i(27, 55)
	spec.e = Vector2i(31, 55)
	spec.nw = Vector2i(28, 54)
	spec.ne = Vector2i(30, 54)
	spec.sw = Vector2i(28, 56)
	spec.se = Vector2i(30, 56)
	return spec
const SEWAGE := Vector2i(0, 0)

var W: int = 104 * S
var H: int = 78 * S
var _bounds := Rect2i(0, 0, 104 * S, 78 * S)
var _report: Array[String] = []


func _initialize() -> void:
	_build()
	for line in _report:
		print(line)
	print("GUTTERWORKS_32_BUILT")
	quit(0)


func _L(x: int, y: int) -> Vector2i:
	return Vector2i(x * S, y * S)


func _R(v: float) -> float:
	return v * float(S)


func _N(n: int) -> int:
	return n * S


func _gap(n: int) -> int:
	return maxi(n, int((n * S) / 2.0))


func _new_layer(ts: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	return layer


## The three-tile sewer wall. Rows 9/10/11 of `wall-1-water` are rim / body /
## base; column 6 is a blank separator between the two run variants, so it is
## skipped. Column 9 rows 3-5 is the arched alcove.
func _wall_spec() -> MapKit.WallSpec:
	var spec := MapKit.WallSpec.new()
	spec.source = SRC_WALL
	for x in [0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12]:
		spec.rim.append(Vector2i(x, 9))
		spec.body.append(Vector2i(x, 10))
		spec.base.append(Vector2i(x, 11))
	spec.alcove = [Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5)]
	return spec


func _carve(chambers: Array, links: Array, margin: int, anchor: Vector2i) -> Dictionary:
	var mask: Dictionary = {}
	for ch in chambers:
		MapKit.blob(mask, ch[0], ch[1], ch[2], int(ch[3]), _bounds)
	for link in links:
		MapKit.tunnel(mask, link[0], link[1], link[2], link[3], int(link[4]), _bounds)
	var trimmed: Dictionary = {}
	for cell: Vector2i in mask.keys():
		if cell.x >= margin and cell.y >= margin + 2 and cell.x < W - margin and cell.y < H - margin:
			trimmed[cell] = true
	var smoothed := MapKit.smooth(trimmed, _bounds, 2, 5, 4)
	return MapKit.largest_region(smoothed, LevelKit.pick_open(smoothed, anchor))


func _populate(walk: Dictionary, taken: Dictionary, spots: Array, gap: int = 3) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for wanted: Vector2i in spots:
		var pool: Dictionary = {}
		for cell: Vector2i in walk.keys():
			if not taken.has(cell):
				pool[cell] = true
		if pool.is_empty():
			out.append(wanted)
			continue
		var cell := LevelKit.pick_open(pool, wanted)
		out.append(cell)
		for oy in range(-gap, gap + 1):
			for ox in range(-gap, gap + 1):
				taken[cell + Vector2i(ox, oy)] = true
	return out


## Godot's set_cell() silently leaves a cell EMPTY when the atlas coordinate is
## not a created tile, so a single mistyped bank punches invisible holes through
## the finished map — exactly the "void gap" this overhaul is meant to remove.
## The banks are therefore checked against the tileset before anything is painted.
func _require(ts: TileSet, source: int, coords: Array[Vector2i], what: String) -> void:
	var src := ts.get_source(source) as TileSetAtlasSource
	assert(src != null, "tileset has no source %d (%s)" % [source, what])
	for c: Vector2i in coords:
		assert(src.has_tile(c), "%s: source %d has no tile at %s" % [what, source, c])


func _build() -> void:
	var ts: TileSet = load(TS)
	assert(ts != null, "missing %s" % TS)
	var slime := _slime_spec()
	_require(ts, SRC_TERRAIN, FLOOR, "floor")
	_require(ts, SRC_TERRAIN, DARK, "dark masonry")
	_require(ts, SRC_TERRAIN, [SLIME], "slime fill")
	_require(ts, SRC_TERRAIN, [
		slime.fill, slime.n, slime.s, slime.w, slime.e,
		slime.nw, slime.ne, slime.sw, slime.se,
	], "slime banks")
	_require(ts, SRC_WALL, VOID, "void fill")
	_require(ts, SRC_SEWAGE, [SEWAGE], "animated sewage")
	var ws := _wall_spec()
	_require(ts, SRC_WALL, ws.rim + ws.body + ws.base + ws.alcove, "wall spec")
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	# --- topology: a 3x3 grid of junctions joined by service runs -------------
	var arrival := _L(52, 68)
	var cols := [_N(22), _N(52), _N(82)]
	var rows := [_N(20), _N(40), _N(58)]
	var chambers: Array = [[_L(52, 67), _R(7.0), 0.24, 401]]
	var seed_i := 410
	for cx in cols:
		for ry in rows:
			chambers.append([Vector2i(cx, ry), _R(7.0), 0.26, seed_i])
			seed_i += 1
	var links: Array = [[_L(52, 64), _L(52, 60), _R(2.6), _R(1.6), 430]]
	var seed_j := 440
	for ry in rows:
		for i in range(cols.size() - 1):
			links.append([Vector2i(cols[i], ry), Vector2i(cols[i + 1], ry), _R(2.2), _R(2.0), seed_j])
			seed_j += 1
	for cx in cols:
		for i in range(rows.size() - 1):
			links.append([Vector2i(cx, rows[i]), Vector2i(cx, rows[i + 1]), _R(2.2), _R(2.0), seed_j])
			seed_j += 1
	var floor_mask := _carve(chambers, links, _N(4), arrival)

	# --- Layer 0: walkway, then the toxic channels cut through it -------------
	# Plain cobble walkway. Separation comes from value, not hue: the void below
	# is a flat dark fill and the sewage above is fully saturated, so the
	# mid-tone cobble sits between them and both read. An earlier pass mixed dry
	# masonry patches in here, but that art is horizontally banded wall face and
	# tiled as hard-edged panels dropped on the floor.
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, SRC_TERRAIN, MapKit._pick(FLOOR, cell, 451))

	# Slime runs along the horizontal service corridors, so the liquid reads as
	# flowing between junctions rather than pooling in them.
	# Meander the channels through waypoints instead of running them dead
	# straight — a perfectly horizontal band reads as a painted stripe, not a
	# flow of liquid.
	var river: Dictionary = {}
	var rseed := 470
	var steps: int = 7
	for ry in rows:
		var pts: Array[Vector2i] = []
		for i in steps + 1:
			var x: int = cols[0] + int(float(cols[2] - cols[0]) * float(i) / float(steps))
			var off: int = int(round(sin(float(i) * 1.15 + float(ry) * 0.4) * float(_N(2))))
			pts.append(Vector2i(x, ry + off))
		for i in steps:
			MapKit.tunnel(river, pts[i], pts[i + 1], _R(0.9), _R(0.7), rseed, _bounds)
			rseed += 1
	var slime_cells: Dictionary = {}
	for cell: Vector2i in river.keys():
		if floor_mask.has(cell):
			slime_cells[cell] = true
	# Banks, not a stamped rectangle: every channel cell picks its tile from
	# which sides are dry, so the liquid meets the stone on an authored edge.
	MapKit.paint_blob(ground, slime_cells, slime)
	# A ribbon of the animated sewage tile down the middle of each channel. The
	# centre is measured from the mask rather than assumed, because the channels
	# now wander off their nominal row.
	var column_rows: Dictionary = {}
	for cell: Vector2i in slime_cells.keys():
		if not column_rows.has(cell.x):
			column_rows[cell.x] = []
		column_rows[cell.x].append(cell.y)
	var flowing: int = 0
	for x: int in column_rows.keys():
		var ys: Array = column_rows[x]
		ys.sort()
		var mid: int = int(ys[ys.size() / 2])
		for dy in [-1, 0]:
			var cell := Vector2i(x, mid + dy)
			# Interior only — an animated full tile over a bank cell would cover
			# the authored edge and put a hard seam back in.
			if not slime_cells.has(cell):
				continue
			if not (slime_cells.has(cell + Vector2i(0, -1)) and slime_cells.has(cell + Vector2i(0, 1))
					and slime_cells.has(cell + Vector2i(-1, 0)) and slime_cells.has(cell + Vector2i(1, 0))):
				continue
			ground.set_cell(cell, SRC_SEWAGE, SEWAGE)
			flowing += 1

	# --- void fill: dark masonry everywhere the floor is not ------------------
	var void_mask := LevelKit.void_of(floor_mask, W, H)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, SRC_WALL, MapKit._pick(VOID, cell, 452))

	# --- Layers 2 and 3: three-tile walls, rims capped onto the overlay -------
	var blocked: Dictionary = {}
	var runs := MapKit.paint_wall3(
		walls, overlay, floor_mask, void_mask, _wall_spec(), _bounds, blocked, 9, 480
	)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, arrival)
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + _L(0, 5))

	var no_build := LevelKit.keepout([entrance, exit_cell], _gap(4))
	for cell: Vector2i in slime_cells.keys():
		no_build[cell] = true # never strand a prop in the channel
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, _gap(3))

	# --- Layer 1: crates, bones, planks and pipework --------------------------
	LevelKit.scatter_props(props, SRC_PROPS, edges, [
		[35, 16, 1, 2], [37, 16, 1, 2], [39, 16, 1, 2],
	], 0.12, 4, 461, free, solid)
	LevelKit.scatter_props(props, SRC_PROPS, inner, [
		[26, 23, 1, 1], [28, 23, 1, 1], [30, 23, 1, 1], [32, 23, 1, 1],
	], 0.06, 5, 462, free, solid)
	LevelKit.scatter_props(props, SRC_PROPS, edges, [
		[0, 28, 2, 1], [3, 28, 2, 1], [6, 28, 2, 1],
	], 0.05, 6, 463, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	# Spider webs hang on the overlay so they read in front of the player.
	LevelKit.scatter_flat(overlay, SRC_PROPS, edges, [
		Vector2i(1, 4), Vector2i(4, 4), Vector2i(8, 4), Vector2i(12, 4),
	], 0.05, 5, 465, solid)
	# Pipe stubs and drain covers on the floor itself.
	LevelKit.scatter_flat(props, SRC_PROPS, inner, [
		Vector2i(38, 41), Vector2i(41, 41), Vector2i(44, 41),
	], 0.04, 6, 464, solid)

	# --- Layer 3 lighting: green glow along the channels ----------------------
	var lights: Array = []
	var li := 0
	for ry in rows:
		for x in range(cols[0], cols[2] + 1, _N(7)):
			var cell := Vector2i(x, ry)
			if not slime_cells.has(cell):
				continue
			li += 1
			lights.append({
				"name": "SlimeGlow%d" % li,
				"pos": LevelKit.tile_pos_sized(cell, TILE),
				"color": "Color(0.42, 1.0, 0.45, 1)",
				"energy": 0.42,
				"scale": 1.7,
			})

	var decos: Array = []
	var ti := 0
	for spot in [
		_L(22, 20), _L(52, 20), _L(82, 20),
		_L(22, 40), _L(52, 40), _L(82, 40),
		_L(22, 58), _L(52, 58), _L(82, 58), _L(52, 67),
	]:
		ti += 1
		decos.append({
			"name": "GutterLamp%d" % ti,
			"frames": "deco_torch" if ti % 3 != 0 else "deco_candle_a",
			"pos": LevelKit.tile_pos_sized(LevelKit.pick_open(walk, spot), TILE),
			"scale": 1.35,
			"light": 0.9,
			"color": "Color(0.55, 0.95, 0.6, 1)" if ti % 3 == 0 else "Color(1, 0.74, 0.4, 1)",
		})

	# --- population: carried over from the 16px build unchanged ---------------
	var taken := LevelKit.keepout([entrance, exit_cell], _gap(6))
	var mob_plan: Array = [
		["Slime", "trpg/trpg_slime", _L(22, 58)],
		["Slime2", "trpg/trpg_slime", _L(82, 58)],
		["Slime3", "trpg/trpg_slime", _L(52, 58)],
		["Slime4", "trpg/trpg_slime", _L(37, 58)],
		["Slime5", "trpg/trpg_slime", _L(67, 58)],
		["GutterBat", "trpg/trpg_bat", _L(22, 40)],
		["GutterBat2", "trpg/trpg_bat", _L(52, 40)],
		["GutterBat3", "trpg/trpg_bat", _L(82, 40)],
		["GutterBat4", "trpg/trpg_bat", _L(37, 40)],
		["GutterBat5", "trpg/trpg_bat", _L(67, 40)],
		["AcidOoze", "trpg/trpg_acid_ooze", _L(22, 20)],
		["AcidOoze2", "trpg/trpg_acid_ooze", _L(82, 20)],
		["AcidOoze3", "trpg/trpg_acid_ooze", _L(52, 28)],
		["AcidOoze4", "trpg/trpg_acid_ooze", _L(37, 20)],
		["Zombie", "trpg/trpg_zombie_giant", _L(52, 20)],
		["Zombie2", "trpg/trpg_zombie_giant", _L(30, 30)],
		["Zombie3", "trpg/trpg_zombie_giant", _L(74, 30)],
		["Crawler", "trpg/trpg_carrion_crawler", _L(37, 30)],
		["Crawler2", "trpg/trpg_carrion_crawler", _L(67, 30)],
		["Crawler3", "trpg/trpg_carrion_crawler", _L(52, 48)],
		["Skeleton", "trpg/trpg_sewer_skeleton", _L(37, 49)],
		["Skeleton2", "trpg/trpg_sewer_skeleton", _L(67, 49)],
		["Skeleton3", "trpg/trpg_sewer_skeleton", _L(22, 49)],
		["Skeleton4", "trpg/trpg_sewer_skeleton", _L(82, 49)],
	]
	var mob_cells := _populate(walk, taken, mob_plan.map(func(m: Array) -> Vector2i: return m[2]), _gap(4))
	var hostiles: Array = []
	for i in mob_plan.size():
		hostiles.append({
			"name": mob_plan[i][0],
			"type": TYPES + mob_plan[i][1] + ".tres",
			"pos": LevelKit.tile_pos_sized(mob_cells[i], TILE),
		})
	var npc_cells := _populate(walk, taken, [entrance + _L(-4, -2), entrance + _L(4, -2)], _gap(2))

	assert(walk.has(entrance) and walk.has(exit_cell), "gutterworks spawn blocked")
	# 32px cells cover four times the ground of the old 16px ones, so the old
	# 30000-cell floor check would reject a map of the same physical size.
	assert(walk.size() > 6000, "gutterworks too small: %d" % walk.size())
	_report.append("  gutterworks32 walk=%d walls=%d runs=%d slime=%d flowing=%d props=%d lights=%d" % [
		walk.size(), walls.get_used_cells().size(), runs,
		slime_cells.size(), flowing, props.get_used_cells().size(), lights.size(),
	])

	LevelKit.write_map({
		"root": "gutterworks",
		"out": OUT,
		"tileset": TS,
		"bg": "Color(0.02, 0.03, 0.02, 1)",
		# Cooler and greener than the 16px build's blue-grey, so the ambient
		# reads as sewer air rather than castle stone.
		"modulate": "Color(0.62, 0.78, 0.64, 1)",
		"music": "res://assets/audio/music/alone.ogg",
		"playlist": ["res://assets/audio/music/army_of_darkness.ogg"],
		"layers": {
			"Ground": LevelKit.b64(ground),
			"Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props),
			"Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * TILE + TILE,
		"cam_bottom": H * TILE + TILE,
		"camps": [{"name": "CrewBrazier", "pos": LevelKit.tile_pos_sized(entrance + _L(3, -3), TILE)}],
		"lights": lights,
		"decos": decos,
		"hostiles": hostiles,
		"npcs": [
			{"name": "SluiceWardenObry", "resource": NPCS + "sewers/sluice_warden_obry.tres",
				"pos": LevelKit.tile_pos_sized(npc_cells[0], TILE)},
			{"name": "RatcatcherPell", "resource": NPCS + "sewers/ratcatcher_pell.tres",
				"pos": LevelKit.tile_pos_sized(npc_cells[1], TILE)},
		],
		"spawn": LevelKit.tile_pos_sized(entrance, TILE),
		"warpers": [{"name": "Entrance", "pos": LevelKit.tile_pos_sized(entrance, TILE), "id": 42}],
		"portals": [{
			"name": "DescentPortal", "pos": LevelKit.tile_pos_sized(exit_cell, TILE),
			"id": 142, "target_id": 52, "instance": INST + "sewers.tres",
			"label": "The Sewers", "color": "Color(0.35, 0.62, 0.4, 1)",
		}],
	})
