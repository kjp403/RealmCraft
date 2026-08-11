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
## and population.
##
## Layouts are authored in a compact grid and multiplied up by `SCALE` on the
## way out (see `_s`). Editing a level means moving small readable numbers; the
## zone size is one constant.
##
##   godot --headless --path . -s tools/build_biome_levels.gd

const OUT := "res://source/common/gameplay/maps/maps/"
const INST := "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const TYPES := "res://source/common/gameplay/characters/npc/types/"
const NPCS := "res://source/common/gameplay/characters/npc/npcs/"

const DESERT_TS := "res://source/common/gameplay/maps/tilesets/desert_tileset.tres"
const FORGE_TS := "res://source/common/gameplay/maps/tilesets/fire_forge_tileset.tres"
const SEWERS_TS := "res://source/common/gameplay/maps/tilesets/sewers_tileset.tres"

## Linear multiplier applied to every authored coordinate, radius and corridor
## width. 2.24 in each axis is ~5x the playable area — these zones needed room
## for oversized mobs (acid oozes, zombie giants, the bosses) without corridors
## reading as a squeeze. This is the single knob for "make it bigger"; note the
## cost is roughly quadratic in `.tscn` size, because Ground paints every cell.
const SCALE := 2.24

var W: int = 96
var H: int = 72
var _bounds := Rect2i(0, 0, 96, 72)
var _report: Array[String] = []


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


# --- Authored space -> world space -------------------------------------------

func _s(cell: Vector2i) -> Vector2i:
	return Vector2i(int(round(float(cell.x) * SCALE)), int(round(float(cell.y) * SCALE)))


func _sf(value: float) -> float:
	return value * SCALE


func _spots(list: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell: Vector2i in list:
		out.append(_s(cell))
	return out


func _set_size(w: int, h: int) -> void:
	W = int(round(float(w) * SCALE))
	H = int(round(float(h) * SCALE))
	_bounds = Rect2i(0, 0, W, H)


## Shared shaping, same contract as `build_stub_biomes.gd`: chambers joined by
## wandering tunnels, smoothed, trimmed to a solid margin, reduced to the single
## region containing `anchor`. Every input is in authored space.
func _carve(chambers: Array, links: Array, margin: int, anchor: Vector2i) -> Dictionary:
	var mask: Dictionary = {}
	for ch in chambers:
		MapKit.blob(mask, _s(ch[0]), _sf(ch[1]), ch[2], int(ch[3]), _bounds)
	for link in links:
		MapKit.tunnel(mask, _s(link[0]), _s(link[1]), _sf(link[2]), _sf(link[3]), int(link[4]), _bounds)
	var m: int = int(round(float(margin) * SCALE))
	var trimmed: Dictionary = {}
	for cell: Vector2i in mask.keys():
		if (
			cell.x >= m and cell.y >= m + 2
			and cell.x < W - m and cell.y < H - m
		):
			trimmed[cell] = true
	var smoothed := MapKit.smooth(trimmed, _bounds, 2, 5, 4)
	return MapKit.largest_region(smoothed, LevelKit.pick_open(smoothed, _s(anchor)))


## A blob carved or removed outside `_carve`, authored space in, world out.
func _blob(centre: Vector2i, radius: float, wobble: float, seed_value: int) -> Dictionary:
	var out: Dictionary = {}
	MapKit.blob(out, _s(centre), _sf(radius), wobble, seed_value, _bounds)
	return MapKit.smooth(out, _bounds, 1, 5, 4)


## A ring of chambers around a hollow centre — used where a level should loop
## instead of branching off a spine. Returns authored-space entries.
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
		out.append([p, q, width, 2.5, seed_value + i])
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
## reads as a different material. Only ever use collision-marked tiles here.
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
		"  %-20s %3dx%-3d walk=%-6d walls=%-6d props=%-5d mobs=%d"
		% [name, W, H, walk.size(), walls.get_used_cells().size(), props.get_used_cells().size(), hostiles.size()]
	)


## Place one entry on the nearest free walkable cell to its authored spot,
## reserving a gap so nothing crowds anything else.
func _place(walk: Dictionary, taken: Dictionary, wanted: Vector2i, gap: int) -> Vector2i:
	var pool: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not taken.has(cell):
			pool[cell] = true
	if pool.is_empty():
		return wanted
	var cell := LevelKit.pick_open(pool, wanted)
	for oy in range(-gap, gap + 1):
		for ox in range(-gap, gap + 1):
			taken[cell + Vector2i(ox, oy)] = true
	return cell


## Expand a mob plan into hostiles. Entries are
## `[base_name, type_slug, authored_spot, count]`; a count above one spreads
## that many of the same type around the spot, which is how a zone this size
## gets populated without a hand-written line per body.
func _mobs(walk: Dictionary, taken: Dictionary, plan: Array, gap: int) -> Array:
	var out: Array = []
	for entry: Array in plan:
		var base: String = entry[0]
		var slug: String = entry[1]
		var spot: Vector2i = _s(entry[2])
		var count: int = int(entry[3]) if entry.size() > 3 else 1
		for i in count:
			var cell := _place(walk, taken, spot, gap)
			out.append({
				"name": base if i == 0 else "%s%d" % [base, i + 1],
				"type": TYPES + slug + ".tres",
				"pos": LevelKit.tile_pos(cell),
			})
	return out


# =============================================================================
# DESERT — Sunspire Terraces (up) and The Sunken Tombs (down)
# =============================================================================

# --- Sunspire Terraces -------------------------------------------------------
# Wind-scoured mesa tops above the basin. A single loop of terraces around a
# central spire so the level circles instead of branching, with the caravan camp
# at the arrival end. Draws on three atlas banks the basin never touches: the
# Props monuments, the Sand dune overlays, and the OutdoorHouseSet lanterns.

