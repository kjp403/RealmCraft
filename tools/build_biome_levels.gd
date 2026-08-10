extends SceneTree
## Build the upper and lower levels for Desert, Fire Forge and Sewers.
##
## This never opens desert.tscn / fire_forge.tscn / sewers.tscn. Those three
## maps are finished; the levels here are separate scenes that share their
## tilesets and their wall-resolution rules so a player reads them as floors of
## the same place rather than as unrelated zones.
##
## Each level reuses its biome's proven RimSpec for the *border* of the void —
## that is the code path already shipping, and it is what keeps a new map free
## of the invisible-wall class of bug. Levels differentiate themselves through
## floor material, deep-void mass, prop vocabulary, lighting, layout topology
## and population, drawing almost entirely on atlas banks the surface maps
## never paint.
##
##   godot --headless --path . -s tools/build_biome_levels.gd

const OUT := "res://source/common/gameplay/maps/maps/"
const INST := "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const TYPES := "res://source/common/gameplay/characters/npc/types/"
const NPCS := "res://source/common/gameplay/characters/npc/npcs/"

const DESERT_TS := "res://source/common/gameplay/maps/tilesets/desert_tileset.tres"
const FORGE_TS := "res://source/common/gameplay/maps/tilesets/fire_forge_tileset.tres"
const SEWERS_TS := "res://source/common/gameplay/maps/tilesets/sewers_tileset.tres"

var W: int = 96
var H: int = 72
var _bounds := Rect2i(0, 0, 96, 72)
var _report: Array[String] = []

## Layout scale for sub-levels. Authored coordinates / radii below describe the
## original compact maps; `_L` / `_R` / `_N` expand them so large TRPG sprites
## have room to move (Mining Cave freedom standard). Atlas cells are never
## scaled — only world layout.
const S := 5


func _L(x: int, y: int) -> Vector2i:
	return Vector2i(x * S, y * S)


func _R(v: float) -> float:
	return v * float(S)


func _N(n: int) -> int:
	return n * S


func _dense(rate: float) -> float:
	# Keep absolute prop counts stable as floor area grows with S^2.
	return rate / float(S * S)


func _gap(n: int) -> int:
	return maxi(n, int((n * S) / 2.0))


func _initialize() -> void:
	_build_desert_terraces()
	_build_desert_tombs()
	_build_sewers_gutterworks()
	_build_sewers_cistern()
	_build_forge_gallery()
	_build_forge_deeps()
	for line in _report:
		print(line)
	print("BIOME_LEVELS_PASS")
	quit(0)


func _set_size(w: int, h: int) -> void:
	W = w
	H = h
	_bounds = Rect2i(0, 0, w, h)


## Shared shaping, same contract as `build_stub_biomes.gd`: chambers joined by
## wandering tunnels, smoothed, trimmed to a solid margin, reduced to the single
## region containing `anchor`.
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
	return MapKit.largest_region(smoothed, LevelKit.pick_open(smoothed, anchor))


## A ring of chambers around a hollow centre — used where a level should loop
## instead of branching off a spine.
func _ring(centre: Vector2i, radius: int, count: int, size: float, seed_value: int) -> Array:
	var out: Array = []
	for i in count:
		var a: float = TAU * float(i) / float(count)
		var c := centre + Vector2i(int(cos(a) * radius), int(sin(a) * radius * 0.72))
		out.append([c, size, 0.26, seed_value + i])
	return out


func _ring_links(centre: Vector2i, radius: int, count: int, width: float, seed_value: int) -> Array:
	var out: Array = []
	for i in count:
		var a: float = TAU * float(i) / float(count)
		var b: float = TAU * float((i + 1) % count) / float(count)
		var p := centre + Vector2i(int(cos(a) * radius), int(sin(a) * radius * 0.72))
		var q := centre + Vector2i(int(cos(b) * radius), int(sin(b) * radius * 0.72))
		out.append([p, q, width, 2.5 * float(S), seed_value + i])
	return out


func _rim(
	source: int, fill: Array, n: Array, s: Array, w: Array, e: Array,
	nw: Vector2i, ne: Vector2i, sw: Vector2i, se: Vector2i, face_rows: int = 0
) -> MapKit.RimSpec:
	return LevelKit.rim_spec(source, fill, n, s, w, e, nw, ne, sw, se, face_rows)


## The desert cliff ring, verbatim from the surface map so both levels resolve
## their rock edges identically. `face_rows = 2` because this art hangs two rows
## below its own cell.
func _desert_rim() -> MapKit.RimSpec:
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
	return spec


func _sewers_rim() -> MapKit.RimSpec:
	return _rim(
		0,
		[Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0), Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)],
		[Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)],
		[Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)],
		[Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3)],
		Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 4), Vector2i(5, 4)
	)


func _forge_rim() -> MapKit.RimSpec:
	return _rim(
		3,
		[Vector2i(2, 2), Vector2i(3, 2)],
		[Vector2i(2, 1), Vector2i(3, 1)],
		[Vector2i(2, 3), Vector2i(3, 3)],
		[Vector2i(1, 2)],
		[Vector2i(4, 2)],
		Vector2i(1, 1), Vector2i(4, 1), Vector2i(1, 3), Vector2i(4, 3)
	)


## Restyle the deep mass of rock behind the rim. The border tiles `paint_rim`
## chose are left alone, so edges still resolve correctly while the interior
## reads as a different material.
func _restyle_deep(walls: TileMapLayer, void_mask: Dictionary, source: int, tiles: Array, seed_value: int) -> int:
	var n: int = 0
	for cell in LevelKit.deep_void(void_mask):
		walls.set_cell(cell, source, MapKit._pick(tiles, cell, seed_value))
		n += 1
	return n


