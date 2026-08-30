extends SceneTree
## Build the three sewer maps as OPEN HUNTING BIOMES on the 32px art.
##
## These are field-boss zones, not dungeon crawls, so the geometry is one wide
## cavernous space per map rather than rooms or a corridor grid. Three rules
## follow from that and are enforced here rather than left to authoring:
##
##   1. The interior has no walls at all. Any pocket of void the boundary noise
##      leaves inside the zone is filled back to floor by `_seal_interior`, so
##      the only void is the border-connected outside and the only three-tile
##      walls are on the map's outer edge.
##   2. Sewage is painted as wide continuous rivers with authored banks, not
##      one-tile stripes — broad enough to fight around and to spawn against.
##   3. The boundary undulates from low-frequency noise, which gives broad bays
##      and headlands. It is deliberately NOT carved with tunnel(), whose narrow
##      radius is what produced the stair-stepped edges in the room build.
##
## Replaces the Gutterworks room grid and takes the Cistern and the surface hub
## off `build_biome_levels.gd` / `build_stub_biomes.gd`. The Ossuary is not part
## of this and stays on the 16px tileset.
##
## The surface map carries the hub's whole warper set — entrance 28, the
## overworld portal 128, and the three landing/stair pairs down to the
## sub-levels. Stair 156 to the Ossuary is emitted here because it was
## hand-placed on the old scene and `add_biome_stairs.gd` explicitly refuses to
## manage it; regenerating without it would silently break that round trip.
##
##   godot --headless --path . -s tools/build_sewer_biome_32.gd

const TS := "res://source/common/gameplay/maps/tilesets/rpgw_sewers_tileset.tres"
const MAPS := "res://source/common/gameplay/maps/maps/sewers/"
const INST := "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const OVERWORLD := "res://source/common/gameplay/maps/instance/instance_collection/overworld.tres"
const TYPES := "res://source/common/gameplay/characters/npc/types/"
const NPCS := "res://source/common/gameplay/characters/npc/npcs/"

const TILE := 32
## Minimum length of a straight bank run, in cells.
const RUN := 4

const SRC_TERRAIN := 0
const SRC_WALL := 1
const SRC_SEWAGE := 2
const SRC_PROPS := 3

const FLOOR: Array[Vector2i] = [
	Vector2i(26, 2), Vector2i(27, 2), Vector2i(28, 2),
	Vector2i(26, 3), Vector2i(27, 3), Vector2i(28, 3),
	Vector2i(26, 4), Vector2i(27, 4), Vector2i(28, 4),
]
const DARK: Array[Vector2i] = [Vector2i(28, 37), Vector2i(29, 37), Vector2i(33, 37)]
const VOID: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
const SEWAGE := Vector2i(0, 0)

var W: int = 0
var H: int = 0
var _bounds := Rect2i()
var _report: Array[String] = []


func _initialize() -> void:
	_build_sewers()
	_build_gutterworks()
	_build_cistern()
	for line in _report:
		print(line)
	print("SEWER_BIOME_32_BUILT")
	quit(0)


# --- shared helpers ---------------------------------------------------------

func _size(w: int, h: int) -> void:
	W = w
	H = h
	_bounds = Rect2i(0, 0, w, h)


func _layer(ts: TileSet) -> TileMapLayer:
	var l := TileMapLayer.new()
	l.tile_set = ts
	return l


func _wall_spec() -> MapKit.WallSpec:
	var spec := MapKit.WallSpec.new()
	spec.source = SRC_WALL
	for x in [0, 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 12]:
		spec.rim.append(Vector2i(x, 9))
		spec.body.append(Vector2i(x, 10))
		spec.base.append(Vector2i(x, 11))
	spec.alcove = [Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5)]
	return spec


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


## One broad open zone. `wobble` is how far the boundary breathes in and out;
## the noise scale is large so the edge makes bays tens of cells across instead
## of the cell-scale ragged edge a carve would leave.
func _open_zone(inset: int, wobble: float, seed_v: int) -> Dictionary:
	var mask: Dictionary = {}
	var cx := float(W) * 0.5
	var cy := float(H) * 0.5
	var rx := float(W) * 0.5 - float(inset)
	var ry := float(H) * 0.5 - float(inset)
	for y in range(inset, H - inset):
		for x in range(inset, W - inset):
			var nx: float = (float(x) - cx) / rx
			var ny: float = (float(y) - cy) / ry
			# Chebyshev falloff keeps the middle wide open instead of tapering
			# to a circle, which is what makes the space read as a hall.
			var d: float = maxf(absf(nx), absf(ny))
			var n: float = MapKit.value_noise(float(x), float(y), 30.0, seed_v)
			if d < 0.99 - wobble * (n - 0.5):
				mask[Vector2i(x, y)] = true
	return mask