func _build_desert_terraces() -> void:
	_set_size(100, 74)
	var ts: TileSet = load(DESERT_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	var arrival := Vector2i(50, 64)
	var centre := Vector2i(50, 36)
	var chambers: Array = [[Vector2i(50, 63), 10.0, 0.26, 201]]
	chambers.append_array(_ring(centre, 38, 7, 10.5, 210))
	var links: Array = [[Vector2i(50, 58), Vector2i(50, 50), 3.4, 2.0, 220]]
	links.append_array(_ring_links(centre, 38, 7, 3.2, 230))
	var floor_mask := _carve(chambers, links, 4, arrival)

	# The spire the terraces circle: a solid mesa left standing in the middle.
	for cell: Vector2i in _blob(centre, 11.0, 0.24, 240).keys():
		floor_mask.erase(cell)
	floor_mask = MapKit.largest_region(floor_mask, LevelKit.pick_open(floor_mask, _s(arrival)))

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
	var entrance := LevelKit.pick_open(walk, _s(arrival))
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + Vector2i(0, 6))

	var no_build := LevelKit.keepout([entrance, exit_cell], 6)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)
	# Tall monuments need a block of clear cells, so they anchor on interior
	# floor rather than the nearest free cell — which is often against a cliff
	# where the stamp would silently fail to fit.
	var inner_free: Dictionary = {}
	for cell: Vector2i in inner:
		if free.has(cell):
			inner_free[cell] = true

	var monuments: Array = [
		[Vector2i(50, 12), [0, 0, 3, 8]],    # great obelisk, north gate
		[Vector2i(16, 32), [2, 2, 3, 6]],    # lesser obelisks on the side terraces
		[Vector2i(84, 32), [2, 2, 3, 6]],
		[Vector2i(24, 58), [4, 4, 2, 4]],    # roadside shrines on the south run
		[Vector2i(76, 58), [4, 4, 2, 4]],
		[Vector2i(30, 16), [0, 8, 2, 3]],    # stepped bases flanking the spire
		[Vector2i(70, 16), [2, 8, 2, 3]],
		[Vector2i(50, 54), [4, 8, 2, 3]],
		[Vector2i(14, 48), [0, 11, 3, 5]],   # sun-bleached bones and dead trees
		[Vector2i(86, 48), [3, 11, 2, 3]],
		[Vector2i(22, 20), [0, 16, 3, 5]],
		[Vector2i(78, 20), [4, 16, 2, 2]],
	]
	for m in monuments:
		LevelKit.stamp_landmark(props, 1, m[1], LevelKit.pick_open(inner_free, _s(m[0])), inner_free, solid)
	# Stone lanterns ringing the camp. Solid, and `free` keeps them off the stair.
	for spot in _spots([
		Vector2i(42, 60), Vector2i(58, 60), Vector2i(42, 68), Vector2i(58, 68),
		Vector2i(50, 54), Vector2i(16, 32), Vector2i(84, 32),
	]):
		LevelKit.stamp_landmark(props, 3, [1, 4, 1, 1], LevelKit.pick_open(inner_free, spot), inner_free, solid)
	for cell: Vector2i in solid.keys():
		free.erase(cell)

	# Boulders hug the cliff feet, cacti stand in the open.
	LevelKit.scatter_props(props, 0, edges, [[10, 7, 2, 2], [12, 7, 2, 2], [10, 1, 2, 2]], 0.09, 5, 261, free, solid)
	LevelKit.scatter_props(props, 0, inner, [[10, 14, 1, 3], [11, 14, 1, 3], [12, 14, 1, 3]], 0.045, 6, 262, free, solid)
	LevelKit.scatter_props(props, 1, inner, [[6, 0, 2, 2], [8, 0, 2, 2], [6, 2, 2, 2]], 0.02, 9, 263, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	# Flat detail: dry scrub, caravan urns, then dune crests on the overlay so
	# they read as wind ripples drifting over everything else.
	LevelKit.scatter_flat(props, 0, inner, [
		Vector2i(10, 5), Vector2i(11, 5), Vector2i(12, 5), Vector2i(13, 5), Vector2i(14, 5),
	], 0.10, 3, 264, solid)
	LevelKit.scatter_flat(props, 1, inner, [
		Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4),
		Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5),
	], 0.015, 7, 265, solid)
	LevelKit.scatter_flat(overlay, 2, inner, [
		Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(3, 2),
		Vector2i(10, 1), Vector2i(11, 1), Vector2i(15, 2), Vector2i(16, 2),
	], 0.07, 4, 266, {})

	var decos: Array = []
	var ti := 0
	for spot in _spots([
		Vector2i(50, 12), Vector2i(16, 32), Vector2i(84, 32), Vector2i(24, 58),
		Vector2i(76, 58), Vector2i(50, 63), Vector2i(30, 44), Vector2i(70, 44),
		Vector2i(30, 20), Vector2i(70, 20), Vector2i(50, 50), Vector2i(38, 66),
		Vector2i(62, 66), Vector2i(20, 44), Vector2i(80, 44),
	]):
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
	for spot in _spots([Vector2i(24, 44), Vector2i(76, 44), Vector2i(50, 24), Vector2i(44, 60)]):
		critters.append({
			"name": "TerraceCritter%d" % (ci + 1),
			"frames": names[ci],
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"scale": 0.9,
			"wander_radius": 44.0,
		})
		ci += 1

	var taken := LevelKit.keepout([entrance, exit_cell], 10)
	var hostiles := _mobs(walk, taken, [
		["Harpy", "trpg/trpg_clawing_harpy", Vector2i(50, 12), 3],
		["Cockatrice", "trpg/trpg_lacerating_cockatrice", Vector2i(16, 32), 2],
		["CockatriceE", "trpg/trpg_lacerating_cockatrice", Vector2i(84, 32), 2],
		["OrcRider", "trpg/trpg_orc_rider", Vector2i(24, 54), 3],
		["OrcRiderE", "trpg/trpg_orc_rider", Vector2i(76, 54), 3],
		["DuneArcher", "trpg/trpg_archer", Vector2i(30, 22), 2],
		["DuneArcherE", "trpg/trpg_archer", Vector2i(70, 22), 2],
		["Fomorian", "trpg/trpg_wretched_fomorian", Vector2i(50, 48), 2],
		["Werewolf", "trpg/trpg_werewolf", Vector2i(36, 40), 2],
		["WerewolfE", "trpg/trpg_werewolf", Vector2i(64, 40), 2],
	], 8)

	var npc_a := _place(walk, taken, entrance + Vector2i(-6, -3), 3)
	var npc_b := _place(walk, taken, entrance + Vector2i(6, -3), 3)

	assert(walk.has(entrance) and walk.has(exit_cell), "terraces spawn blocked")
	assert(walk.size() > 6000, "terraces too small: %d" % walk.size())
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
		"camps": [{"name": "CaravanFire", "pos": LevelKit.tile_pos(entrance + Vector2i(4, -4))}],
		"decos": decos,
		"critters": critters,
		"hostiles": hostiles,
		"npcs": [
			{"name": "CaravanMasterSefu", "resource": NPCS + "desert/caravan_master_sefu.tres",
				"pos": LevelKit.tile_pos(npc_a)},
			{"name": "DuneScoutIlka", "resource": NPCS + "desert/dune_scout_ilka.tres",
				"pos": LevelKit.tile_pos(npc_b)},
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
	_set_size(108, 84)
	var ts: TileSet = load(DESERT_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	var arrival := Vector2i(54, 74)
	var floor_mask := _carve(
		[
			[Vector2i(54, 73), 9.0, 0.24, 301],   # stair hall
			[Vector2i(54, 62), 8.0, 0.26, 302],
			[Vector2i(32, 58), 8.5, 0.28, 303],   # paired alcoves down the spine
			[Vector2i(76, 58), 8.5, 0.28, 304],
			[Vector2i(54, 48), 8.0, 0.26, 305],
			[Vector2i(28, 42), 9.0, 0.28, 306],
			[Vector2i(80, 42), 9.0, 0.28, 307],
			[Vector2i(54, 34), 8.5, 0.26, 308],
			[Vector2i(34, 24), 8.0, 0.28, 309],
			[Vector2i(74, 24), 8.0, 0.28, 310],
			[Vector2i(54, 16), 14.0, 0.20, 311],  # king's chamber
		],
		[
			[Vector2i(54, 68), Vector2i(54, 56), 3.2, 1.8, 321],
			[Vector2i(48, 60), Vector2i(36, 58), 2.8, 2.4, 322],
			[Vector2i(60, 60), Vector2i(72, 58), 2.8, 2.4, 323],
			[Vector2i(54, 54), Vector2i(54, 42), 3.2, 1.8, 324],
			[Vector2i(46, 46), Vector2i(32, 42), 2.8, 2.6, 325],
			[Vector2i(62, 46), Vector2i(76, 42), 2.8, 2.6, 326],
			[Vector2i(54, 40), Vector2i(54, 26), 3.2, 1.8, 327],
			[Vector2i(46, 30), Vector2i(38, 24), 2.8, 2.4, 328],
			[Vector2i(62, 30), Vector2i(70, 24), 2.8, 2.4, 329],
			[Vector2i(38, 22), Vector2i(48, 16), 3.0, 2.2, 330],
			[Vector2i(70, 22), Vector2i(60, 16), 3.0, 2.2, 331],
		],
		4,
		arrival
	)

	# Flat cut sandstone. Row 8 of this bank looks like floor on a contact sheet
	# but is the bottom half of the boulder sprite; the genuinely flat slabs are
	# rows 9-10, columns 10-12 (column 13 has transparent cut-outs punched
	# through it).
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
	# The two cleanest cells of the arch interior; the neighbours carry tan brick
	# fragments that speckle when tiled across a mass this size.
	_restyle_deep(walls, void_mask, 0, [Vector2i(8, 12), Vector2i(7, 13)], 342)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, _s(arrival))
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + Vector2i(0, 6))
	var throne := LevelKit.pick_open(walk, _s(Vector2i(54, 16)))

	var no_build := LevelKit.keepout([entrance, exit_cell], 6)
	for cell: Vector2i in LevelKit.keepout([throne], 12).keys():
		no_build[cell] = true
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)

	# Sarcophagi line the alcoves — the gilded coffin bank on Ground rows 15-18.
	for spot in _spots([
		Vector2i(32, 58), Vector2i(76, 58), Vector2i(28, 42), Vector2i(80, 42),
		Vector2i(34, 24), Vector2i(74, 24), Vector2i(46, 62), Vector2i(62, 62),
		Vector2i(44, 34), Vector2i(64, 34), Vector2i(36, 54), Vector2i(72, 54),
		Vector2i(30, 38), Vector2i(78, 38), Vector2i(48, 50), Vector2i(60, 50),
	]):
		var anchor := LevelKit.pick_open(free, spot)
		var bank: Array = [
			[0, 15, 1, 4], [1, 15, 1, 4], [2, 15, 1, 4],
		][MapKit.hash2(anchor.x, anchor.y, 351) % 3]
		LevelKit.stamp_landmark(props, 0, bank, anchor, free, solid)
	# Grave goods heaped against the walls.
	LevelKit.scatter_props(props, 1, edges, [[6, 0, 2, 2], [8, 0, 2, 2], [6, 2, 2, 2], [8, 2, 2, 2]], 0.07, 5, 352, free, solid)
	LevelKit.scatter_props(props, 1, inner, [[0, 8, 2, 3], [2, 8, 2, 3], [4, 8, 2, 3]], 0.035, 7, 353, free, solid)
	LevelKit.scatter_props(props, 1, edges, [[0, 11, 3, 5], [3, 11, 2, 3]], 0.03, 8, 354, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	LevelKit.scatter_flat(props, 1, inner, [
		Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4),
		Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(9, 5),
		Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 6),
	], 0.05, 4, 355, solid)
	LevelKit.scatter_flat(overlay, 0, inner, [
		Vector2i(10, 11), Vector2i(11, 11), Vector2i(12, 11), Vector2i(13, 11),
	], 0.02, 8, 356, {})

	var decos: Array = []
	var ti := 0
	for spot in _spots([
		Vector2i(54, 73), Vector2i(54, 62), Vector2i(32, 58), Vector2i(76, 58),
		Vector2i(54, 48), Vector2i(28, 42), Vector2i(80, 42), Vector2i(54, 34),
		Vector2i(34, 24), Vector2i(74, 24), Vector2i(44, 16), Vector2i(64, 16),
		Vector2i(54, 68), Vector2i(54, 56), Vector2i(54, 42), Vector2i(54, 28),
		Vector2i(40, 50), Vector2i(68, 50), Vector2i(40, 34), Vector2i(68, 34),
	]):
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
	for spot in _spots([Vector2i(54, 16), Vector2i(46, 13), Vector2i(62, 13), Vector2i(54, 22)]):
		li += 1
		lights.append({
			"name": "ThroneGlow%d" % li,
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"color": "Color(0.5, 0.9, 0.8, 1)",
			"energy": 0.55,
			"scale": 1.6,
		})

	var taken := LevelKit.keepout([entrance, exit_cell], 10)
	for cell: Vector2i in LevelKit.keepout([throne], 10).keys():
		taken[cell] = true
	var hostiles := _mobs(walk, taken, [
		["TombSkeleton", "trpg/trpg_skeleton", Vector2i(54, 62), 4],
		["ArmoredSkeleton", "trpg/trpg_armored_skeleton", Vector2i(32, 58), 3],
		["ArmoredSkeletonE", "trpg/trpg_armored_skeleton", Vector2i(76, 58), 3],
		["BoneArcher", "trpg/trpg_skeleton_archer", Vector2i(28, 42), 3],
		["BoneArcherE", "trpg/trpg_skeleton_archer", Vector2i(80, 42), 3],
		["Greatsword", "trpg/trpg_greatsword_skeleton", Vector2i(54, 48), 2],
		["GreatswordN", "trpg/trpg_greatsword_skeleton", Vector2i(54, 34), 2],
		["Necromancer", "trpg/trpg_necromancer", Vector2i(34, 24), 2],
		["NecromancerE", "trpg/trpg_necromancer", Vector2i(74, 24), 2],
		["Gorgon", "trpg/trpg_poisonous_gorgon", Vector2i(44, 34), 2],
		["GorgonE", "trpg/trpg_poisonous_gorgon", Vector2i(64, 34), 2],
		["ThroneGuard", "trpg/trpg_armored_skeleton", Vector2i(44, 20), 2],
		["ThroneGuardE", "trpg/trpg_armored_skeleton", Vector2i(64, 20), 2],
	], 8)
	hostiles.append({
		"name": "SandKing",
		"type": TYPES + "bosses/sand_king.tres",
		"pos": LevelKit.tile_pos(throne),
	})

	var npc_a := _place(walk, taken, entrance + Vector2i(-6, -3), 3)

	assert(walk.has(entrance) and walk.has(exit_cell), "tombs spawn blocked")
	assert(walk.has(throne), "tombs throne blocked")
	assert(walk.size() > 6000, "tombs too small: %d" % walk.size())
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
		"camps": [{"name": "StairFire", "pos": LevelKit.tile_pos(entrance + Vector2i(4, -4))}],
		"decos": decos,
		"lights": lights,
		"hostiles": hostiles,
		"npcs": [{
			"name": "TombDelverAsha", "resource": NPCS + "desert/tomb_delver_asha.tres",
			"pos": LevelKit.tile_pos(npc_a),
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
# its banners, portcullises and gargoyles.

func _build_sewers_gutterworks() -> void:
	_set_size(104, 78)
	var ts: TileSet = load(SEWERS_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	var arrival := Vector2i(52, 68)
	var cols := [22, 52, 82]
	var rows := [20, 40, 58]
	var chambers: Array = [[Vector2i(52, 67), 8.0, 0.24, 401]]
	var seed_i := 410
	for cx in cols:
		for ry in rows:
			chambers.append([Vector2i(cx, ry), 8.0, 0.26, seed_i])
			seed_i += 1
	var links: Array = [[Vector2i(52, 64), Vector2i(52, 60), 3.2, 1.6, 430]]
	var seed_j := 440
	for ry in rows:
		for i in range(cols.size() - 1):
			links.append([Vector2i(cols[i], ry), Vector2i(cols[i + 1], ry), 2.8, 2.0, seed_j])
			seed_j += 1
	for cx in cols:
		for i in range(rows.size() - 1):
			links.append([Vector2i(cx, rows[i]), Vector2i(cx, rows[i + 1]), 2.8, 2.0, seed_j])
			seed_j += 1
	var floor_mask := _carve(chambers, links, 4, arrival)

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
	# identity from the cobble floor and the DarkCastle furniture instead.

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, _s(arrival))
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + Vector2i(0, 6))

	var no_build := LevelKit.keepout([entrance, exit_cell], 6)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)

	# Gargoyle heads at the crossings.
	for spot in _spots([
		Vector2i(22, 20), Vector2i(52, 20), Vector2i(82, 20),
		Vector2i(22, 40), Vector2i(82, 40), Vector2i(22, 58), Vector2i(82, 58),
	]):
		LevelKit.stamp_landmark(props, 2, [3, 3, 1, 1], LevelKit.pick_open(free, spot), free, solid)
	LevelKit.scatter_props(props, 0, edges, [[6, 4, 1, 2], [7, 4, 1, 2], [8, 4, 1, 2]], 0.14, 4, 461, free, solid)
	LevelKit.scatter_props(props, 0, inner, [[6, 3, 1, 1], [7, 3, 1, 1], [8, 3, 1, 1]], 0.05, 6, 462, free, solid)
	# Stores left behind by the works crews: chests, crates and cauldrons.
	LevelKit.scatter_props(props, 0, edges, [[0, 8, 1, 1], [1, 8, 1, 1], [2, 8, 1, 1], [3, 8, 1, 1], [4, 7, 1, 1]], 0.05, 6, 463, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	LevelKit.scatter_flat(props, 2, inner, [Vector2i(2, 4)], 0.035, 5, 464, solid)
	LevelKit.scatter_flat(overlay, 0, inner, [
		Vector2i(9, 4), Vector2i(9, 5), Vector2i(7, 7), Vector2i(8, 6),
		Vector2i(6, 8), Vector2i(7, 8), Vector2i(9, 8),
	], 0.055, 3, 465, {})
	LevelKit.scatter_flat(overlay, 2, edges, [Vector2i(3, 0), Vector2i(4, 0)], 0.05, 5, 466, solid)

	var decos: Array = []
	var ti := 0
	for spot in _spots([
		Vector2i(22, 20), Vector2i(52, 20), Vector2i(82, 20),
		Vector2i(22, 40), Vector2i(52, 40), Vector2i(82, 40),
		Vector2i(22, 58), Vector2i(52, 58), Vector2i(82, 58), Vector2i(52, 67),
		Vector2i(37, 20), Vector2i(67, 20), Vector2i(37, 40), Vector2i(67, 40),
		Vector2i(37, 58), Vector2i(67, 58), Vector2i(22, 30), Vector2i(82, 30),
		Vector2i(22, 49), Vector2i(82, 49),
	]):
		ti += 1
		decos.append({
			"name": "GutterLamp%d" % ti,
			"frames": "deco_torch" if ti % 3 != 0 else "deco_candle_a",
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"scale": 1.35,
			"light": 0.9,
			"color": "Color(0.55, 0.95, 0.6, 1)" if ti % 3 == 0 else "Color(1, 0.74, 0.4, 1)",
		})

	var taken := LevelKit.keepout([entrance, exit_cell], 10)
	var hostiles := _mobs(walk, taken, [
		["Slime", "trpg/trpg_slime", Vector2i(22, 58), 3],
		["SlimeE", "trpg/trpg_slime", Vector2i(82, 58), 3],
		["GutterBat", "trpg/trpg_bat", Vector2i(22, 40), 3],
		["GutterBatC", "trpg/trpg_bat", Vector2i(52, 40), 3],
		["GutterBatE", "trpg/trpg_bat", Vector2i(82, 40), 3],
		["AcidOoze", "trpg/trpg_acid_ooze", Vector2i(22, 20), 2],
		["AcidOozeE", "trpg/trpg_acid_ooze", Vector2i(82, 20), 2],
		["Zombie", "trpg/trpg_zombie_giant", Vector2i(52, 20), 2],
		["Crawler", "trpg/trpg_carrion_crawler", Vector2i(37, 30), 2],
		["CrawlerE", "trpg/trpg_carrion_crawler", Vector2i(67, 30), 2],
		["Skeleton", "trpg/trpg_skeleton", Vector2i(37, 49), 2],
		["SkeletonE", "trpg/trpg_skeleton", Vector2i(67, 49), 2],
	], 9)

	var npc_a := _place(walk, taken, entrance + Vector2i(-6, -3), 3)
	var npc_b := _place(walk, taken, entrance + Vector2i(6, -3), 3)

	assert(walk.has(entrance) and walk.has(exit_cell), "gutterworks spawn blocked")
	assert(walk.size() > 6000, "gutterworks too small: %d" % walk.size())
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
		"camps": [{"name": "CrewBrazier", "pos": LevelKit.tile_pos(entrance + Vector2i(4, -4))}],
		"decos": decos,
		"hostiles": hostiles,
		"npcs": [
			{"name": "SluiceWardenObry", "resource": NPCS + "sewers/sluice_warden_obry.tres",
				"pos": LevelKit.tile_pos(npc_a)},
			{"name": "RatcatcherPell", "resource": NPCS + "sewers/ratcatcher_pell.tres",
				"pos": LevelKit.tile_pos(npc_b)},
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
# One enormous flooded reservoir with a ring of holding tanks around it.
#
# This level is deliberately plain in its tiling. The first version mixed a
# checkerboard floor cell, a fully transparent atlas cell, and the DG "liquid"
# tiles — which are decorative spheres, not tileable water — and the result read
# as noise. It now follows the rule that actually worked in the Bellows Gallery:
# ONE flat floor bank, the biome's own quiet wall fill, and all the character
# carried by structure, props, lighting and scale.

func _build_sewers_cistern() -> void:
	_set_size(112, 86)
	var ts: TileSet = load(SEWERS_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	var arrival := Vector2i(56, 76)
	var basin := Vector2i(56, 38)
	var chambers: Array = [
		[Vector2i(56, 75), 8.5, 0.24, 501],
		[Vector2i(56, 64), 8.0, 0.26, 502],
		[basin, 22.0, 0.14, 503],  # the reservoir itself
	]
	chambers.append_array(_ring(basin, 36, 7, 8.0, 510))
	var links: Array = [
		[Vector2i(56, 70), Vector2i(56, 58), 3.4, 1.8, 520],
		[Vector2i(56, 58), basin, 3.6, 1.6, 521],
	]
	links.append_array(_ring_links(basin, 36, 7, 2.8, 530))
	var seed_s := 540
	for i in 7:
		var a: float = TAU * float(i) / 7.0
		var p := basin + Vector2i(int(cos(a) * 36), int(sin(a) * 36 * 0.72))
		links.append([p, basin, 2.6, 2.4, seed_s])
		seed_s += 1
	var floor_mask := _carve(chambers, links, 4, arrival)

	# Flat DG stone. Columns 6-8 of row 13 are the only genuinely flat cells in
	# this bank: column 4 is transparent, column 5 is a checkerboard, and
	# columns 9-10 carry crack decals (scattered sparsely further down instead).
	var dg_floor := [Vector2i(6, 13), Vector2i(7, 13), Vector2i(8, 13)]
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, 3, MapKit._pick(dg_floor, cell, 551))

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 0, Vector2i(7, 0))
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, _sewers_rim(), _bounds, blocked)
	# No deep-void restyle: the DG banding striped the whole surround and the
	# rubble bank speckled it. The culverts' own fill is quiet and correct.

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, _s(arrival))
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + Vector2i(0, 6))
	var dais := LevelKit.pick_open(walk, _s(basin))

	# The ornate hall mosaic laid as the reservoir's drained floor plate — one
	# authored 5x7 panel, not a tiled pattern, so it reads as a deliberate dais.
	var plate_origin := dais - Vector2i(2, 3)
	for oy in 7:
		for ox in 5:
			var cell := plate_origin + Vector2i(ox, oy)
			if walk.has(cell):
				ground.set_cell(cell, 3, Vector2i(21 + ox, oy))

	var no_build := LevelKit.keepout([entrance, exit_cell], 6)
	for cell: Vector2i in LevelKit.keepout([dais], 14).keys():
		no_build[cell] = true
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)

	# Fallen pillars and stair blocks from the DG set, plus catacomb urns.
	for spot in _spots([
		Vector2i(30, 30), Vector2i(82, 30), Vector2i(30, 52), Vector2i(82, 52),
		Vector2i(56, 18), Vector2i(38, 66), Vector2i(74, 66),
		Vector2i(20, 40), Vector2i(92, 40),
	]):
		LevelKit.stamp_landmark(props, 3, [16, 7, 3, 3], LevelKit.pick_open(free, spot), free, solid)
	for spot in _spots([Vector2i(36, 40), Vector2i(76, 40), Vector2i(56, 26), Vector2i(56, 54)]):
		LevelKit.stamp_landmark(props, 3, [17, 10, 2, 4], LevelKit.pick_open(free, spot), free, solid)
	LevelKit.scatter_props(props, 0, edges, [[6, 4, 1, 2], [7, 4, 1, 2], [8, 4, 1, 2]], 0.12, 5, 571, free, solid)
	LevelKit.scatter_props(props, 3, inner, [[2, 12, 1, 1]], 0.04, 6, 572, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	# Cracks and silt on the stone, sparse enough to read as wear.
	LevelKit.scatter_flat(overlay, 3, inner, [Vector2i(9, 13), Vector2i(10, 13)], 0.05, 5, 573, solid)
	LevelKit.scatter_flat(overlay, 0, inner, [
		Vector2i(9, 4), Vector2i(9, 5), Vector2i(7, 7), Vector2i(8, 6),
	], 0.05, 4, 574, solid)

	var decos: Array = []
	var ti := 0
	for spot in _spots([
		Vector2i(56, 75), Vector2i(56, 64), Vector2i(30, 30), Vector2i(82, 30),
		Vector2i(30, 52), Vector2i(82, 52), Vector2i(56, 18), Vector2i(38, 66),
		Vector2i(74, 66), Vector2i(42, 44), Vector2i(70, 44), Vector2i(20, 40),
		Vector2i(92, 40), Vector2i(56, 56), Vector2i(56, 26), Vector2i(42, 32),
		Vector2i(70, 32), Vector2i(44, 56), Vector2i(68, 56), Vector2i(56, 70),
	]):
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
	for spot in _spots([basin, basin + Vector2i(-8, 0), basin + Vector2i(8, 0)]):
		li += 1
		lights.append({
			"name": "DaisGlow%d" % li,
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"color": "Color(0.4, 0.85, 0.7, 1)",
			"energy": 0.5,
			"scale": 1.6,
		})

	var taken := LevelKit.keepout([entrance, exit_cell], 10)
	for cell: Vector2i in LevelKit.keepout([dais], 12).keys():
		taken[cell] = true
	var hostiles := _mobs(walk, taken, [
		["Crawler", "trpg/trpg_carrion_crawler", Vector2i(56, 64), 3],
		["CrawlerW", "trpg/trpg_carrion_crawler", Vector2i(42, 60), 2],
		["CrawlerE", "trpg/trpg_carrion_crawler", Vector2i(70, 60), 2],
		["AcidOoze", "trpg/trpg_acid_ooze", Vector2i(30, 52), 2],
		["AcidOozeE", "trpg/trpg_acid_ooze", Vector2i(82, 52), 2],
		["AcidOozeN", "trpg/trpg_acid_ooze", Vector2i(30, 30), 2],
		["Gorgon", "trpg/trpg_poisonous_gorgon", Vector2i(82, 30), 2],
		["GorgonN", "trpg/trpg_poisonous_gorgon", Vector2i(56, 18), 2],
		["Devourer", "trpg/trpg_intellect_devourer", Vector2i(36, 40), 2],
		["DevourerE", "trpg/trpg_intellect_devourer", Vector2i(76, 40), 2],
		["Zombie", "trpg/trpg_zombie_giant", Vector2i(42, 26), 2],
		["ZombieE", "trpg/trpg_zombie_giant", Vector2i(70, 26), 2],
		["TankGuard", "trpg/trpg_umber_hulk", Vector2i(44, 50), 2],
		["TankGuardE", "trpg/trpg_umber_hulk", Vector2i(68, 50), 2],
	], 10)
	hostiles.append({
		"name": "CisternSovereign",
		"type": TYPES + "bosses/cistern_sovereign.tres",
		"pos": LevelKit.tile_pos(dais),
	})

	var npc_a := _place(walk, taken, entrance + Vector2i(-6, -3), 3)

	assert(walk.has(entrance) and walk.has(exit_cell), "cistern spawn blocked")
	assert(walk.has(dais), "cistern dais blocked")
	assert(walk.size() > 8000, "cistern too small: %d" % walk.size())
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
		"camps": [{"name": "LandingFire", "pos": LevelKit.tile_pos(entrance + Vector2i(4, -4))}],
		"decos": decos,
		"lights": lights,
		"hostiles": hostiles,
		"npcs": [{
			"name": "DrownedKeeperVess", "resource": NPCS + "sewers/drowned_keeper_vess.tres",
			"pos": LevelKit.tile_pos(npc_a),
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
# bridges, dry and built rather than molten.

func _build_forge_gallery() -> void:
	_set_size(104, 78)
	var ts: TileSet = load(FORGE_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	var arrival := Vector2i(52, 68)
	var west := 30
	var east := 74
	var hall_rows := [18, 30, 42, 54]
	var chambers: Array = [[Vector2i(52, 67), 8.5, 0.24, 601]]
	var seed_i := 610
	for ry in hall_rows:
		chambers.append([Vector2i(west, ry), 8.0, 0.26, seed_i])
		chambers.append([Vector2i(east, ry), 8.0, 0.26, seed_i + 50])
		seed_i += 1
	var links: Array = [
		[Vector2i(52, 64), Vector2i(west, 54), 3.2, 2.2, 630],
		[Vector2i(52, 64), Vector2i(east, 54), 3.2, 2.2, 631],
	]
	var seed_j := 640
	for i in range(hall_rows.size() - 1):
		links.append([Vector2i(west, hall_rows[i]), Vector2i(west, hall_rows[i + 1]), 3.2, 1.8, seed_j])
		links.append([Vector2i(east, hall_rows[i]), Vector2i(east, hall_rows[i + 1]), 3.2, 1.8, seed_j + 40])
		seed_j += 1
	# The two cross bridges are kept apart from the rest: they are the only spans
	# the Gallery decks in iron, so the floor pass needs their exact shapes.
	var bridges: Array = []
	for ry in [18, 42]:
		bridges.append([Vector2i(west, ry), Vector2i(east, ry), 2.6, 2.6, seed_j])
		seed_j += 1
	links.append_array(bridges)
	var floor_mask := _carve(chambers, links, 4, arrival)

	var void_mask := LevelKit.void_of(floor_mask, W, H)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 3, Vector2i(2, 2))
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, _forge_rim(), _bounds, blocked)

	var walk := LevelKit.walkable(floor_mask, blocked)
	var entrance := LevelKit.pick_open(walk, _s(arrival))
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + Vector2i(0, 6))

	# --- Floor ---------------------------------------------------------------
	# The Gallery is the built floor of the Forge, so paving is the rule and raw
	# slate is the exception: every bay is laid, every hall run is a road, and
	# the slate only shows in the rock the crews never finished. `bias` runs
	# positive so this level sits a full value step above the Deeps.
	var depth := ForgeFloor.depth_field(floor_mask)
	var paved: Dictionary = {}
	for link: Array in links:
		MapKit.tunnel(paved, _s(link[0]), _s(link[1]), _sf(float(link[2])) * 0.5, _sf(float(link[3])), int(link[4]), _bounds)
	for ry in hall_rows:
		ForgeFloor.apron(paved, _s(Vector2i(west, ry)), int(_sf(4.5)))
		ForgeFloor.apron(paved, _s(Vector2i(east, ry)), int(_sf(4.5)))
	ForgeFloor.apron(paved, entrance, 9)
	ForgeFloor.apron(paved, exit_cell, 5)

	var owned: Dictionary = {}
	# A work plate at the head of every bay, on both halls.
	for spot in _spots([
		Vector2i(west, 15), Vector2i(east, 15), Vector2i(west, 27), Vector2i(east, 27),
		Vector2i(west, 39), Vector2i(east, 39), Vector2i(west, 51), Vector2i(east, 51),
	]):
		for cell: Vector2i in ForgeFloor.hearth(ground, floor_mask, LevelKit.pick_open(walk, spot)).keys():
			owned[cell] = true
	# Casting pits down the middle of both halls. This is the Gallery's signature
	# feature: it is the level where metal is actually poured, and each pit puts
	# a lit, moving thing on the floor for a player to navigate by.
	for spot in _spots([
		Vector2i(west, 21), Vector2i(east, 21), Vector2i(west, 33), Vector2i(east, 33),
		Vector2i(west, 45), Vector2i(east, 45), Vector2i(52, 62),
	]):
		var pit := LevelKit.pick_open(walk, spot)
		var placed := ForgeFloor.mold_pit(ground, floor_mask, pit)
		if placed.is_empty():
			continue
		for cell: Vector2i in placed.keys():
			owned[cell] = true
		walk.erase(pit)
	walk = MapKit.largest_region(walk, entrance)

	for cell: Vector2i in owned.keys():
		paved.erase(cell)
	var paved_done := ForgeFloor.pave(ground, paved, floor_mask, depth, 652, 0.20)
	for cell: Vector2i in paved_done.keys():
		owned[cell] = true
	ForgeFloor.paint_slate(ground, floor_mask, depth, 651, {"bias": 0.10, "skip": owned})

	# Iron decking over the middle of each cross bridge — the span itself, not
	# the approaches. The mesh is see-through, so it goes on Props above the
	# paving and reads as grating rather than as another floor colour.
	var deck: Dictionary = {}
	for link: Array in bridges:
		var a := Vector2(_s(link[0]))
		var b := Vector2(_s(link[1]))
		MapKit.tunnel(
			deck, Vector2i(a.lerp(b, 0.3)), Vector2i(a.lerp(b, 0.7)),
			_sf(float(link[2])) * 0.5, _sf(float(link[3])) * 0.4, int(link[4]), _bounds
		)
	ForgeFloor.catwalk(props, deck, walk, 653)

	var no_build := LevelKit.keepout([entrance, exit_cell], 6)
	# Nothing gets stamped onto the decked bridges: a prop there both punches a
	# hole in the grating art and squeezes the only east-west crossings.
	for cell: Vector2i in deck.keys():
		no_build[cell] = true
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)

	# Quench wells down the middle of each hall.
	for spot in _spots([
		Vector2i(west, 24), Vector2i(east, 24), Vector2i(west, 48), Vector2i(east, 48),
		Vector2i(west, 36), Vector2i(east, 36), Vector2i(west, 18), Vector2i(east, 18),
		Vector2i(west, 54), Vector2i(east, 54),
	]):
		LevelKit.stamp_landmark(props, 3, [8, 1, 3, 3], LevelKit.pick_open(free, spot), free, solid)
	LevelKit.scatter_props(props, 3, edges, [[8, 5, 1, 1], [9, 5, 1, 1], [10, 5, 1, 1]], 0.13, 4, 661, free, solid)
	LevelKit.scatter_props(props, 0, inner, [[0, 1, 1, 2], [2, 1, 1, 1], [0, 2, 1, 1], [1, 2, 1, 1]], 0.05, 6, 662, free, solid)
	LevelKit.scatter_props(props, 2, edges, [[0, 0, 1, 1], [1, 0, 1, 1], [2, 0, 1, 1]], 0.045, 7, 663, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	LevelKit.scatter_flat(overlay, 0, inner, [Vector2i(1, 1), Vector2i(3, 1)], 0.03, 6, 664, solid)
	# Swept slag along the hall walls — floor wear, not props.
	LevelKit.scatter_flat(overlay, ForgeFloor.SOURCE, edges, ForgeFloor.RUBBLE, 0.10, 3, 665, solid)

	var decos: Array = []
	var ti := 0
	for spot in _spots([
		Vector2i(west, 18), Vector2i(east, 18), Vector2i(west, 30), Vector2i(east, 30),
		Vector2i(west, 42), Vector2i(east, 42), Vector2i(west, 54), Vector2i(east, 54),
		Vector2i(52, 67), Vector2i(52, 60), Vector2i(west, 24), Vector2i(east, 24),
		Vector2i(west, 36), Vector2i(east, 36), Vector2i(west, 48), Vector2i(east, 48),
		Vector2i(41, 18), Vector2i(63, 18), Vector2i(41, 42), Vector2i(63, 42),
	]):
		ti += 1
		decos.append({
			"name": "GalleryTorch%d" % ti,
			"frames": "deco_forge_torch",
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, spot)),
			"scale": 1.3,
			"light": 0.75,
			"color": "Color(1, 0.58, 0.22, 1)",
		})

	var taken := LevelKit.keepout([entrance, exit_cell], 10)
	var hostiles := _mobs(walk, taken, [
		["ForgeAxeman", "trpg/trpg_armored_axeman", Vector2i(west, 54), 2],
		["ForgeAxemanE", "trpg/trpg_armored_axeman", Vector2i(east, 54), 2],
		["EliteOrc", "trpg/trpg_elite_orc", Vector2i(west, 42), 2],
		["EliteOrcE", "trpg/trpg_elite_orc", Vector2i(east, 42), 2],
		["ArmoredOrc", "trpg/trpg_armored_orc", Vector2i(west, 30), 2],
		["ArmoredOrcE", "trpg/trpg_armored_orc", Vector2i(east, 30), 2],
		["Lancer", "trpg/trpg_lancer", Vector2i(west, 18), 2],
		["LancerE", "trpg/trpg_lancer", Vector2i(east, 18), 2],
		["Templar", "trpg/trpg_knight_templar", Vector2i(52, 18), 2],
		["TemplarS", "trpg/trpg_knight_templar", Vector2i(52, 42), 2],
		["Wizard", "trpg/trpg_wizard", Vector2i(west, 36), 2],
		["WizardE", "trpg/trpg_wizard", Vector2i(east, 36), 2],
	], 9)

	var npc_a := _place(walk, taken, entrance + Vector2i(-6, -3), 3)
	var npc_b := _place(walk, taken, entrance + Vector2i(6, -3), 3)

	assert(walk.has(entrance) and walk.has(exit_cell), "gallery spawn blocked")
	assert(walk.size() > 6000, "gallery too small: %d" % walk.size())
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
		"camps": [{"name": "GalleryHearth", "pos": LevelKit.tile_pos(entrance + Vector2i(4, -4))}],
		"decos": decos,
		"hostiles": hostiles,
		"npcs": [
			{"name": "ForgemasterHelka", "resource": NPCS + "fire_forge/forgemaster_helka.tres",
				"pos": LevelKit.tile_pos(npc_a)},
			{"name": "BellowsHandTorv", "resource": NPCS + "fire_forge/bellows_hand_torv.tres",
				"pos": LevelKit.tile_pos(npc_b)},
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
# only way around.

func _build_forge_deeps() -> void:
	_set_size(112, 86)
	var ts: TileSet = load(FORGE_TS)
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)

	var arrival := Vector2i(56, 76)
	var lake := Vector2i(56, 40)
	var chambers: Array = [[Vector2i(56, 75), 8.5, 0.24, 701]]
	var links: Array = [[Vector2i(56, 70), Vector2i(56, 64), 3.4, 1.8, 702]]
	var prev := Vector2i(56, 64)
	var steps := 9
	for i in steps:
		var a: float = -PI * 0.5 + TAU * float(i) / float(steps - 1)
		var r: float = 36.0 - float(i) * 1.4
		var c := lake + Vector2i(int(cos(a) * r), int(sin(a) * r * 0.74))
		chambers.append([c, 8.5 - float(i) * 0.12, 0.27, 710 + i])
		links.append([prev, c, 3.0, 2.4, 730 + i])
		prev = c
	links.append([prev, lake + Vector2i(0, 17), 3.0, 1.6, 749])
	chambers.append([lake, 18.0, 0.16, 750])
	var floor_mask := _carve(chambers, links, 4, arrival)

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
	var entrance := LevelKit.pick_open(walk, _s(arrival))
	walk = MapKit.largest_region(walk, entrance)
	var exit_cell := LevelKit.pick_open(walk, entrance + Vector2i(0, 6))

	# The magma lake: animated lava, and a hazard rather than scenery.
	var lava_cells: Dictionary = {}
	for cell: Vector2i in _blob(lake, 8.5, 0.22, 761).keys():
		if walk.has(cell):
			lava_cells[cell] = true
	for spot in [
		[lake + Vector2i(-22, 11), 4.0, 762], [lake + Vector2i(22, 11), 4.0, 763],
		[lake + Vector2i(-20, -13), 3.6, 764], [lake + Vector2i(20, -13), 3.6, 765],
	]:
		for cell: Vector2i in _blob(spot[0], spot[1], 0.30, int(spot[2])).keys():
			if walk.has(cell):
				lava_cells[cell] = true
	var lava_anim := [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	for cell: Vector2i in lava_cells.keys():
		ground.set_cell(cell, 1, MapKit._pick(lava_anim, cell, 766))
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)
	var shore := LevelKit.pick_open(walk, _s(lake + Vector2i(0, 16)))

	# --- Floor ---------------------------------------------------------------
	# Below the foundry nobody paves anything except the route itself. The
	# Deeps are raw slate at a negative bias — a clear step darker than the
	# Gallery — with an ash apron burnt into every metre near the magma, and one
	# ribbon of old foundry paving winding down the spiral. That ribbon is the
	# level's only navigation aid, and the reason a player can tell which ledge
	# they have already walked.
	var deeps_depth := ForgeFloor.depth_field(floor_mask)
	var descent: Dictionary = {}
	for link: Array in links:
		MapKit.tunnel(descent, _s(link[0]), _s(link[1]), _sf(float(link[2])) * 0.42, _sf(float(link[3])), int(link[4]), _bounds)
	ForgeFloor.apron(descent, entrance, 6)
	ForgeFloor.apron(descent, exit_cell, 3)
	ForgeFloor.apron(descent, shore, 7)
	for cell: Vector2i in lava_cells.keys():
		descent.erase(cell)

	# The lava is already on Ground at this point, so it has to be excluded by
	# name — the floor pass covers the whole carved mask, including the cells
	# under the wall rim, so no gap can open behind a transparent rim pixel.
	# `wear` runs high here: this is the oldest paving in the Forge and most of
	# it has cracked back to rock.
	var deeps_owned: Dictionary = lava_cells.duplicate()
	for cell: Vector2i in ForgeFloor.pave(ground, descent, floor_mask, deeps_depth, 752, 0.34).keys():
		deeps_owned[cell] = true
	ForgeFloor.paint_slate(ground, floor_mask, deeps_depth, 751, {
		"bias": -0.14,
		"scorch": ForgeFloor.scorch_of(lava_cells, floor_mask, 4),
		"skip": deeps_owned,
	})

	var blocked_all := blocked.duplicate()
	for cell: Vector2i in lava_cells.keys():
		blocked_all[cell] = true
	var no_build := LevelKit.keepout([entrance, exit_cell], 6)
	for cell: Vector2i in LevelKit.keepout([shore], 12).keys():
		no_build[cell] = true
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not no_build.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	var edges := MapKit.edge_cells(walk, blocked_all)
	var inner := MapKit.interior_cells(walk, blocked_all, 3)

	LevelKit.scatter_props(props, 3, edges, [[8, 5, 1, 1], [9, 5, 1, 1], [10, 5, 1, 1]], 0.15, 4, 771, free, solid)
	LevelKit.scatter_props(props, 0, inner, [[0, 2, 1, 1], [1, 2, 1, 1], [1, 1, 1, 1]], 0.06, 5, 772, free, solid)
	LevelKit.scatter_props(props, 2, edges, [[1, 0, 1, 1], [2, 0, 1, 1]], 0.05, 6, 773, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	LevelKit.scatter_flat(overlay, 0, inner, [Vector2i(2, 1), Vector2i(3, 1)], 0.025, 7, 774, solid)
	# Fallen rock, heavier here than in the Gallery: nothing sweeps this floor.
	LevelKit.scatter_flat(overlay, ForgeFloor.SOURCE, edges, ForgeFloor.RUBBLE, 0.14, 3, 785, solid)
	LevelKit.scatter_flat(overlay, ForgeFloor.SOURCE, inner, ForgeFloor.RUBBLE, 0.05, 5, 786, solid)

	var decos: Array = []
	var ti := 0
	var deco_spots: Array = [Vector2i(56, 75), Vector2i(56, 64), Vector2i(56, 70)]
	for i in steps:
		var a: float = -PI * 0.5 + TAU * float(i) / float(steps - 1)
		var r: float = 36.0 - float(i) * 1.4
		deco_spots.append(lake + Vector2i(int(cos(a) * r), int(sin(a) * r * 0.74)))
		deco_spots.append(lake + Vector2i(int(cos(a) * (r - 7.0)), int(sin(a) * (r - 7.0) * 0.74)))
	for spot in _spots(deco_spots):
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
	var lights: Array = []
	var li := 0
	for cell: Vector2i in lava_cells.keys():
		if MapKit.hash2(cell.x, cell.y, 775) % 149 != 0:
			continue
		li += 1
		lights.append({
			"name": "MagmaGlow%d" % li,
			"pos": LevelKit.tile_pos(cell),
			"color": "Color(1, 0.36, 0.1, 1)",
			"energy": 0.55,
			"scale": 1.3,
		})

	var taken := LevelKit.keepout([entrance, exit_cell], 10)
	for cell: Vector2i in LevelKit.keepout([shore], 12).keys():
		taken[cell] = true
	var hostiles := _mobs(walk, taken, [
		["Demon", "trpg/trpg_demon_a", Vector2i(56, 64), 3],
		["DemonW", "trpg/trpg_demon_a", Vector2i(44, 62), 2],
		["DemonE", "trpg/trpg_demon_a", Vector2i(68, 62), 2],
		["Oni", "trpg/trpg_conjuring_oni", lake + Vector2i(-30, 8), 2],
		["OniE", "trpg/trpg_conjuring_oni", lake + Vector2i(30, 8), 2],
		["OgreMage", "trpg/trpg_ogre_mage", lake + Vector2i(-28, -10), 2],
		["OgreMageE", "trpg/trpg_ogre_mage", lake + Vector2i(28, -10), 2],
		["Fomorian", "trpg/trpg_wretched_fomorian", lake + Vector2i(0, -28), 2],
		["FomorianW", "trpg/trpg_wretched_fomorian", lake + Vector2i(-16, -24), 2],
		["UmberHulk", "trpg/trpg_umber_hulk", lake + Vector2i(16, -24), 2],
		["BloodMonster", "trpg/trpg_blood_monster_a", lake + Vector2i(-24, 18), 2],
		["BloodMonsterE", "trpg/trpg_blood_monster_a", lake + Vector2i(24, 18), 2],
		["EliteOrc", "trpg/trpg_elite_orc", lake + Vector2i(-10, 22), 2],
		["EliteOrcE", "trpg/trpg_elite_orc", lake + Vector2i(10, 22), 2],
	], 10)
	hostiles.append({
		"name": "Cinderborn",
		"type": TYPES + "bosses/cinderborn.tres",
		"pos": LevelKit.tile_pos(shore),
	})

	var npc_a := _place(walk, taken, entrance + Vector2i(-6, -3), 3)

	assert(walk.has(entrance) and walk.has(exit_cell), "deeps spawn blocked")
	assert(walk.has(shore), "deeps shore blocked")
	assert(walk.size() > 6000, "deeps too small: %d" % walk.size())
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
		"camps": [{"name": "DeepHearth", "pos": LevelKit.tile_pos(entrance + Vector2i(4, -4))}],
		"decos": decos,
		"lights": lights,
		"hostiles": hostiles,
		"npcs": [{
			"name": "CinderwrightMaro", "resource": NPCS + "fire_forge/cinderwright_maro.tres",
			"pos": LevelKit.tile_pos(npc_a),
		}],
		"spawn": LevelKit.tile_pos(entrance),
		"warpers": [{"name": "Entrance", "pos": LevelKit.tile_pos(entrance), "id": 45}],
		"portals": [{
			"name": "AscentPortal", "pos": LevelKit.tile_pos(exit_cell),
			"id": 145, "target_id": 55, "instance": INST + "fire_forge.tres",
			"label": "Fire Forge", "color": "Color(0.7, 0.2, 0.05, 1)",
		}],
	})