func _new_layer(ts: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	return layer


func _log(name: String, walk: Dictionary, walls: TileMapLayer, props: TileMapLayer, hostiles: Array) -> void:
	_report.append(
		"  %-20s walk=%-5d walls=%-5d props=%-4d mobs=%d"
		% [name, walk.size(), walls.get_used_cells().size(), props.get_used_cells().size(), hostiles.size()]
	)


## Place a population entry on the nearest free walkable cell to its authored
## spot, keeping mobs off each other and off the arrival tiles.
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


# =============================================================================
# DESERT — Sunspire Terraces (up) and The Sunken Tombs (down)
# =============================================================================

# --- Sunspire Terraces -------------------------------------------------------
# Wind-scoured mesa tops above the basin. A single loop of terraces around a
# central spire so the level circles instead of branching, with the caravan camp
# at the arrival end. Draws on three atlas banks the basin never touches: the
# Props monuments, the Sand dune overlays, and the OutdoorHouseSet paving.

func _build_desert_terraces() -> void:
	_set_size(_N(100), _N(74))
	var ts: TileSet = load(DESERT_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	var arrival := _L(50, 64)
	var centre := _L(50, 36)
	var chambers: Array = [[_L(50, 63), _R(9.0), 0.26, 201]]
	chambers.append_array(_ring(centre, _N(38), 7, _R(9.5), 210))
	var links: Array = [[_L(50, 58), _L(50, 50), _R(3.0), _R(2.0), 220]]
	links.append_array(_ring_links(centre, _N(38), 7, _R(2.8), 230))
	var floor_mask := _carve(chambers, links, _N(4), arrival)

	# The spire the terraces circle: a solid mesa left standing in the middle.
	var spire: Dictionary = {}
	MapKit.blob(spire, centre, _R(11.0), 0.24, 240, _bounds)
	spire = MapKit.smooth(spire, _bounds, 1, 5, 4)
	for cell: Vector2i in spire.keys():
		floor_mask.erase(cell)
	floor_mask = MapKit.largest_region(floor_mask, LevelKit.pick_open(floor_mask, arrival))

	var sand := [
		Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 2),
		Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3),
	]
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, 0, MapKit._pick(sand, cell, 251))

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 0, Vector2i(7, 6))
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, _desert_rim(), _bounds, blocked)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, arrival)
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + _L(0, 5))

	var no_build := LevelKit.keepout([entrance, exit_cell], _gap(4))
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, _gap(3))
	# Tall monuments need a block of clear cells, so they anchor on interior
	# floor rather than the nearest free cell — which is often against a cliff
	# where the stamp would silently fail to fit.
	var inner_free: Dictionary = {}
	for cell: Vector2i in inner:
		if free.has(cell):
			inner_free[cell] = true

	# Monuments first: they are the landmarks the loop navigates by, so they get
	# their pick of open ground before the scatter fills the gaps.
	var monuments: Array = [
		[Vector2i(50, 12), [0, 0, 3, 8]],    # great obelisk, north gate
		[_L(16, 32), [2, 2, 3, 6]],    # lesser obelisk, west terrace
		[_L(84, 32), [2, 2, 3, 6]],    # lesser obelisk, east terrace
		[_L(24, 58), [4, 4, 2, 4]],    # roadside shrines on the south run
		[_L(76, 58), [4, 4, 2, 4]],
		[_L(30, 16), [0, 8, 2, 3]],    # stepped bases flanking the spire
		[_L(70, 16), [2, 8, 2, 3]],
		[_L(50, 54), [4, 8, 2, 3]],
	]
	for m in monuments:
		LevelKit.stamp_landmark(props, 1, m[1], LevelKit.pick_open(inner_free, m[0]), inner_free, solid)
		free.erase(LevelKit.pick_open(inner_free, m[0]))
	# Sun-bleached bones and dead trees on the exposed rims.
	for b in [
		[Vector2i(14, 48), [0, 11, 3, 5]], [Vector2i(86, 48), [3, 11, 2, 3]],
		[_L(22, 20), [0, 16, 3, 5]], [_L(78, 20), [4, 16, 2, 2]],
	]:
		LevelKit.stamp_landmark(props, 1, b[1], LevelKit.pick_open(inner_free, b[0]), inner_free, solid)
	for cell: Vector2i in solid.keys():
		free.erase(cell)

	# Boulders hug the cliff feet, cacti stand in the open.
	LevelKit.scatter_props(props, 0, edges, [[10, 7, 2, 2], [12, 7, 2, 2], [10, 1, 2, 2]], _dense(0.09), _N(5), 261, free, solid)
	LevelKit.scatter_props(props, 0, inner, [[10, 14, 1, 3], [11, 14, 1, 3], [12, 14, 1, 3]], _dense(0.045), _N(6), 262, free, solid)
	# Caravan urns and chests around the camp end.
	LevelKit.scatter_props(props, 1, inner, [[6, 0, 2, 2], [8, 0, 2, 2], [6, 2, 2, 2]], _dense(0.02), _N(9), 263, free, solid)
	# Stone lanterns ringing the camp. `free` already excludes the arrival
	# keepout, so these stay clear of the stair.
	for spot in [
		entrance + Vector2i(-8, -5), entrance + Vector2i(8, -5),
		entrance + Vector2i(-8, 4), entrance + Vector2i(8, 4),
		Vector2i(50, 52), Vector2i(22, 34), Vector2i(78, 34),
	]:
		LevelKit.stamp_landmark(props, 3, [1, 4, 1, 1], LevelKit.pick_open(free, spot), free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	# Flat detail: dry scrub, then the dune crests on the overlay layer so they
	# read as wind ripples drifting over everything else.
	LevelKit.scatter_flat(props, 0, inner, [
		Vector2i(10, 5), Vector2i(11, 5), Vector2i(12, 5), Vector2i(13, 5), Vector2i(14, 5),
	], _dense(0.10), _N(3), 264, solid)
	LevelKit.scatter_flat(props, 1, inner, [
		Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4),
		Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5),
	], _dense(0.015), _N(7), 265, solid)
	LevelKit.scatter_flat(overlay, 2, inner, [
		Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(3, 2),
		Vector2i(10, 1), Vector2i(11, 1), Vector2i(15, 2), Vector2i(16, 2),
	], _dense(0.07), _N(4), 266, {})
	# No paved apron here: every OutdoorHouseSet paving cell carries a collision
	# polygon (it is a platformer wall set) and the Ground sheet's cut slabs read
	# as a foreign grey patch dropped on open sand. The camp is marked instead by
	# its lanterns, fire and scrub, which is what the surface basin does too.

	var lit: Dictionary = LevelKit.keepout([entrance, exit_cell], _gap(2))
	var decos: Array = []
	var ti := 0
	for spot in [
		Vector2i(50, 20), Vector2i(22, 34), Vector2i(78, 34), Vector2i(30, 56),
		Vector2i(70, 56), Vector2i(50, 62), Vector2i(36, 46), Vector2i(64, 46),
	]:
		ti += 1
		decos.append({
			"name": "TerraceTorch%d" % ti,
			"frames": "deco_torch",
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"scale": 1.2,
			"light": 0.5,
			"color": "Color(1, 0.84, 0.55, 1)",
		})

	var critters: Array = []
	var names := ["critter_stag", "critter_boar", "critter_badger", "critter_wolf"]
	var ci := 0
	for spot in [
		_L(24, 44), _L(76, 44), _L(50, 30), _L(44, 58),
		_L(18, 36), _L(82, 36), _L(30, 24), _L(70, 24),
		_L(36, 52), _L(64, 52), _L(50, 40), _L(22, 56),
		_L(78, 56), _L(42, 18), _L(58, 18), _L(50, 62),
	]:
		critters.append({
			"name": "TerraceCritter%d" % (ci + 1),
			"frames": names[ci % names.size()],
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"scale": 0.9,
			"wander_radius": 48.0,
		})
		ci += 1

	# Population: raiders and cliff beasts working the loop.
	var taken := LevelKit.keepout([entrance, exit_cell], _gap(6))
	var mob_plan: Array = [
		["Harpy", "trpg/trpg_clawing_harpy", Vector2i(50, 18)],
		["Harpy2", "trpg/trpg_clawing_harpy", _L(44, 22)],
		["Harpy3", "trpg/trpg_clawing_harpy", _L(56, 22)],
		["Harpy4", "trpg/trpg_clawing_harpy", _L(34, 18)],
		["Harpy5", "trpg/trpg_clawing_harpy", _L(66, 18)],
		["Cockatrice", "trpg/trpg_lacerating_cockatrice", _L(22, 32)],
		["Cockatrice2", "trpg/trpg_lacerating_cockatrice", _L(78, 32)],
		["Cockatrice3", "trpg/trpg_lacerating_cockatrice", _L(50, 28)],
		["Cockatrice4", "trpg/trpg_lacerating_cockatrice", _L(30, 36)],
		["OrcRider", "trpg/trpg_orc_rider", _L(24, 50)],
		["OrcRider2", "trpg/trpg_orc_rider", _L(76, 50)],
		["OrcRider3", "trpg/trpg_orc_rider", _L(40, 54)],
		["OrcRider4", "trpg/trpg_orc_rider", _L(60, 54)],
		["DuneArcher", "trpg/trpg_archer", _L(34, 40)],
		["DuneArcher2", "trpg/trpg_archer", _L(66, 40)],
		["DuneArcher3", "trpg/trpg_archer", _L(28, 44)],
		["DuneArcher4", "trpg/trpg_archer", _L(72, 44)],
		["Fomorian", "trpg/trpg_wretched_fomorian", _L(50, 46)],
		["Fomorian2", "trpg/trpg_wretched_fomorian", _L(42, 38)],
		["Fomorian3", "trpg/trpg_wretched_fomorian", _L(58, 38)],
		["Orc", "trpg/trpg_orc", _L(20, 42)],
		["Orc2", "trpg/trpg_orc", _L(80, 42)],
	]
	var mob_cells := _populate(walk, taken, mob_plan.map(func(m: Array) -> Vector2i: return m[2]), _gap(4))
	var hostiles: Array = []
	for i in mob_plan.size():
		hostiles.append({
			"name": mob_plan[i][0],
			"type": TYPES + mob_plan[i][1] + ".tres",
			"pos": LevelKit.tile_pos(mob_cells[i]),
		})

	var npc_cells := _populate(walk, taken, [entrance + _L(-4, -2), entrance + _L(4, -2)], _gap(2))

	assert(walk.has(entrance) and walk.has(exit_cell), "terraces spawn blocked")
	assert(walk.size() > 35000, "terraces too small: %d" % walk.size())
	_log("sunspire_terraces", walk, walls, props, hostiles)

	LevelKit.write_map({
		"root": "sunspire_terraces",
		"out": OUT + "desert/sunspire_terraces.tscn",
		"tileset": DESERT_TS,
		"bg": "Color(0.11, 0.08, 0.06, 1)",
		"modulate": "Color(1, 0.94, 0.82, 1)",
		"music": "res://assets/audio/music/lost_woods.ogg",
		"layers": {
			"Ground": LevelKit.b64(ground),
			"Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props),
			"Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
		"camps": [{"name": "CaravanFire", "pos": LevelKit.tile_pos(entrance + _L(3, -3))}],
		"decos": decos,
		"critters": critters,
		"hostiles": hostiles,
		"npcs": [
			{"name": "CaravanMasterSefu", "resource": NPCS + "desert/caravan_master_sefu.tres",
				"pos": LevelKit.tile_pos(npc_cells[0])},
			{"name": "DuneScoutIlka", "resource": NPCS + "desert/dune_scout_ilka.tres",
				"pos": LevelKit.tile_pos(npc_cells[1])},
		],
		"spawn": LevelKit.tile_pos(entrance),
		"warpers": [{"name": "Entrance", "pos": LevelKit.tile_pos(entrance), "id": 40}],
		"portals": [{
			"name": "DescentPortal", "pos": LevelKit.tile_pos(exit_cell),
			"id": 140, "target_id": 50, "instance": INST + "desert.tres",
			"label": "Desert", "color": "Color(0.85, 0.66, 0.25, 1)",
		}],
	})


# --- The Sunken Tombs --------------------------------------------------------
# A burial complex under the basin: one long spine with paired alcoves, ending
# in a sealed king's chamber. The floor is cut sandstone rather than sand and
# the deep rock is the dark arch stone, so the level reads as excavated even
# though the wall border resolves with the same cliff ring as the surface.

func _build_desert_tombs() -> void:
	_set_size(_N(108), _N(84))
	var ts: TileSet = load(DESERT_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	var arrival := _L(54, 74)
	var floor_mask := _carve(
		[
			[Vector2i(54, 73), _R(8.0), 0.24, 301],   # stair hall
			[_L(54, 62), _R(7.0), 0.26, 302],
			[_L(32, 58), _R(7.5), 0.28, 303],   # paired alcoves down the spine
			[_L(76, 58), _R(7.5), 0.28, 304],
			[_L(54, 48), _R(7.0), 0.26, 305],
			[_L(28, 42), _R(8.0), 0.28, 306],
			[_L(80, 42), _R(8.0), 0.28, 307],
			[_L(54, 34), _R(7.5), 0.26, 308],
			[_L(34, 24), _R(7.0), 0.28, 309],
			[_L(74, 24), _R(7.0), 0.28, 310],
			[_L(54, 16), _R(13.0), 0.20, 311],  # king's chamber
		],
		[
			[Vector2i(54, 68), Vector2i(54, 56), _R(2.6), _R(1.8), 321],
			[_L(48, 60), _L(36, 58), _R(2.2), _R(2.4), 322],
			[_L(60, 60), _L(72, 58), _R(2.2), _R(2.4), 323],
			[_L(54, 54), _L(54, 42), _R(2.6), _R(1.8), 324],
			[_L(46, 46), _L(32, 42), _R(2.2), _R(2.6), 325],
			[_L(62, 46), _L(76, 42), _R(2.2), _R(2.6), 326],
			[_L(54, 40), _L(54, 26), _R(2.6), _R(1.8), 327],
			[_L(46, 30), _L(38, 24), _R(2.2), _R(2.4), 328],
			[_L(62, 30), _L(70, 24), _R(2.2), _R(2.4), 329],
			[_L(38, 22), _L(48, 16), _R(2.4), _R(2.2), 330],
			[_L(70, 22), _L(60, 16), _R(2.4), _R(2.2), 331],
		],
		_N(4),
		arrival
	)

	# Cut sandstone: the flat block bank, never painted on the surface.
	# Flat cut sandstone. Row 8 of this bank looks like floor on a contact sheet
	# but is the bottom half of the boulder sprite — tiling it carpets the whole
	# level in dark scallops. The genuinely flat slabs are rows 9-10, and only
	# columns 10-12: column 13 has transparent cut-outs punched through it.
	var slabs := [
		Vector2i(10, 9), Vector2i(11, 9), Vector2i(12, 9),
		Vector2i(10, 10), Vector2i(11, 10),
	]
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, 0, MapKit._pick(slabs, cell, 341))

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 0, Vector2i(7, 6))
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, _desert_rim(), _bounds, blocked)
	# Dark arch stone behind the rim — collision-marked already, so restyling it
	# cannot open a hole in the map.
	# The two cleanest cells of the arch interior. The neighbours carry tan brick
	# fragments that speckle when tiled across a mass this size.
	_restyle_deep(walls, void_mask, 0, [Vector2i(8, 12), Vector2i(7, 13)], 342)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, arrival)
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + _L(0, 5))
	var throne := LevelKit.pick_open(walk, _L(54, 16))

	var no_build := LevelKit.keepout([entrance, exit_cell], _gap(4))
	for cell: Vector2i in LevelKit.keepout([throne], _gap(6)).keys():
		no_build[cell] = true
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, _gap(3))

	# Sarcophagi line the alcoves — the gilded coffin bank on Ground rows 15-18.
	for spot in [
		Vector2i(32, 58), Vector2i(76, 58), Vector2i(28, 42), Vector2i(80, 42),
		Vector2i(34, 24), Vector2i(74, 24), Vector2i(46, 62), Vector2i(62, 62),
		Vector2i(44, 34), Vector2i(64, 34),
	]:
		var anchor := LevelKit.pick_open(free, spot)
		var bank: Array = [
			[0, 15, 1, 4], [1, 15, 1, 4], [2, 15, 1, 4],
		][MapKit.hash2(anchor.x, anchor.y, 351) % 3]
		LevelKit.stamp_landmark(props, 0, bank, anchor, free, solid)
	# Grave goods heaped against the walls.
	LevelKit.scatter_props(props, 1, edges, [[6, 0, 2, 2], [8, 0, 2, 2], [6, 2, 2, 2], [8, 2, 2, 2]], _dense(0.07), _N(5), 352, free, solid)
	LevelKit.scatter_props(props, 1, inner, [[0, 8, 2, 3], [2, 8, 2, 3], [4, 8, 2, 3]], _dense(0.035), _N(7), 353, free, solid)
	LevelKit.scatter_props(props, 1, edges, [[0, 11, 3, 5], [3, 11, 2, 3]], _dense(0.03), _N(8), 354, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	# Scattered urns and grit on the slabs.
	LevelKit.scatter_flat(props, 1, inner, [
		Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4),
		Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5),
		Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 6),
	], _dense(0.05), _N(4), 355, solid)
	LevelKit.scatter_flat(overlay, 0, inner, [
		Vector2i(10, 11), Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11),
	], _dense(0.02), _N(8), 356, {})

	var decos: Array = []
	var ti := 0
	for spot in [
		Vector2i(54, 73), Vector2i(54, 62), Vector2i(32, 58), Vector2i(76, 58),
		Vector2i(54, 48), Vector2i(28, 42), Vector2i(80, 42), Vector2i(54, 34),
		Vector2i(34, 24), Vector2i(74, 24), Vector2i(44, 16), Vector2i(64, 16),
	]:
		ti += 1
		decos.append({
			"name": "TombBrazier%d" % ti,
			"frames": "deco_torch" if ti % 3 != 0 else "deco_candle_a",
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"scale": 1.3,
			"light": 0.85,
			"color": "Color(0.6, 0.9, 0.75, 1)" if ti % 3 == 0 else "Color(1, 0.78, 0.42, 1)",
		})

	var lights: Array = []
	var li := 0
	for spot in [_L(54, 16), _L(48, 14), _L(60, 14)]:
		li += 1
		lights.append({
			"name": "ThroneGlow%d" % li,
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"color": "Color(0.5, 0.9, 0.8, 1)",
			"energy": 0.55,
			"scale": 1.6,
		})

	var critters: Array = []
	var names := ["critter_stag", "critter_boar", "critter_badger", "critter_wolf"]
	var ci := 0
	for spot in [
		_L(30, 64), _L(78, 64), _L(40, 50), _L(68, 50),
		_L(24, 36), _L(84, 36), _L(50, 56), _L(36, 28),
		_L(72, 28), _L(54, 40), _L(28, 52), _L(80, 52),
	]:
		critters.append({
			"name": "TombCritter%d" % (ci + 1),
			"frames": names[ci % names.size()],
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"scale": 0.85,
			"wander_radius": 40.0,
		})
		ci += 1

	var taken := LevelKit.keepout([entrance, exit_cell], _gap(6))
	var mob_plan: Array = [
		["TombSkeleton", "trpg/trpg_skeleton", Vector2i(54, 62)],
		["TombSkeleton2", "trpg/trpg_skeleton", _L(48, 60)],
		["TombSkeleton3", "trpg/trpg_skeleton", _L(60, 60)],
		["TombSkeleton4", "trpg/trpg_skeleton", _L(40, 64)],
		["TombSkeleton5", "trpg/trpg_skeleton", _L(68, 64)],
		["ArmoredSkeleton", "trpg/trpg_armored_skeleton", _L(32, 58)],
		["ArmoredSkeleton2", "trpg/trpg_armored_skeleton", _L(76, 58)],
		["ArmoredSkeleton3", "trpg/trpg_armored_skeleton", _L(44, 52)],
		["ArmoredSkeleton4", "trpg/trpg_armored_skeleton", _L(64, 52)],
		["BoneArcher", "trpg/trpg_skeleton_archer", _L(28, 42)],
		["BoneArcher2", "trpg/trpg_skeleton_archer", _L(80, 42)],
		["BoneArcher3", "trpg/trpg_skeleton_archer", _L(36, 36)],
		["BoneArcher4", "trpg/trpg_skeleton_archer", _L(72, 36)],
		["Greatsword", "trpg/trpg_greatsword_skeleton", _L(54, 48)],
		["Greatsword2", "trpg/trpg_greatsword_skeleton", _L(54, 34)],
		["Greatsword3", "trpg/trpg_greatsword_skeleton", _L(46, 42)],
		["Necromancer", "trpg/trpg_necromancer", _L(34, 24)],
		["Necromancer2", "trpg/trpg_necromancer", _L(74, 24)],
		["Necromancer3", "trpg/trpg_necromancer", _L(54, 22)],
		["Gorgon", "trpg/trpg_poisonous_gorgon", _L(44, 34)],
		["Gorgon2", "trpg/trpg_poisonous_gorgon", _L(64, 34)],
		["Gorgon3", "trpg/trpg_poisonous_gorgon", _L(54, 28)],
		["ThroneGuard", "trpg/trpg_armored_skeleton", _L(46, 18)],
		["ThroneGuard2", "trpg/trpg_armored_skeleton", _L(62, 18)],
		["ThroneGuard3", "trpg/trpg_armored_skeleton", _L(54, 16)],
	]
	var mob_cells := _populate(walk, taken, mob_plan.map(func(m: Array) -> Vector2i: return m[2]), _gap(4))
	var hostiles: Array = []
	for i in mob_plan.size():
		hostiles.append({
			"name": mob_plan[i][0],
			"type": TYPES + mob_plan[i][1] + ".tres",
			"pos": LevelKit.tile_pos(mob_cells[i]),
		})
	hostiles.append({
		"name": "SandKing",
		"type": TYPES + "bosses/sand_king.tres",
		"pos": LevelKit.tile_pos(throne),
	})

	var npc_cells := _populate(walk, taken, [entrance + _L(-4, -2)], _gap(2))

	assert(walk.has(entrance) and walk.has(exit_cell), "tombs spawn blocked")
	assert(walk.has(throne), "tombs throne blocked")
	assert(walk.size() > 35000, "tombs too small: %d" % walk.size())
	_log("sunken_tombs", walk, walls, props, hostiles)

	LevelKit.write_map({
		"root": "sunken_tombs",
		"out": OUT + "desert/sunken_tombs.tscn",
		"tileset": DESERT_TS,
		"bg": "Color(0.05, 0.04, 0.03, 1)",
		"modulate": "Color(0.62, 0.58, 0.52, 1)",
		"music": "res://assets/audio/music/shadow_temple.ogg",
		"layers": {
			"Ground": LevelKit.b64(ground),
			"Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props),
			"Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
		"camps": [{"name": "StairFire", "pos": LevelKit.tile_pos(entrance + _L(3, -3))}],
		"decos": decos,
		"lights": lights,
		"critters": critters,
		"hostiles": hostiles,
		"npcs": [{
			"name": "TombDelverAsha", "resource": NPCS + "desert/tomb_delver_asha.tres",
			"pos": LevelKit.tile_pos(npc_cells[0]),
		}],
		"spawn": LevelKit.tile_pos(entrance),
		"warpers": [{"name": "Entrance", "pos": LevelKit.tile_pos(entrance), "id": 41}],
		"portals": [{
			"name": "AscentPortal", "pos": LevelKit.tile_pos(exit_cell),
			"id": 141, "target_id": 51, "instance": INST + "desert.tres",
			"label": "Desert", "color": "Color(0.72, 0.6, 0.3, 1)",
		}],
	})


# =============================================================================
# SEWERS — The Gutterworks (up) and The Drowned Cistern (down)
# =============================================================================

# --- The Gutterworks ---------------------------------------------------------
# The maintenance level between the city and the culverts: a grid of service
# runs rather than a branching cave. Paved in DarkCastle cobble and hung with
# its banners, portcullises and gargoyles — a whole atlas source the culverts
# below never paint.

func _build_sewers_gutterworks() -> void:
	_set_size(_N(104), _N(78))
	var ts: TileSet = load(SEWERS_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

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
	# Grid of service runs: every neighbouring junction joined both ways.
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

	# DarkCastle cobble paving instead of the culverts' purple flagstone.
	var cobble := [Vector2i(0, 4), Vector2i(1, 4)]
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, 2, MapKit._pick(cobble, cell, 451))

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 0, Vector2i(7, 0))
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, _sewers_rim(), _bounds, blocked)
	# No deep-void restyle. DarkCastle's brickwork is high-contrast mortar that
	# tiles into visual static across a mass this size; the level takes its
	# identity from the cobble floor and the DarkCastle furniture instead, and
	# keeps the culverts' own quiet wall fill.

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, arrival)
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + _L(0, 5))

	var no_build := LevelKit.keepout([entrance, exit_cell], _gap(4))
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, _gap(3))

	# Junction furniture: portcullis frames and gargoyle heads at the crossings.
	for spot in [
		Vector2i(22, 20), Vector2i(52, 20), Vector2i(82, 20),
		Vector2i(22, 40), Vector2i(82, 40), Vector2i(22, 58), Vector2i(82, 58),
	]:
		LevelKit.stamp_landmark(props, 2, [3, 3, 1, 1], LevelKit.pick_open(free, spot), free, solid)
	# Wooden beams and brick piers from the pixel-dungeon shell.
	LevelKit.scatter_props(props, 0, edges, [[6, 4, 1, 2], [7, 4, 1, 2], [8, 4, 1, 2]], _dense(0.14), _N(4), 461, free, solid)
	LevelKit.scatter_props(props, 0, inner, [[6, 3, 1, 1], [7, 3, 1, 1], [8, 3, 1, 1]], _dense(0.05), _N(6), 462, free, solid)
	# Stores left behind by the works crews: chests, crates and cauldrons.
	LevelKit.scatter_props(props, 0, edges, [[0, 8, 1, 1], [1, 8, 1, 1], [2, 8, 1, 1], [3, 8, 1, 1], [4, 7, 1, 1]], _dense(0.05), _N(6), 463, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	# Drain grates and spilled stock on the cobbles.
	LevelKit.scatter_flat(props, 2, inner, [Vector2i(2, 4)], _dense(0.035), _N(5), 464, solid)
	LevelKit.scatter_flat(overlay, 0, inner, [
		Vector2i(9, 4), Vector2i(9, 5), Vector2i(7, 7), Vector2i(8, 6),
		Vector2i(6, 8), Vector2i(7, 8), Vector2i(9, 8),
	], _dense(0.055), _N(3), 465, {})
	# Banners hung on the wall faces flanking the runs.
	LevelKit.scatter_flat(overlay, 2, edges, [Vector2i(3, 0), Vector2i(4, 0)], _dense(0.05), _N(5), 466, solid)

	var decos: Array = []
	var ti := 0
	for spot in [
		Vector2i(22, 20), Vector2i(52, 20), Vector2i(82, 20),
		Vector2i(22, 40), Vector2i(52, 40), Vector2i(82, 40),
		Vector2i(22, 58), Vector2i(52, 58), Vector2i(82, 58), Vector2i(52, 67),
	]:
		ti += 1
		decos.append({
			"name": "GutterLamp%d" % ti,
			"frames": "deco_torch" if ti % 3 != 0 else "deco_candle_a",
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"scale": 1.35,
			"light": 0.9,
			"color": "Color(0.55, 0.95, 0.6, 1)" if ti % 3 == 0 else "Color(1, 0.74, 0.4, 1)",
		})

	var taken := LevelKit.keepout([entrance, exit_cell], _gap(6))
	var mob_plan: Array = [
		["Slime", "trpg/trpg_slime", Vector2i(22, 58)],
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
			"pos": LevelKit.tile_pos(mob_cells[i]),
		})

	var npc_cells := _populate(walk, taken, [entrance + _L(-4, -2), entrance + _L(4, -2)], _gap(2))

	assert(walk.has(entrance) and walk.has(exit_cell), "gutterworks spawn blocked")
	assert(walk.size() > 30000, "gutterworks too small: %d" % walk.size())
	_log("gutterworks", walk, walls, props, hostiles)

	LevelKit.write_map({
		"root": "gutterworks",
		"out": OUT + "sewers/gutterworks.tscn",
		"tileset": SEWERS_TS,
		"bg": "Color(0.02, 0.02, 0.03, 1)",
		"modulate": "Color(0.68, 0.7, 0.8, 1)",
		"music": "res://assets/audio/music/fungus.ogg",
		"layers": {
			"Ground": LevelKit.b64(ground),
			"Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props),
			"Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
		"camps": [{"name": "CrewBrazier", "pos": LevelKit.tile_pos(entrance + _L(3, -3))}],
		"decos": decos,
		"hostiles": hostiles,
		"npcs": [
			{"name": "SluiceWardenObry", "resource": NPCS + "sewers/sluice_warden_obry.tres",
				"pos": LevelKit.tile_pos(npc_cells[0])},
			{"name": "RatcatcherPell", "resource": NPCS + "sewers/ratcatcher_pell.tres",
				"pos": LevelKit.tile_pos(npc_cells[1])},
		],
		"spawn": LevelKit.tile_pos(entrance),
		"warpers": [{"name": "Entrance", "pos": LevelKit.tile_pos(entrance), "id": 42}],
		"portals": [{
			"name": "DescentPortal", "pos": LevelKit.tile_pos(exit_cell),
			"id": 142, "target_id": 52, "instance": INST + "sewers.tres",
			"label": "The Sewers", "color": "Color(0.35, 0.62, 0.4, 1)",
		}],
	})


# --- The Drowned Cistern -----------------------------------------------------
# One enormous flooded reservoir with a ring of holding tanks around it. Floored
# with the DG dungeon stone and its ornate hall mosaic, standing water in the
# pools bank, and rubble walls behind the rim. The boss holds the mosaic floor.

func _build_sewers_cistern() -> void:
	_set_size(_N(112), _N(86))
	var ts: TileSet = load(SEWERS_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	var arrival := _L(56, 76)
	var basin := _L(56, 38)
	var chambers: Array = [
		[Vector2i(56, 75), _R(7.5), 0.24, 501],
		[_L(56, 64), _R(7.0), 0.26, 502],
		[basin, _R(20.0), 0.14, 503],  # the reservoir itself
	]
	chambers.append_array(_ring(basin, _N(34), 7, _R(7.0), 510))
	var links: Array = [
		[Vector2i(56, 70), Vector2i(56, 58), _R(2.8), _R(1.8), 520],
		[_L(56, 58), basin, _R(3.0), _R(1.6), 521],
	]
	links.append_array(_ring_links(basin, _N(34), 7, _R(2.2), 530))
	# Spokes from the holding tanks into the reservoir.
	var seed_s := 540
	for i in 7:
		var a: float = TAU * float(i) / 7.0
		var p := basin + Vector2i(int(cos(a) * _N(34)), int(sin(a) * _N(34) * 0.72))
		links.append([p, basin, _R(2.0), _R(2.4), seed_s])
		seed_s += 1
	var floor_mask := _carve(chambers, links, _N(4), arrival)

	var dg_floor := [
		Vector2i(5, 13), Vector2i(6, 13), Vector2i(7, 13),
		Vector2i(8, 13), Vector2i(9, 13), Vector2i(10, 13),
	]
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, 3, MapKit._pick(dg_floor, cell, 551))

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 0, Vector2i(7, 0))
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, _sewers_rim(), _bounds, blocked)
	# Banded stone behind the rim (DG set1 rows 9-10, already collision). The
	# rubble bank one row down tiles into speckle at this scale; the banding
	# reads as a built reservoir wall and stays quiet.
	_restyle_deep(walls, void_mask, 3, [
		Vector2i(5, 9), Vector2i(6, 9), Vector2i(5, 10), Vector2i(6, 10),
	], 552)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, arrival)
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + _L(0, 5))
	var dais := LevelKit.pick_open(walk, basin)

	# The ornate hall mosaic laid as the reservoir's drained floor plate.
	var plate_origin := dais - Vector2i(2, 3)
	for oy in 7:
		for ox in 5:
			var cell := plate_origin + Vector2i(ox, oy)
			if walk.has(cell):
				ground.set_cell(cell, 3, Vector2i(21 + ox, 0 + oy))

	# Standing water pooled in the low ground around the reservoir. These tiles
	# carry no collision, so the water is wadeable rather than a barrier.
	var shallows: Dictionary = {}
	for spot in [
		[basin + Vector2i(-14, 4), _R(5.0), 561], [basin + Vector2i(14, 4), _R(5.0), 562],
		[basin + _L(-12, -8), _R(4.4), 563], [basin + _L(12, -8), _R(4.4), 564],
		[_L(56, 62), _R(4.0), 565],
	]:
		var pool: Dictionary = {}
		MapKit.blob(pool, spot[0], spot[1], 0.30, int(spot[2]), _bounds)
		pool = MapKit.smooth(pool, _bounds, 1, 5, 4)
		for cell: Vector2i in pool.keys():
			if walk.has(cell) and ground.get_cell_atlas_coords(cell).x < 21:
				shallows[cell] = true
	# Real water is a sparse-alpha sheet — paint it on Overlay over solid stone
	# so transparent pixels never punch holes through the map (Mining Cave rule).
	var water := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	for cell: Vector2i in shallows.keys():
		overlay.set_cell(cell, 4, MapKit._pick(water, cell, 566))

	var no_build := LevelKit.keepout([entrance, exit_cell], _gap(4))
	for cell: Vector2i in LevelKit.keepout([dais], _gap(7)).keys():
		no_build[cell] = true
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell) and not shallows.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, _gap(3))

	# Fallen pillars and stair blocks from the DG set, plus catacomb urns.
	for spot in [
		Vector2i(30, 30), Vector2i(82, 30), Vector2i(30, 52), Vector2i(82, 52),
		Vector2i(56, 20), Vector2i(40, 64), Vector2i(72, 64),
	]:
		LevelKit.stamp_landmark(props, 3, [16, 7, 3, 3], LevelKit.pick_open(free, spot), free, solid)
	for spot in [_L(38, 40), _L(74, 40), _L(56, 28)]:
		LevelKit.stamp_landmark(props, 3, [17, 10, 2, 4], LevelKit.pick_open(free, spot), free, solid)
	LevelKit.scatter_props(props, 0, edges, [[6, 4, 1, 2], [7, 4, 1, 2], [8, 4, 1, 2]], _dense(0.12), _N(5), 571, free, solid)
	LevelKit.scatter_props(props, 3, inner, [[2, 12, 1, 1]], _dense(0.04), _N(6), 572, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	LevelKit.scatter_flat(overlay, 3, inner, [
		Vector2i(19, 8), Vector2i(20, 8), Vector2i(21, 8),
	], _dense(0.02), _N(8), 573, solid)
	LevelKit.scatter_flat(overlay, 0, inner, [
		Vector2i(9, 4), Vector2i(9, 5), Vector2i(7, 7), Vector2i(8, 6),
	], _dense(0.06), _N(3), 574, solid)

	var decos: Array = []
	var ti := 0
	for spot in [
		Vector2i(56, 75), Vector2i(56, 64), Vector2i(30, 30), Vector2i(82, 30),
		Vector2i(30, 52), Vector2i(82, 52), Vector2i(56, 20), Vector2i(40, 64),
		Vector2i(72, 64), Vector2i(44, 44), Vector2i(68, 44),
	]:
		ti += 1
		decos.append({
			"name": "CisternLamp%d" % ti,
			"frames": "deco_candle_a" if ti % 2 == 0 else "deco_torch",
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"scale": 1.4,
			"light": 0.85,
			"color": "Color(0.5, 0.95, 0.72, 1)" if ti % 2 == 0 else "Color(1, 0.7, 0.36, 1)",
		})

	var lights: Array = []
	var li := 0
	for cell: Vector2i in shallows.keys():
		if MapKit.hash2(cell.x, cell.y, 575) % 41 != 0:
			continue
		li += 1
		lights.append({
			"name": "WaterGlow%d" % li,
			"pos": LevelKit.tile_pos(cell),
			"color": "Color(0.4, 0.85, 0.7, 1)",
			"energy": 0.4,
			"scale": 1.1,
		})

	var taken := LevelKit.keepout([entrance, exit_cell], _gap(6))
	var mob_plan: Array = [
		["Crawler", "trpg/trpg_carrion_crawler", Vector2i(56, 64)],
		["Crawler2", "trpg/trpg_carrion_crawler", _L(46, 60)],
		["Crawler3", "trpg/trpg_carrion_crawler", _L(66, 60)],
		["Crawler4", "trpg/trpg_carrion_crawler", _L(56, 52)],
		["AcidOoze", "trpg/trpg_acid_ooze", _L(30, 52)],
		["AcidOoze2", "trpg/trpg_acid_ooze", _L(82, 52)],
		["AcidOoze3", "trpg/trpg_acid_ooze", _L(30, 30)],
		["AcidOoze4", "trpg/trpg_acid_ooze", _L(82, 40)],
		["AcidOoze5", "trpg/trpg_acid_ooze", _L(56, 36)],
		["Gorgon", "trpg/trpg_sewer_gorgon", _L(82, 30)],
		["Gorgon2", "trpg/trpg_sewer_gorgon", _L(56, 20)],
		["Gorgon3", "trpg/trpg_sewer_gorgon", _L(40, 24)],
		["Gorgon4", "trpg/trpg_sewer_gorgon", _L(72, 24)],
		["Devourer", "trpg/trpg_intellect_devourer", _L(40, 40)],
		["Devourer2", "trpg/trpg_intellect_devourer", _L(72, 40)],
		["Devourer3", "trpg/trpg_intellect_devourer", _L(56, 44)],
		["Zombie", "trpg/trpg_zombie_giant", _L(44, 26)],
		["Zombie2", "trpg/trpg_zombie_giant", _L(68, 26)],
		["Zombie3", "trpg/trpg_zombie_giant", _L(56, 30)],
		["TankGuard", "trpg/trpg_cistern_hulk", _L(46, 48)],
		["TankGuard2", "trpg/trpg_cistern_hulk", _L(66, 48)],
		["TankGuard3", "trpg/trpg_cistern_hulk", _L(56, 48)],
		["Slime", "trpg/trpg_slime", _L(36, 56)],
		["Slime2", "trpg/trpg_slime", _L(76, 56)],
	]
	var mob_cells := _populate(walk, taken, mob_plan.map(func(m: Array) -> Vector2i: return m[2]), _gap(4))
	var hostiles: Array = []
	for i in mob_plan.size():
		hostiles.append({
			"name": mob_plan[i][0],
			"type": TYPES + mob_plan[i][1] + ".tres",
			"pos": LevelKit.tile_pos(mob_cells[i]),
		})
	hostiles.append({
		"name": "CisternSovereign",
		"type": TYPES + "bosses/cistern_sovereign.tres",
		"pos": LevelKit.tile_pos(dais),
	})

	var npc_cells := _populate(walk, taken, [entrance + _L(-4, -2)], _gap(2))

	assert(walk.has(entrance) and walk.has(exit_cell), "cistern spawn blocked")
	assert(walk.has(dais), "cistern dais blocked")
	assert(walk.size() > 35000, "cistern too small: %d" % walk.size())
	_log("drowned_cistern", walk, walls, props, hostiles)

	LevelKit.write_map({
		"root": "drowned_cistern",
		"out": OUT + "sewers/drowned_cistern.tscn",
		"tileset": SEWERS_TS,
		"bg": "Color(0.012, 0.022, 0.024, 1)",
		"modulate": "Color(0.6, 0.74, 0.72, 1)",
		"music": "res://assets/audio/music/shadow_temple.ogg",
		"layers": {
			"Ground": LevelKit.b64(ground),
			"Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props),
			"Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
		"camps": [{"name": "LandingFire", "pos": LevelKit.tile_pos(entrance + _L(3, -3))}],
		"decos": decos,
		"lights": lights,
		"hostiles": hostiles,
		"npcs": [{
			"name": "DrownedKeeperVess", "resource": NPCS + "sewers/drowned_keeper_vess.tres",
			"pos": LevelKit.tile_pos(npc_cells[0]),
		}],
		"spawn": LevelKit.tile_pos(entrance),
		"warpers": [{"name": "Entrance", "pos": LevelKit.tile_pos(entrance), "id": 43}],
		"portals": [{
			"name": "AscentPortal", "pos": LevelKit.tile_pos(exit_cell),
			"id": 143, "target_id": 53, "instance": INST + "sewers.tres",
			"label": "The Sewers", "color": "Color(0, 0.5, 0.34, 1)",
		}],
	})


# =============================================================================
# FIRE FORGE — The Bellows Gallery (up) and The Cinder Deeps (down)
# =============================================================================

# --- The Bellows Gallery -----------------------------------------------------
# The working floor above the foundry: two long masonry halls joined by cross
# bridges, dry and built rather than molten. Uses the DG Fire well rings and the
# lava sheet's braziers, coal heaps and crystal clusters — all unpainted below.

func _build_forge_gallery() -> void:
	_set_size(_N(104), _N(78))
	var ts: TileSet = load(FORGE_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	var arrival := _L(52, 68)
	var west := _N(30)
	var east := _N(74)
	var hall_rows := [_N(18), _N(30), _N(42), _N(54)]
	var chambers: Array = [[_L(52, 67), _R(7.5), 0.24, 601]]
	var seed_i := 610
	for ry in hall_rows:
		chambers.append([Vector2i(west, ry), _R(7.0), 0.26, seed_i])
		chambers.append([Vector2i(east, ry), _R(7.0), 0.26, seed_i + 50])
		seed_i += 1
	var links: Array = [
		[Vector2i(52, 64), Vector2i(west, _N(54)), _R(2.6), _R(2.2), 630],
		[_L(52, 64), Vector2i(east, _N(54)), _R(2.6), _R(2.2), 631],
	]
	var seed_j := 640
	for i in range(hall_rows.size() - 1):
		links.append([Vector2i(west, hall_rows[i]), Vector2i(west, hall_rows[i + 1]), _R(2.6), _R(1.8), seed_j])
		links.append([Vector2i(east, hall_rows[i]), Vector2i(east, hall_rows[i + 1]), _R(2.6), _R(1.8), seed_j + 40])
		seed_j += 1
	# Cross bridges between the two halls.
	for ry in [_N(18), _N(42)]:
		links.append([Vector2i(west, ry), Vector2i(east, ry), _R(2.0), _R(2.6), seed_j])
		seed_j += 1
	var floor_mask := _carve(chambers, links, _N(4), arrival)

	var forge_floors := [
		Vector2i(5, 1), Vector2i(7, 1), Vector2i(5, 2),
		Vector2i(7, 2), Vector2i(5, 3), Vector2i(7, 3),
	]
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, 3, MapKit._pick(forge_floors, cell, 651))

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 3, Vector2i(2, 2))
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, _forge_rim(), _bounds, blocked)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, arrival)
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + _L(0, 5))

	# Magma pits sit inside the west/east hall chambers only — never on the
	# cross bridges (those must stay fully walkable so players can cross).
	var lava_cells: Dictionary = {}
	var bridge_keepout: Dictionary = {}
	for ry in [_N(18), _N(42)]:
		for x in range(mini(west, east), maxi(west, east) + 1):
			for dy in range(-_gap(3), _gap(3) + 1):
				bridge_keepout[Vector2i(x, ry + dy)] = true
	for spot in [
		[Vector2i(west, _N(24)), _R(2.6), 651], [Vector2i(east, _N(24)), _R(2.6), 652],
		[Vector2i(west, _N(36)), _R(2.4), 653], [Vector2i(east, _N(36)), _R(2.4), 654],
		[Vector2i(west, _N(48)), _R(2.5), 655], [Vector2i(east, _N(48)), _R(2.5), 656],
		[Vector2i(west, _N(30)), _R(2.0), 658], [Vector2i(east, _N(30)), _R(2.0), 659],
	]:
		var pool: Dictionary = {}
		MapKit.blob(pool, spot[0], spot[1], 0.28, int(spot[2]), _bounds)
		pool = MapKit.smooth(pool, _bounds, 1, 5, 4)
		for cell: Vector2i in pool.keys():
			if walk.has(cell) and not bridge_keepout.has(cell):
				lava_cells[cell] = true
	var lava_tiles := [Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11)]
	for cell: Vector2i in lava_cells.keys():
		ground.set_cell(cell, 0, MapKit._pick(lava_tiles, cell, 662))
		walk.erase(cell)
	# Heat-stained masonry around each pit so the floor isn't one flat wash.
	var hot_floors := [Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3), Vector2i(4, 1), Vector2i(4, 2)]
	for cell: Vector2i in lava_cells.keys():
		for ox in range(-2, 3):
			for oy in range(-2, 3):
				if ox == 0 and oy == 0:
					continue
				var n := cell + Vector2i(ox, oy)
				if walk.has(n) and MapKit.hash2(n.x, n.y, 663) % 3 == 0:
					ground.set_cell(n, 3, MapKit._pick(hot_floors, n, 664))
	walk = MapKit.largest_region(walk, entrance)
	# Both cross bridges must still join the two halls after lava carving.
	for ry in [_N(18), _N(42)]:
		var mid := Vector2i(int((west + east) / 2.0), ry)
		assert(walk.has(LevelKit.pick_open(walk, mid)), "gallery cross-bridge blocked at y=%d" % ry)
		assert(walk.has(LevelKit.pick_open(walk, Vector2i(west, ry))), "gallery west bridge mouth blocked")
		assert(walk.has(LevelKit.pick_open(walk, Vector2i(east, ry))), "gallery east bridge mouth blocked")

	var blocked_all := blocked.duplicate()
	for cell: Vector2i in lava_cells.keys():
		blocked_all[cell] = true

	var no_build := LevelKit.keepout([entrance, exit_cell], _gap(4))
	for cell: Vector2i in bridge_keepout.keys():
		no_build[cell] = true
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked_all)
	var inner := MapKit.interior_cells(walk, blocked_all, _gap(3))

	# Quench wells down the middle of each hall (away from magma / bridges).
	for spot in [
		Vector2i(west, _N(18)), Vector2i(east, _N(18)), Vector2i(west, _N(54)), Vector2i(east, _N(54)),
		Vector2i(west, _N(36)), Vector2i(east, _N(36)),
	]:
		LevelKit.stamp_landmark(props, 3, [8, 1, 3, 3], LevelKit.pick_open(free, spot), free, solid)
	# Slag heaps and cooled rock along the hall walls.
	LevelKit.scatter_props(props, 3, edges, [[8, 5, 1, 1], [9, 5, 1, 1], [10, 5, 1, 1]], _dense(0.14), _N(4), 671, free, solid)
	# Braziers, coal heaps and crystal growths from the lava sheet.
	LevelKit.scatter_props(props, 0, inner, [[0, 1, 1, 2], [2, 1, 1, 1], [0, 2, 1, 1], [1, 2, 1, 1]], _dense(0.07), _N(5), 672, free, solid)
	# Forge stock: the props sheet chest and coal piles.
	LevelKit.scatter_props(props, 2, edges, [[0, 0, 1, 1], [1, 0, 1, 1], [2, 0, 1, 1]], _dense(0.055), _N(6), 673, free, solid)
	# Cracked floor / ember overlays so the masonry doesn't read as one flat wash.
	LevelKit.scatter_flat(overlay, 0, inner, [Vector2i(1, 1), Vector2i(3, 1), Vector2i(2, 1), Vector2i(0, 1)], _dense(0.10), _N(3), 674, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	var decos: Array = []
	var ti := 0
	for spot in [
		Vector2i(west, _N(18)), Vector2i(east, _N(18)), Vector2i(west, _N(30)), Vector2i(east, _N(30)),
		Vector2i(west, _N(42)), Vector2i(east, _N(42)), Vector2i(west, _N(54)), Vector2i(east, _N(54)),
		Vector2i(52, 67), Vector2i(52, 60), Vector2i(west, _N(24)), Vector2i(east, _N(24)),
		_L(52, 36), _L(46, 48), _L(58, 48),
	]:
		ti += 1
		decos.append({
			"name": "GalleryTorch%d" % ti,
			"frames": "deco_forge_torch",
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"scale": 1.3,
			"light": 0.75,
			"color": "Color(1, 0.58, 0.22, 1)",
		})

	var lights: Array = []
	var li := 0
	for cell: Vector2i in lava_cells.keys():
		if MapKit.hash2(cell.x, cell.y, 675) % 61 != 0:
			continue
		li += 1
		lights.append({
			"name": "GalleryMagma%d" % li,
			"pos": LevelKit.tile_pos(cell),
			"color": "Color(1, 0.38, 0.1, 1)",
			"energy": 0.6,
			"scale": 1.25,
		})

	var taken := LevelKit.keepout([entrance, exit_cell], _gap(6))
	var mob_plan: Array = [
		["ForgeAxeman", "trpg/trpg_armored_axeman", Vector2i(west, _N(54))],
		["ForgeAxeman2", "trpg/trpg_armored_axeman", Vector2i(east, _N(54))],
		["ForgeAxeman3", "trpg/trpg_armored_axeman", Vector2i(west, _N(48))],
		["ForgeAxeman4", "trpg/trpg_armored_axeman", Vector2i(east, _N(48))],
		["EliteOrc", "trpg/trpg_elite_orc", Vector2i(west, _N(42))],
		["EliteOrc2", "trpg/trpg_elite_orc", Vector2i(east, _N(42))],
		["EliteOrc3", "trpg/trpg_elite_orc", _L(52, 36)],
		["ArmoredOrc", "trpg/trpg_armored_orc", Vector2i(west, _N(30))],
		["ArmoredOrc2", "trpg/trpg_armored_orc", Vector2i(east, _N(30))],
		["ArmoredOrc3", "trpg/trpg_armored_orc", Vector2i(west, _N(24))],
		["ArmoredOrc4", "trpg/trpg_armored_orc", Vector2i(east, _N(24))],
		["Lancer", "trpg/trpg_lancer", Vector2i(west, _N(18))],
		["Lancer2", "trpg/trpg_lancer", Vector2i(east, _N(18))],
		["Lancer3", "trpg/trpg_lancer", _L(46, 24)],
		["Lancer4", "trpg/trpg_lancer", _L(58, 24)],
		["Templar", "trpg/trpg_knight_templar", _L(52, 18)],
		["Templar2", "trpg/trpg_knight_templar", _L(52, 42)],
		["Templar3", "trpg/trpg_knight_templar", _L(40, 42)],
		["Templar4", "trpg/trpg_knight_templar", _L(64, 42)],
		["Wizard", "trpg/trpg_wizard", Vector2i(west, _N(36))],
		["Wizard2", "trpg/trpg_wizard", Vector2i(east, _N(36))],
		["Wizard3", "trpg/trpg_wizard", _L(46, 54)],
		["Wizard4", "trpg/trpg_wizard", _L(58, 54)],
		["Soldier", "trpg/trpg_soldier", Vector2i(west, _N(60))],
		["Soldier2", "trpg/trpg_soldier", Vector2i(east, _N(60))],
		["Swordsman", "trpg/trpg_swordsman", _L(52, 58)],
	]
	var mob_cells := _populate(walk, taken, mob_plan.map(func(m: Array) -> Vector2i: return m[2]), _gap(4))
	var hostiles: Array = []
	for i in mob_plan.size():
		hostiles.append({
			"name": mob_plan[i][0],
			"type": TYPES + mob_plan[i][1] + ".tres",
			"pos": LevelKit.tile_pos(mob_cells[i]),
		})

	var npc_cells := _populate(walk, taken, [entrance + _L(-4, -2), entrance + _L(4, -2)], _gap(2))

	assert(walk.has(entrance) and walk.has(exit_cell), "gallery spawn blocked")
	assert(walk.size() > 30000, "gallery too small: %d" % walk.size())
	_log("bellows_gallery", walk, walls, props, hostiles)

	LevelKit.write_map({
		"root": "bellows_gallery",
		"out": OUT + "fire_forge/bellows_gallery.tscn",
		"tileset": FORGE_TS,
		"bg": "Color(0.05, 0.022, 0.016, 1)",
		"modulate": "Color(0.9, 0.8, 0.74, 1)",
		"music": "res://assets/audio/music/angevin.ogg",
		"layers": {
			"Ground": LevelKit.b64(ground),
			"Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props),
			"Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
		"camps": [{"name": "GalleryHearth", "pos": LevelKit.tile_pos(entrance + _L(3, -3))}],
		"decos": decos,
		"lights": lights,
		"hostiles": hostiles,
		"npcs": [
			{"name": "ForgemasterHelka", "resource": NPCS + "fire_forge/forgemaster_helka.tres",
				"pos": LevelKit.tile_pos(npc_cells[0])},
			{"name": "BellowsHandTorv", "resource": NPCS + "fire_forge/bellows_hand_torv.tres",
				"pos": LevelKit.tile_pos(npc_cells[1])},
		],
		"spawn": LevelKit.tile_pos(entrance),
		"warpers": [{"name": "Entrance", "pos": LevelKit.tile_pos(entrance), "id": 44}],
		"portals": [{
			"name": "DescentPortal", "pos": LevelKit.tile_pos(exit_cell),
			"id": 144, "target_id": 54, "instance": INST + "fire_forge.tres",
			"label": "Fire Forge", "color": "Color(0.86, 0.42, 0.12, 1)",
		}],
	})


# --- The Cinder Deeps --------------------------------------------------------
# Below the foundry the built walls give out and the raw volcano takes over: a
# spiral of ledges stepping around a central magma lake. The lake is the
# animated lava the surface map never used, and it blocks, so the spiral is the
# only way around. The masonry rim survives only at the chamber edges.

func _build_forge_deeps() -> void:
	_set_size(_N(112), _N(86))
	var ts: TileSet = load(FORGE_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	var arrival := _L(56, 76)
	var lake := _L(56, 40)
	# Spiral: eight ledges stepping inward and around the lake.
	var chambers: Array = [[_L(56, 75), _R(7.5), 0.24, 701]]
	var links: Array = [[_L(56, 70), _L(56, 64), _R(2.8), _R(1.8), 702]]
	var prev := _L(56, 64)
	var steps := 9
	for i in steps:
		var a: float = -PI * 0.5 + TAU * float(i) / float(steps - 1)
		var r: float = _R(34.0) - float(i) * _R(1.4)
		var c := lake + Vector2i(int(cos(a) * r), int(sin(a) * r * 0.74))
		chambers.append([c, _R(7.5) - float(i) * 0.12 * float(S), 0.27, 710 + i])
		links.append([prev, c, _R(2.4), _R(2.4), 730 + i])
		prev = c
	# A short causeway from the last ledge to the lake shore.
	links.append([prev, lake + _L(0, 16), _R(2.4), _R(1.6), 749])
	chambers.append([lake, _R(17.0), 0.16, 750])
	var floor_mask := _carve(chambers, links, _N(4), arrival)

	var forge_floors := [
		Vector2i(5, 1), Vector2i(7, 1), Vector2i(5, 2),
		Vector2i(7, 2), Vector2i(5, 3), Vector2i(7, 3),
	]
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, 3, MapKit._pick(forge_floors, cell, 751))

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 3, Vector2i(2, 2))
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, _forge_rim(), _bounds, blocked)
	# Raw volcanic rock behind the masonry border. Collision for this bank is
	# added in `build_biome_tilesets.gd`, so the mass blocks like the rim does.
	_restyle_deep(walls, void_mask, 0, [
		Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4),
		Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6),
		Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7),
	], 752)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, arrival)
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + _L(0, 5))

	# The magma lake: animated lava, and a hazard rather than scenery.
	var lava_cells: Dictionary = {}
	var pool: Dictionary = {}
	MapKit.blob(pool, lake, _R(8.5), 0.22, 761, _bounds)
	pool = MapKit.smooth(pool, _bounds, 1, 5, 4)
	for cell: Vector2i in pool.keys():
		if walk.has(cell):
			lava_cells[cell] = true
	# Runnels spilling off the lake into the lower ledges.
	for spot in [
		[lake + Vector2i(-20, 10), _R(4.0), 762], [lake + Vector2i(20, 10), _R(4.0), 763],
		[lake + _L(-18, -12), _R(3.6), 764], [lake + _L(18, -12), _R(3.6), 765],
	]:
		var run: Dictionary = {}
		MapKit.blob(run, spot[0], spot[1], 0.30, int(spot[2]), _bounds)
		run = MapKit.smooth(run, _bounds, 1, 5, 4)
		for cell: Vector2i in run.keys():
			if walk.has(cell):
				lava_cells[cell] = true
	var lava_anim := [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	for cell: Vector2i in lava_cells.keys():
		ground.set_cell(cell, 1, MapKit._pick(lava_anim, cell, 766))
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)
	# The boss holds the shore the causeway lands on.
	var shore := LevelKit.pick_open(walk, lake + _L(0, 15))

	var blocked_all := blocked.duplicate()
	for cell: Vector2i in lava_cells.keys():
		blocked_all[cell] = true
	var no_build := LevelKit.keepout([entrance, exit_cell], _gap(4))
	for cell: Vector2i in LevelKit.keepout([shore], _gap(6)).keys():
		no_build[cell] = true
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked_all)
	var inner := MapKit.interior_cells(walk, blocked_all, _gap(3))

	LevelKit.scatter_props(props, 3, edges, [[8, 5, 1, 1], [9, 5, 1, 1], [10, 5, 1, 1]], _dense(0.15), _N(4), 771, free, solid)
	# Crystal growths and coal heaps thrown up by the vents.
	LevelKit.scatter_props(props, 0, inner, [[0, 2, 1, 1], [1, 2, 1, 1], [1, 1, 1, 1]], _dense(0.06), _N(5), 772, free, solid)
	LevelKit.scatter_props(props, 2, edges, [[1, 0, 1, 1], [2, 0, 1, 1]], _dense(0.05), _N(6), 773, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	LevelKit.scatter_flat(overlay, 0, inner, [Vector2i(2, 1), Vector2i(3, 1)], _dense(0.025), _N(7), 774, solid)

	var decos: Array = []
	var ti := 0
	var deco_spots: Array = [_L(56, 75), _L(56, 64)]
	for i in steps:
		var a: float = -PI * 0.5 + TAU * float(i) / float(steps - 1)
		var r: float = _R(34.0) - float(i) * _R(1.4)
		deco_spots.append(lake + Vector2i(int(cos(a) * r), int(sin(a) * r * 0.74)))
	for spot: Vector2i in deco_spots:
		ti += 1
		decos.append({
			"name": "DeepTorch%d" % ti,
			"frames": "deco_forge_torch",
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"scale": 1.35,
			"light": 0.8,
			"color": "Color(1, 0.5, 0.16, 1)",
		})

	# Sparse and dim on purpose: these radial lights are square quads, so a dense
	# field of them blows the lake out into one bright blob with visible edges.
	# The surface forge uses eleven; this lake gets a comparable handful.
	var lights: Array = []
	var li := 0
	for cell: Vector2i in lava_cells.keys():
		if MapKit.hash2(cell.x, cell.y, 775) % 89 != 0:
			continue
		li += 1
		lights.append({
			"name": "MagmaGlow%d" % li,
			"pos": LevelKit.tile_pos(cell),
			"color": "Color(1, 0.36, 0.1, 1)",
			"energy": 0.55,
			"scale": 1.3,
		})

	var taken := LevelKit.keepout([entrance, exit_cell], _gap(6))
	var mob_plan: Array = [
		["Demon", "trpg/trpg_demon_a", Vector2i(56, 64)],
		["Demon2", "trpg/trpg_demon_a", _L(44, 62)],
		["Demon3", "trpg/trpg_demon_a", _L(68, 62)],
		["Demon4", "trpg/trpg_demon_a", _L(50, 68)],
		["Demon5", "trpg/trpg_demon_a", _L(62, 68)],
		["Oni", "trpg/trpg_conjuring_oni", lake + _L(-30, 8)],
		["Oni2", "trpg/trpg_conjuring_oni", lake + _L(30, 8)],
		["Oni3", "trpg/trpg_conjuring_oni", lake + _L(0, 12)],
		["OgreMage", "trpg/trpg_ogre_mage", lake + _L(-28, -10)],
		["OgreMage2", "trpg/trpg_ogre_mage", lake + _L(28, -10)],
		["OgreMage3", "trpg/trpg_ogre_mage", lake + _L(0, -14)],
		["Fomorian", "trpg/trpg_cinder_fomorian", lake + _L(0, -26)],
		["Fomorian2", "trpg/trpg_cinder_fomorian", lake + _L(-16, -22)],
		["Fomorian3", "trpg/trpg_cinder_fomorian", lake + _L(16, -26)],
		["UmberHulk", "trpg/trpg_umber_hulk", lake + _L(16, -22)],
		["UmberHulk2", "trpg/trpg_umber_hulk", lake + _L(-20, -8)],
		["UmberHulk3", "trpg/trpg_umber_hulk", lake + _L(20, -8)],
		["BloodMonster", "trpg/trpg_blood_monster_a", lake + _L(-22, 18)],
		["BloodMonster2", "trpg/trpg_blood_monster_a", lake + _L(22, 18)],
		["BloodMonster3", "trpg/trpg_blood_monster_a", lake + _L(0, 22)],
		["EliteOrc", "trpg/trpg_elite_orc", lake + _L(-10, 20)],
		["EliteOrc2", "trpg/trpg_elite_orc", lake + _L(10, 20)],
		["EliteOrc3", "trpg/trpg_elite_orc", lake + _L(-24, 4)],
		["EliteOrc4", "trpg/trpg_elite_orc", lake + _L(24, 4)],
		["Axeman", "trpg/trpg_armored_axeman", lake + _L(-14, -30)],
		["Axeman2", "trpg/trpg_armored_axeman", lake + _L(14, -30)],
	]
	var mob_cells := _populate(walk, taken, mob_plan.map(func(m: Array) -> Vector2i: return m[2]), _gap(4))
	var hostiles: Array = []
	for i in mob_plan.size():
		hostiles.append({
			"name": mob_plan[i][0],
			"type": TYPES + mob_plan[i][1] + ".tres",
			"pos": LevelKit.tile_pos(mob_cells[i]),
		})
	hostiles.append({
		"name": "Cinderborn",
		"type": TYPES + "bosses/cinderborn.tres",
		"pos": LevelKit.tile_pos(shore),
	})

	var npc_cells := _populate(walk, taken, [entrance + _L(-4, -2)], _gap(2))

	assert(walk.has(entrance) and walk.has(exit_cell), "deeps spawn blocked")
	assert(walk.has(shore), "deeps shore blocked")
	assert(walk.size() > 30000, "deeps too small: %d" % walk.size())
	_log("cinder_deeps", walk, walls, props, hostiles)

	LevelKit.write_map({
		"root": "cinder_deeps",
		"out": OUT + "fire_forge/cinder_deeps.tscn",
		"tileset": FORGE_TS,
		"bg": "Color(0.06, 0.012, 0.008, 1)",
		"modulate": "Color(0.78, 0.62, 0.58, 1)",
		"music": "res://assets/audio/music/middle_boss.ogg",
		"layers": {
			"Ground": LevelKit.b64(ground),
			"Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props),
			"Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
		"camps": [{"name": "DeepHearth", "pos": LevelKit.tile_pos(entrance + _L(3, -3))}],
		"decos": decos,
		"lights": lights,
		"hostiles": hostiles,
		"npcs": [{
			"name": "CinderwrightMaro", "resource": NPCS + "fire_forge/cinderwright_maro.tres",
			"pos": LevelKit.tile_pos(npc_cells[0]),
		}],
		"spawn": LevelKit.tile_pos(entrance),
		"warpers": [{"name": "Entrance", "pos": LevelKit.tile_pos(entrance), "id": 45}],
		"portals": [{
			"name": "AscentPortal", "pos": LevelKit.tile_pos(exit_cell),
			"id": 145, "target_id": 55, "instance": INST + "fire_forge.tres",
			"label": "Fire Forge", "color": "Color(0.7, 0.2, 0.05, 1)",
		}],
	})