## Fill every void pocket that is not connected to the map border, so the
## interior is guaranteed open and the wall painter can only ever build on the
## outer boundary.
func _seal_interior(mask: Dictionary) -> Dictionary:
	var outside: Dictionary = {}
	var queue: Array[Vector2i] = []
	for x in W:
		for y in [0, H - 1]:
			var c := Vector2i(x, y)
			if not mask.has(c) and not outside.has(c):
				outside[c] = true
				queue.append(c)
	for y in H:
		for x in [0, W - 1]:
			var c := Vector2i(x, y)
			if not mask.has(c) and not outside.has(c):
				outside[c] = true
				queue.append(c)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = cur + d
			if not _bounds.has_point(nb) or mask.has(nb) or outside.has(nb):
				continue
			outside[nb] = true
			queue.append(nb)
	var sealed: Dictionary = mask.duplicate()
	for y in H:
		for x in W:
			var c := Vector2i(x, y)
			if not mask.has(c) and not outside.has(c):
				sealed[c] = true
	return sealed


## A wide meandering river across the zone. Width is in cells either side of the
## centreline, so `half = 5` is an eleven-tile channel.
func _river(out: Dictionary, flow: Dictionary, floor_mask: Dictionary, base_y: float,
		amp: float, freq: float, half: int, seed_v: int) -> void:
	# The centreline is held straight and the shoreline comes from width instead.
	# A sloping centreline steps down one cell at a time, and this pack's banks
	# are a rounded-rect ring whose corners need several cells of run to read —
	# a one-cell step is smaller than the art can express, so it renders as a
	# staircase however the tiles are chosen. Width is quantised to RUN-cell
	# stretches for the same reason: every bank run is long enough to sit flat.
	for x in W:
		var qx: int = (x / RUN) * RUN
		var cy: int = int(round(base_y))
		var hw: int = half + int(round(
			(MapKit.value_noise(float(qx), base_y + 40.0, 7.0, seed_v + 7) - 0.5) * 5.0))
		hw = maxi(2, hw)
		for dy in range(-hw, hw + 1):
			var cell := Vector2i(x, cy + dy)
			if floor_mask.has(cell):
				out[cell] = true
				if absi(dy) <= 1:
					flow[cell] = true


## Vertical counterpart, for a river that crosses the zone the other way.
func _river_v(out: Dictionary, flow: Dictionary, floor_mask: Dictionary, base_x: float,
		amp: float, freq: float, half: int, seed_v: int) -> void:
	for y in H:
		var qy: int = (y / RUN) * RUN
		var cx: int = int(round(base_x))
		var hw: int = half + int(round(
			(MapKit.value_noise(base_x + 40.0, float(qy), 7.0, seed_v + 7) - 0.5) * 5.0))
		hw = maxi(2, hw)
		for dx in range(-hw, hw + 1):
			var cell := Vector2i(cx + dx, y)
			if floor_mask.has(cell):
				out[cell] = true
				if absi(dx) <= 1:
					flow[cell] = true


func _paint_ground(ground: TileMapLayer, floor_mask: Dictionary, void_mask: Dictionary) -> void:
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, SRC_TERRAIN, MapKit._pick(FLOOR, cell, 451))
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, SRC_WALL, MapKit._pick(VOID, cell, 452))


## Paint the sewage with its authored banks, then run the animated tile down the
## interior only — over a bank cell it would cover the edge and reinstate a seam.
func _paint_slime(ground: TileMapLayer, slime: Dictionary, flow: Dictionary) -> int:
	MapKit.paint_blob(ground, slime, _slime_spec())
	var flowing: int = 0
	for cell: Vector2i in flow.keys():
		# Interior only. The animated tile is a different green from the blob
		# fill, so scattering it randomly across a river turned the liquid into a
		# two-tone patchwork of blocks; confined to the centreline it reads as
		# current running down the middle of the channel.
		if not slime.has(cell):
			continue
		if not (slime.has(cell + Vector2i(0, -1)) and slime.has(cell + Vector2i(0, 1))
				and slime.has(cell + Vector2i(-1, 0)) and slime.has(cell + Vector2i(1, 0))):
			continue
		ground.set_cell(cell, SRC_SEWAGE, SEWAGE)
		flowing += 1
	return flowing


func _require(ts: TileSet) -> void:
	var slime := _slime_spec()
	var ws := _wall_spec()
	var checks: Array = [
		[SRC_TERRAIN, FLOOR], [SRC_TERRAIN, DARK], [SRC_WALL, VOID],
		[SRC_SEWAGE, [SEWAGE]], [SRC_WALL, ws.rim + ws.body + ws.base + ws.alcove],
		[SRC_TERRAIN, [slime.fill, slime.n, slime.s, slime.w, slime.e,
			slime.nw, slime.ne, slime.sw, slime.se]],
	]
	for c in checks:
		var src := ts.get_source(int(c[0])) as TileSetAtlasSource
		assert(src != null, "tileset missing source %d" % int(c[0]))
		for coord: Vector2i in c[1]:
			assert(src.has_tile(coord), "source %d has no tile %s" % [int(c[0]), coord])


func _populate(walk: Dictionary, taken: Dictionary, spots: Array, gap: int) -> Array[Vector2i]:
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


## Expand [name, type, spot, count] rows into individual hostiles spread around
## their authored anchor, which is how the surface map's roster is written.
func _mobs(walk: Dictionary, taken: Dictionary, plan: Array, gap: int) -> Array:
	var spots: Array[Vector2i] = []
	var names: Array[String] = []
	var types: Array[String] = []
	for row in plan:
		var count: int = int(row[3])
		for i in count:
			var ring: Vector2i = Vector2i(
				int(round(cos(float(i) * 2.1) * float(gap) * 1.6)),
				int(round(sin(float(i) * 2.1) * float(gap) * 1.6)))
			spots.append(row[2] + ring)
			names.append("%s%d" % [row[0], i + 1] if count > 1 else str(row[0]))
			types.append(row[1])
	var cells := _populate(walk, taken, spots, gap)
	var out: Array = []
	for i in cells.size():
		out.append({
			"name": names[i],
			"type": TYPES + types[i] + ".tres",
			"pos": LevelKit.tile_pos_sized(cells[i], TILE),
		})
	return out


func _lights(name: String, cells: Array[Vector2i], colour: String, energy: float,
		scale: float) -> Array:
	var out: Array = []
	for i in cells.size():
		out.append({
			"name": "%s%d" % [name, i + 1],
			"pos": LevelKit.tile_pos_sized(cells[i], TILE),
			"color": colour,
			"energy": energy,
			"scale": scale,
		})
	return out


## Evenly spaced sample of a mask, for dropping lights along a river.
func _sample(mask: Dictionary, step: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}
	var keys: Array = mask.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a.x * 10000 + a.y) < (b.x * 10000 + b.y))
	for cell: Vector2i in keys:
		var k := Vector2i(cell.x / step, cell.y / step)
		if seen.has(k):
			continue
		seen[k] = true
		out.append(cell)
	return out


# --- The Sewers (surface hub) ------------------------------------------------
# The widest, flattest of the three: a single hall the whole zone across, one
# river bending through it and a shallow branch off the north side. This map is
# the hub, so it carries entrance 28, the overworld portal 128 and the three
# landing/stair pairs down to the sub-levels.

func _build_sewers() -> void:
	_size(140, 105)
	var ts: TileSet = load(TS)
	_require(ts)
	var ground := _layer(ts)
	var walls := _layer(ts)
	var props := _layer(ts)
	var overlay := _layer(ts)

	var floor_mask := _seal_interior(_open_zone(6, 0.16, 7101))
	var slime: Dictionary = {}
	var flow: Dictionary = {}
	_river(slime, flow, floor_mask, float(H) * 0.56, 7.0, 0.055, 5, 7110)
	_river_v(slime, flow, floor_mask, float(W) * 0.30, 5.0, 0.06, 4, 7111)

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	_paint_ground(ground, floor_mask, void_mask)
	var flowing := _paint_slime(ground, slime, flow)

	var blocked: Dictionary = {}
	var runs := MapKit.paint_wall3(walls, overlay, floor_mask, void_mask, _wall_spec(),
		_bounds, blocked, 8, 7120)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, Vector2i(W / 2, H - 12))
	walk = MapKit.largest_region(walk, entrance)
	var portal := LevelKit.pick_open(walk, entrance + Vector2i(0, 5))
	var boss_cell := LevelKit.pick_open(walk, Vector2i(W / 2, 14))

	var free: Dictionary = {}
	var no_build := LevelKit.keepout([entrance, portal], 6)
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell) and not slime.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 5)
	LevelKit.scatter_props(props, SRC_PROPS, edges, [
		[35, 16, 1, 2], [37, 16, 1, 2], [39, 16, 1, 2],
	], 0.22, 3, 7130, free, solid)
	LevelKit.scatter_props(props, SRC_PROPS, inner, [
		[26, 23, 1, 1], [28, 23, 1, 1], [30, 23, 1, 1],
	], 0.14, 4, 7131, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)
	LevelKit.scatter_flat(overlay, SRC_PROPS, edges, [
		Vector2i(1, 4), Vector2i(4, 4), Vector2i(8, 4),
	], 0.10, 4, 7132, solid)

	var taken := LevelKit.keepout([entrance, portal], 9)
	for cell: Vector2i in LevelKit.keepout([boss_cell], 12).keys():
		taken[cell] = true
	var hostiles := _mobs(walk, taken, [
		["Slime", "trpg/trpg_slime", Vector2i(int(W * 0.34), int(H * 0.62)), 3],
		["SlimeE", "trpg/trpg_slime", Vector2i(int(W * 0.66), int(H * 0.62)), 3],
		["Bat", "trpg/trpg_bat", Vector2i(int(W * 0.18), int(H * 0.48)), 3],
		["BatE", "trpg/trpg_bat", Vector2i(int(W * 0.82), int(H * 0.48)), 3],
		["SewerSkeleton", "trpg/trpg_sewer_skeleton", Vector2i(W / 2, int(H * 0.44)), 3],
		["AcidOoze", "trpg/trpg_acid_ooze", Vector2i(int(W * 0.24), int(H * 0.26)), 2],
		["AcidOozeE", "trpg/trpg_acid_ooze", Vector2i(int(W * 0.76), int(H * 0.26)), 2],
		["Crawler", "trpg/trpg_carrion_crawler", Vector2i(int(W * 0.32), int(H * 0.38)), 2],
		["CrawlerE", "trpg/trpg_carrion_crawler", Vector2i(int(W * 0.68), int(H * 0.38)), 2],
		["ZombieGiant", "trpg/trpg_zombie_giant", Vector2i(int(W * 0.26), int(H * 0.34)), 2],
		["ZombieGiantE", "trpg/trpg_zombie_giant", Vector2i(int(W * 0.74), int(H * 0.34)), 2],
		["SewerGorgon", "trpg/trpg_sewer_gorgon", Vector2i(int(W * 0.40), int(H * 0.30)), 2],
		["SewerGorgonE", "trpg/trpg_sewer_gorgon", Vector2i(int(W * 0.60), int(H * 0.30)), 2],
		["Devourer", "trpg/trpg_intellect_devourer", Vector2i(W / 2, int(H * 0.34)), 2],
		["CisternHulk", "trpg/trpg_cistern_hulk", Vector2i(W / 2, int(H * 0.24)), 2],
	], 5)
	hostiles.append({
		"name": "BloatedSovereign",
		"type": TYPES + "bosses/cistern_sovereign.tres",
		"pos": LevelKit.tile_pos_sized(boss_cell, TILE),
	})

	# Landing / stair pairs are placed far apart so the two descents never sit on
	# the same wing of the hall.
	var gutter_land := LevelKit.pick_open(walk, Vector2i(12, 12))
	var cistern_land := LevelKit.pick_open(walk, Vector2i(W - 12, 12))
	var ossuary_land := LevelKit.pick_open(walk, Vector2i(W / 2 - 4, H - 16))

	var glow := _sample(slime, 26)
	assert(walk.has(entrance) and walk.has(portal), "sewers spawn blocked")
	assert(walk.size() > 4000, "sewers too small: %d" % walk.size())
	_report.append("  sewers        walk=%d walls=%d runs=%d slime=%d flow=%d mobs=%d" % [
		walk.size(), walls.get_used_cells().size(), runs, slime.size(), flowing, hostiles.size()])

	LevelKit.write_map({
		"root": "sewers",
		"out": MAPS + "sewers.tscn",
		"tileset": TS,
		"bg": "Color(0.015, 0.025, 0.02, 1)",
		"modulate": "Color(0.50, 0.54, 0.50, 1)",
		"music": "res://assets/audio/music/alone.ogg",
		"layers": {
			"Ground": LevelKit.b64(ground), "Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props), "Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * TILE + TILE, "cam_bottom": H * TILE + TILE,
		"lights": _lights("SewerGlow", glow, "Color(0.45, 0.95, 0.5, 1)", 0.20, 1.6),
		"camps": [{"name": "Campfire", "pos": LevelKit.tile_pos_sized(entrance + Vector2i(2, -2), TILE)}],
		"decos": [],
		"hostiles": hostiles,
		"npcs": [],
		"spawn": LevelKit.tile_pos_sized(entrance, TILE),
		"warpers": [
			{"name": "Entrance", "pos": LevelKit.tile_pos_sized(entrance, TILE), "id": 28},
			{"name": "GutterLanding", "pos": LevelKit.tile_pos_sized(gutter_land, TILE), "id": 52},
			{"name": "CisternLanding", "pos": LevelKit.tile_pos_sized(cistern_land, TILE), "id": 53},
			{"name": "OssuaryLanding", "pos": LevelKit.tile_pos_sized(ossuary_land, TILE), "id": 56},
		],
		"portals": [
			{"name": "Portal", "pos": LevelKit.tile_pos_sized(portal, TILE), "id": 128,
				"target_id": 28, "instance": OVERWORLD, "label": "Castle Garden",
				"color": "Color(0, 0.53, 0.27, 1)"},
			{"name": "GutterStair", "pos": LevelKit.tile_pos_sized(gutter_land + Vector2i(0, 2), TILE),
				"id": 152, "target_id": 42, "instance": INST + "gutterworks.tres",
				"label": "The Gutterworks", "color": "Color(0.45, 0.7, 0.5, 1)"},
			{"name": "CisternStair", "pos": LevelKit.tile_pos_sized(cistern_land + Vector2i(0, 2), TILE),
				"id": 153, "target_id": 43, "instance": INST + "drowned_cistern.tres",
				"label": "The Drowned Cistern", "color": "Color(0.2, 0.5, 0.55, 1)"},
			{"name": "OssuaryStair", "pos": LevelKit.tile_pos_sized(ossuary_land + Vector2i(0, 2), TILE),
				"id": 156, "target_id": 46, "instance": INST + "ossuary.tres",
				"label": "The Ossuary", "color": "Color(0.45, 0.28, 0.7, 1)"},
		],
	})


# --- The Gutterworks --------------------------------------------------------
# The lowest and wettest of the three: two broad rivers converging across an
# open works floor, lit green off the sewage itself.

func _build_gutterworks() -> void:
	_size(200, 150)
	var ts: TileSet = load(TS)
	var ground := _layer(ts)
	var walls := _layer(ts)
	var props := _layer(ts)
	var overlay := _layer(ts)

	var floor_mask := _seal_interior(_open_zone(7, 0.20, 8201))
	var slime: Dictionary = {}
	var flow: Dictionary = {}
	_river(slime, flow, floor_mask, float(H) * 0.34, 9.0, 0.040, 6, 8210)
	_river(slime, flow, floor_mask, float(H) * 0.70, 9.0, 0.035, 6, 8211)
	_river_v(slime, flow, floor_mask, float(W) * 0.52, 7.0, 0.045, 5, 8212)

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	_paint_ground(ground, floor_mask, void_mask)
	var flowing := _paint_slime(ground, slime, flow)

	var blocked: Dictionary = {}
	var runs := MapKit.paint_wall3(walls, overlay, floor_mask, void_mask, _wall_spec(),
		_bounds, blocked, 8, 8220)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, Vector2i(W / 2, H - 14))
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + Vector2i(0, 6))

	var no_build := LevelKit.keepout([entrance, exit_cell], 6)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell) and not slime.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 5)
	LevelKit.scatter_props(props, SRC_PROPS, edges, [
		[35, 16, 1, 2], [37, 16, 1, 2], [39, 16, 1, 2],
	], 0.24, 3, 8230, free, solid)
	LevelKit.scatter_props(props, SRC_PROPS, inner, [
		[26, 23, 1, 1], [28, 23, 1, 1], [30, 23, 1, 1], [32, 23, 1, 1],
	], 0.15, 4, 8231, free, solid)
	LevelKit.scatter_props(props, SRC_PROPS, edges, [
		[0, 28, 2, 1], [3, 28, 2, 1], [6, 28, 2, 1],
	], 0.12, 4, 8232, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)
	LevelKit.scatter_flat(overlay, SRC_PROPS, edges, [
		Vector2i(1, 4), Vector2i(4, 4), Vector2i(8, 4), Vector2i(12, 4),
	], 0.11, 4, 8233, solid)
	LevelKit.scatter_flat(props, SRC_PROPS, inner, [
		Vector2i(38, 41), Vector2i(41, 41), Vector2i(44, 41),
	], 0.09, 5, 8234, solid)

	var taken := LevelKit.keepout([entrance, exit_cell], 9)
	var hostiles := _mobs(walk, taken, [
		["Slime", "trpg/trpg_slime", Vector2i(int(W * 0.22), int(H * 0.72)), 5],
		["GutterBat", "trpg/trpg_bat", Vector2i(int(W * 0.78), int(H * 0.30)), 5],
		["AcidOoze", "trpg/trpg_acid_ooze", Vector2i(int(W * 0.24), int(H * 0.26)), 4],
		["Zombie", "trpg/trpg_zombie_giant", Vector2i(int(W * 0.52), int(H * 0.20)), 3],
		["Crawler", "trpg/trpg_carrion_crawler", Vector2i(int(W * 0.72), int(H * 0.58)), 3],
		["Skeleton", "trpg/trpg_sewer_skeleton", Vector2i(int(W * 0.36), int(H * 0.48)), 4],
	], 5)
	var npc_cells := _populate(walk, taken, [
		entrance + Vector2i(-6, -3), entrance + Vector2i(6, -3)], 3)

	var glow := _sample(slime, 24)
	assert(walk.has(entrance) and walk.has(exit_cell), "gutterworks spawn blocked")
	assert(walk.size() > 6000, "gutterworks too small: %d" % walk.size())
	_report.append("  gutterworks   walk=%d walls=%d runs=%d slime=%d flow=%d mobs=%d" % [
		walk.size(), walls.get_used_cells().size(), runs, slime.size(), flowing, hostiles.size()])

	LevelKit.write_map({
		"root": "gutterworks",
		"out": MAPS + "gutterworks.tscn",
		"tileset": TS,
		"bg": "Color(0.02, 0.03, 0.02, 1)",
		"modulate": "Color(0.48, 0.53, 0.48, 1)",
		"music": "res://assets/audio/music/alone.ogg",
		"playlist": ["res://assets/audio/music/army_of_darkness.ogg"],
		"layers": {
			"Ground": LevelKit.b64(ground), "Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props), "Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * TILE + TILE, "cam_bottom": H * TILE + TILE,
		"lights": _lights("SlimeGlow", glow, "Color(0.42, 1.0, 0.45, 1)", 0.21, 1.5),
		"camps": [{"name": "CrewBrazier", "pos": LevelKit.tile_pos_sized(entrance + Vector2i(3, -3), TILE)}],
		"decos": [],
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


# --- The Drowned Cistern ----------------------------------------------------
# The flooded one: a reservoir that is mostly sewage, crossed by stone
# causeways, with the dry ground pushed out to the rim. Cold cyan ambient.

func _build_cistern() -> void:
	_size(220, 165)
	var ts: TileSet = load(TS)
	var ground := _layer(ts)
	var walls := _layer(ts)
	var props := _layer(ts)
	var overlay := _layer(ts)

	var floor_mask := _seal_interior(_open_zone(7, 0.18, 9301))

	# A broad central lake rather than channels, then causeways cut back through
	# it so the space stays crossable and mobs keep dry ground to hold.
	var slime: Dictionary = {}
	var cx := float(W) * 0.5
	var cy := float(H) * 0.5
	for cell: Vector2i in floor_mask.keys():
		var nx: float = (float(cell.x) - cx) / (float(W) * 0.40)
		var ny: float = (float(cell.y) - cy) / (float(H) * 0.40)
		var d: float = sqrt(nx * nx + ny * ny)
		var n: float = MapKit.value_noise(float(cell.x), float(cell.y), 22.0, 9310)
		if d < 0.95 + 0.35 * (n - 0.5):
			slime[cell] = true
	for cell: Vector2i in floor_mask.keys():
		if absi(cell.y - int(cy)) < 4 or absi(cell.x - int(cx)) < 4:
			slime.erase(cell)

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	_paint_ground(ground, floor_mask, void_mask)
	# A reservoir is still water; no current ribbon runs across it.
	var flowing := _paint_slime(ground, slime, {})

	var blocked: Dictionary = {}
	var runs := MapKit.paint_wall3(walls, overlay, floor_mask, void_mask, _wall_spec(),
		_bounds, blocked, 8, 9320)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, Vector2i(W / 2, H - 14))
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + Vector2i(0, 6))

	var no_build := LevelKit.keepout([entrance, exit_cell], 6)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell) and not slime.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 5)
	LevelKit.scatter_props(props, SRC_PROPS, edges, [
		[35, 16, 1, 2], [37, 16, 1, 2],
	], 0.20, 3, 9330, free, solid)
	LevelKit.scatter_props(props, SRC_PROPS, inner, [
		[26, 23, 1, 1], [28, 23, 1, 1], [30, 23, 1, 1],
	], 0.13, 4, 9331, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)
	LevelKit.scatter_flat(overlay, SRC_PROPS, edges, [
		Vector2i(1, 4), Vector2i(4, 4), Vector2i(8, 4),
	], 0.10, 4, 9332, solid)

	var taken := LevelKit.keepout([entrance, exit_cell], 9)
	var hostiles := _mobs(walk, taken, [
		["Crawler", "trpg/trpg_carrion_crawler", Vector2i(int(W * 0.26), int(H * 0.30)), 4],
		["AcidOoze", "trpg/trpg_acid_ooze", Vector2i(int(W * 0.74), int(H * 0.30)), 4],
		["Gorgon", "trpg/trpg_sewer_gorgon", Vector2i(int(W * 0.26), int(H * 0.70)), 4],
		["Devourer", "trpg/trpg_intellect_devourer", Vector2i(int(W * 0.74), int(H * 0.70)), 4],
		["Zombie", "trpg/trpg_zombie_giant", Vector2i(int(W * 0.50), int(H * 0.22)), 4],
		["Hulk", "trpg/trpg_cistern_hulk", Vector2i(int(W * 0.50), int(H * 0.78)), 4],
	], 5)
	var npc_cells := _populate(walk, taken, [entrance + Vector2i(-6, -3)], 3)

	var glow := _sample(slime, 30)
	assert(walk.has(entrance) and walk.has(exit_cell), "cistern spawn blocked")
	assert(walk.size() > 6000, "cistern too small: %d" % walk.size())
	_report.append("  cistern       walk=%d walls=%d runs=%d slime=%d flow=%d mobs=%d" % [
		walk.size(), walls.get_used_cells().size(), runs, slime.size(), flowing, hostiles.size()])

	LevelKit.write_map({
		"root": "drowned_cistern",
		"out": MAPS + "drowned_cistern.tscn",
		"tileset": TS,
		"bg": "Color(0.012, 0.022, 0.024, 1)",
		# Cold and slightly blue, against the Gutterworks' neutral green.
		"modulate": "Color(0.46, 0.53, 0.58, 1)",
		"music": "res://assets/audio/music/alone.ogg",
		"playlist": ["res://assets/audio/music/fungus.ogg"],
		"layers": {
			"Ground": LevelKit.b64(ground), "Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props), "Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * TILE + TILE, "cam_bottom": H * TILE + TILE,
		"lights": _lights("WaterGlow", glow, "Color(0.38, 0.86, 0.92, 1)", 0.22, 1.7),
		"camps": [{"name": "LandingFire", "pos": LevelKit.tile_pos_sized(entrance + Vector2i(3, -3), TILE)}],
		"decos": [],
		"hostiles": hostiles,
		"npcs": [
			{"name": "DrownedKeeperVess", "resource": NPCS + "sewers/drowned_keeper_vess.tres",
				"pos": LevelKit.tile_pos_sized(npc_cells[0], TILE)},
		],
		"spawn": LevelKit.tile_pos_sized(entrance, TILE),
		"warpers": [{"name": "Entrance", "pos": LevelKit.tile_pos_sized(entrance, TILE), "id": 43}],
		"portals": [{
			"name": "AscentPortal", "pos": LevelKit.tile_pos_sized(exit_cell, TILE),
			"id": 143, "target_id": 53, "instance": INST + "sewers.tres",
			"label": "The Sewers", "color": "Color(0.35, 0.62, 0.68, 1)",
		}],
	})
