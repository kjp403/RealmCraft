extends SceneTree
## Build East Wilds hub + three biome stubs (dunes / wetlands / ash fields).
## Organic MapKit chambers+tunnels like build_stub_biomes.gd — not stripe fills.
##
##   godot --headless --path . -s tools/build_woodland_east_wilds.gd

const MapKit := preload("res://tools/lib/mapkit.gd")
const ForgeFloor := preload("res://tools/lib/forgefloor.gd")

const DESERT_TS := "res://source/common/gameplay/maps/tilesets/desert_tileset.tres"
const FORGE_TS := "res://source/common/gameplay/maps/tilesets/fire_forge_tileset.tres"
const SEWERS_TS := "res://source/common/gameplay/maps/tilesets/sewers_tileset.tres"

const WARPER := "res://source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn"
const PORTAL := "res://source/common/gameplay/maps/components/interaction_areas/warper/portal/portal.tscn"
const WOODLAND := "res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland.tres"
const INST := "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const CAMP := "res://source/common/gameplay/lighting/campfire.tscn"
const GLOW := "res://source/common/gameplay/lighting/light_radial.tres"
const MAP_SCRIPT := "res://source/common/gameplay/maps/map.gd"
const RP_SCRIPT := "res://source/common/network/sync/replicated_props.gd"
const CRITTER_SCN := "res://source/common/gameplay/props/ambient_critter.tscn"
const DECO_SCN := "res://source/common/gameplay/props/animated_deco.tscn"
const HOSTILE_SCN := "res://source/common/gameplay/characters/npc/hostile_npc.tscn"
const TYPES := "res://source/common/gameplay/characters/npc/types/"
const OUT_DIR := "res://source/common/gameplay/maps/maps/woodland/"

## 1x surface scale: stub-sized but same organic quality as desert/sewers/forge.
const SURFACE_S := 1
const SURFACE_WOBBLE := 1.0

var W: int = 64
var H: int = 48
var _bounds := Rect2i(0, 0, 64, 48)


func _sc(x: int, y: int) -> Vector2i:
	return Vector2i(x * SURFACE_S, y * SURFACE_S)


func _sr(v: float) -> float:
	return v * float(SURFACE_S)


func _sn(n: int) -> int:
	return n * SURFACE_S


func _sw(w: float) -> float:
	return minf(w * SURFACE_WOBBLE, 0.45)


func _sh(v: float) -> float:
	return v * sqrt(float(SURFACE_S))


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_east_wilds_hub()
	_build_east_dunes()
	_build_east_wetlands()
	_build_east_ash_fields()
	print("WOODLAND_EAST_WILDS_PASS")
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


func _keepout(spots: Array, radius: int) -> Dictionary:
	var out: Dictionary = {}
	for spot in spots:
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				out[spot + Vector2i(ox, oy)] = true
	return out


# --- East Wilds hub ---------------------------------------------------------

func _build_east_wilds_hub() -> void:
	_set_size(_sn(88), _sn(64))
	var ts: TileSet = load(DESERT_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts

	var entrance_hint := _sc(44, 52)
	var floor_mask := _carve(
		[
			[_sc(44, 50), _sr(11.0), _sw(0.22), 201],
			[_sc(44, 36), _sr(10.0), _sw(0.24), 202],
			[_sc(22, 34), _sr(8.0), _sw(0.28), 203],
			[_sc(66, 34), _sr(8.0), _sw(0.28), 204],
			[_sc(44, 18), _sr(8.5), _sw(0.26), 205],
			[_sc(28, 20), _sr(6.5), _sw(0.30), 206],
			[_sc(60, 20), _sr(6.5), _sw(0.30), 207],
		],
		[
			[_sc(44, 44), _sc(44, 28), _sr(3.0), _sr(2.0), 211],
			[_sc(36, 40), _sc(26, 36), _sr(2.4), _sr(2.5), 212],
			[_sc(52, 40), _sc(62, 36), _sr(2.4), _sr(2.5), 213],
			[_sc(36, 24), _sc(30, 20), _sr(2.2), _sr(2.5), 214],
			[_sc(52, 24), _sc(58, 20), _sr(2.2), _sr(2.5), 215],
			[_sc(44, 28), _sc(44, 20), _sr(2.6), _sr(2.0), 216],
		],
		_sn(4),
		entrance_hint
	)

	# Dirt path spines toward the three biome exits + woodland return.
	var path: Dictionary = {}
	MapKit.tunnel(path, _sc(44, 50), _sc(44, 18), _sr(2.0), _sr(1.5), 221, _bounds)
	MapKit.tunnel(path, _sc(44, 36), _sc(22, 34), _sr(1.8), _sr(1.8), 222, _bounds)
	MapKit.tunnel(path, _sc(44, 36), _sc(66, 34), _sr(1.8), _sr(1.8), 223, _bounds)
	MapKit.tunnel(path, _sc(44, 50), _sc(44, 56), _sr(2.2), _sr(1.2), 224, _bounds)

	var sand := [
		Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 2),
		Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3),
	]
	var dirt := [Vector2i(2, 2), Vector2i(3, 2), Vector2i(1, 2), Vector2i(4, 2)]
	for cell: Vector2i in floor_mask.keys():
		if path.has(cell):
			ground.set_cell(cell, 0, MapKit._pick(dirt, cell, 231))
		else:
			ground.set_cell(cell, 0, MapKit._pick(sand, cell, 232))

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
	var woodland_portal := _pick_open(walk, entrance + Vector2i(0, _sn(4)))
	var dunes_portal := _pick_open(walk, _sc(22, 34))
	var wetlands_portal := _pick_open(walk, _sc(66, 34))
	var ash_portal := _pick_open(walk, _sc(44, 18))

	var keepout := _keepout([entrance, woodland_portal, dunes_portal, wetlands_portal, ash_portal], 3)
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not keepout.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	_scatter_props(props, 0, edges, [[10, 7, 2, 2], [12, 7, 2, 2]], 0.08, 5, 241, free, solid)
	_scatter_flat(props, 0, inner, [[10, 5], [11, 5], [12, 5], [13, 5]], 0.08, 3, 242, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	var camp_cell := _pick_open(walk, _sc(44, 40))
	var decos: Array = []
	var ti := 0
	for spot in [_sc(22, 34), _sc(66, 34), _sc(44, 18), _sc(44, 50), _sc(30, 40), _sc(58, 40)]:
		var cell := _pick_open(walk, spot)
		ti += 1
		decos.append({
			"name": "FrontierTorch%d" % ti,
			"frames": "deco_torch",
			"pos": _tile_pos(cell),
			"scale": 1.25,
			"light": 0.55,
			"color": "Color(1, 0.78, 0.42, 1)",
		})

	assert(walk.has(entrance), "hub entrance blocked")
	print("east_wilds hub walk=", walk.size())

	_write_hub({
		"root": "woodland_east_wilds",
		"out": OUT_DIR + "woodland_east_wilds.tscn",
		"tileset": DESERT_TS,
		"bg": "Color(0.08, 0.06, 0.04, 1)",
		"modulate": "Color(1, 0.96, 0.88, 1)",
		"music": "res://assets/audio/music/fungus.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"decos": decos,
		"entrance": _tile_pos(entrance),
		"woodland_portal": _tile_pos(woodland_portal),
		"dunes_portal": _tile_pos(dunes_portal),
		"wetlands_portal": _tile_pos(wetlands_portal),
		"ash_portal": _tile_pos(ash_portal),
		"camp": _tile_pos(camp_cell),
		"walk_count": walk.size(),
		"wall_count": walls.get_used_cells().size(),
		"prop_count": props.get_used_cells().size(),
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
	})


# --- East Dunes (desert tileset) --------------------------------------------

func _build_east_dunes() -> void:
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

	for spot in [
		[_sc(38, 40), _sh(3.4), 121], [_sc(66, 40), _sh(3.4), 122],
		[_sc(52, 24), _sh(3.0), 123], [_sc(34, 56), _sh(2.8), 124],
		[_sc(70, 56), _sh(2.8), 125],
	]:
		var mesa: Dictionary = {}
		MapKit.blob(mesa, spot[0], spot[1], _sw(0.28), int(spot[2]), _bounds)
		mesa = MapKit.smooth(mesa, _bounds, 1, 5, 4)
		for cell: Vector2i in mesa.keys():
			floor_mask.erase(cell)
	floor_mask = MapKit.largest_region(floor_mask, _pick_open(floor_mask, entrance_hint))

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

	var keepout := _keepout([entrance, portal], 3)
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not keepout.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	_scatter_props(props, 0, edges, [[10, 7, 2, 2], [12, 7, 2, 2], [10, 1, 2, 2]], 0.10, 5, 141, free, solid)
	_scatter_props(props, 0, inner, [[10, 14, 1, 3], [11, 14, 1, 3], [12, 14, 1, 3]], 0.04, 6, 142, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)
	_scatter_flat(props, 0, inner, [[10, 5], [11, 5], [12, 5], [13, 5], [14, 5]], 0.09, 3, 143, solid)

	var decos: Array = []
	var ti := 0
	for spot in [
		_sc(24, 20), _sc(80, 20), _sc(52, 16), _sc(52, 63),
		_sc(26, 44), _sc(78, 44), _sc(52, 32), _sc(52, 50),
	]:
		var cell := _pick_open(walk, spot)
		ti += 1
		decos.append({
			"name": "DuneTorch%d" % ti,
			"frames": "deco_torch",
			"pos": _tile_pos(cell),
			"scale": 1.2,
			"light": 0.45,
			"color": "Color(1, 0.82, 0.5, 1)",
		})

	var taken := _keepout([entrance, portal], _sn(6))
	var hostiles := _mobs(walk, taken, [
		["DuneScout", "trpg/trpg_archer", _sc(52, 40), 1],
		["DuneOrc", "trpg/trpg_orc", _sc(30, 44), 1],
	], _sn(5))

	assert(walk.has(entrance) and walk.has(portal), "dunes spawn blocked")
	assert(walk.size() > 400, "dunes too small: %d" % walk.size())
	print("east_dunes walk=", walk.size())

	_write_biome({
		"root": "east_dunes",
		"out": OUT_DIR + "east_dunes.tscn",
		"tileset": DESERT_TS,
		"bg": "Color(0.09, 0.07, 0.05, 1)",
		"modulate": "Color(1, 0.97, 0.9, 1)",
		"music": "res://assets/audio/music/fungus.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"decos": decos,
		"hostiles": hostiles,
		"entrance": _tile_pos(entrance),
		"portal": _tile_pos(portal),
		"entrance_id": 61,
		"portal_id": 161,
		"portal_color": "Color(0.85, 0.66, 0.25, 1)",
		"portal_label": "Goblin Woodland",
		"walk_count": walk.size(),
		"wall_count": walls.get_used_cells().size(),
		"prop_count": props.get_used_cells().size(),
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
	})


# --- East Wetlands (sewers tileset) -----------------------------------------

func _build_east_wetlands() -> void:
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

	var keepout := _keepout([entrance, portal], 3)
	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)
	var free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not keepout.has(cell):
			free[cell] = true
	var solid: Dictionary = {}
	_scatter_props(props, 0, edges, [[6, 4, 1, 2], [7, 4, 1, 2], [8, 4, 1, 2]], 0.14, 4, 71, free, solid)
	_scatter_props(props, 0, inner, [[6, 3, 1, 1], [7, 3, 1, 1], [8, 3, 1, 1]], 0.04, 6, 72, free, solid)
	_scatter_flat(props, 0, inner, [[9, 4], [9, 5], [7, 7], [8, 6]], 0.06, 3, 73, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	var decos: Array = []
	var ti := 0
	for spot in [
		_sc(24, 50), _sc(88, 50), _sc(56, 44), _sc(30, 24),
		_sc(82, 24), _sc(56, 16), _sc(48, 62), _sc(64, 62), _sc(56, 71),
	]:
		var cell := _pick_open(walk, spot)
		ti += 1
		decos.append({
			"name": "WetTorch%d" % ti,
			"frames": "deco_torch" if ti % 3 != 0 else "deco_candle_a",
			"pos": _tile_pos(cell),
			"scale": 1.35,
			"light": 0.9,
			"color": "Color(0.55, 0.95, 0.6, 1)" if ti % 3 == 0 else "Color(1, 0.72, 0.38, 1)",
		})

	var taken := _keepout([entrance, portal], _sn(6))
	var hostiles := _mobs(walk, taken, [
		["MarshSlime", "trpg/trpg_slime", _sc(56, 44), 1],
		["MarshBat", "trpg/trpg_bat", _sc(30, 50), 1],
	], _sn(5))

	assert(walk.has(entrance) and walk.has(portal), "wetlands spawn blocked")
	assert(walk.size() > 400, "wetlands too small: %d" % walk.size())
	print("east_wetlands walk=", walk.size())

	_write_biome({
		"root": "east_wetlands",
		"out": OUT_DIR + "east_wetlands.tscn",
		"tileset": SEWERS_TS,
		"bg": "Color(0.015, 0.025, 0.02, 1)",
		"modulate": "Color(0.72, 0.82, 0.74, 1)",
		"music": "res://assets/audio/music/fungus.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"decos": decos,
		"hostiles": hostiles,
		"entrance": _tile_pos(entrance),
		"portal": _tile_pos(portal),
		"entrance_id": 62,
		"portal_id": 162,
		"portal_color": "Color(0, 0.53, 0.27, 1)",
		"portal_label": "Goblin Woodland",
		"walk_count": walk.size(),
		"wall_count": walls.get_used_cells().size(),
		"prop_count": props.get_used_cells().size(),
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
	})


# --- East Ash Fields (fire forge tileset) -----------------------------------

func _build_east_ash_fields() -> void:
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

	var lava_cells: Dictionary = {}
	for spot in [
		[_sc(24, 24), _sh(3.6), 81], [_sc(88, 24), _sh(3.6), 82],
		[_sc(56, 42), _sh(4.0), 85],
	]:
		var pool: Dictionary = {}
		MapKit.blob(pool, spot[0], spot[1], _sw(0.30), int(spot[2]), _bounds)
		pool = MapKit.smooth(pool, _bounds, 1, 5, 4)
		for cell: Vector2i in pool.keys():
			if walk.has(cell):
				lava_cells[cell] = true

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
	for spot in [_sc(56, 60), _sc(30, 48), _sc(82, 48), _sc(56, 15)]:
		for cell: Vector2i in ForgeFloor.hearth(ground, floor_mask, _pick_open(walk, spot)).keys():
			owned[cell] = true
	for cell: Vector2i in owned.keys():
		paved.erase(cell)
	for cell: Vector2i in ForgeFloor.pave(ground, paved, floor_mask, depth, 72, 0.28, float(SURFACE_S)).keys():
		owned[cell] = true
	ForgeFloor.paint_slate(ground, floor_mask, depth, 71, {
		"scorch": scorch, "skip": owned, "unit": float(SURFACE_S),
	})

	var lava_tiles := [Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11)]
	for cell: Vector2i in lava_cells.keys():
		ground.set_cell(cell, 0, MapKit._pick(lava_tiles, cell, 86))
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	var keepout := _keepout([entrance, portal], 3)
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
	_scatter_props(props, 3, edges, [[8, 5, 1, 1], [9, 5, 1, 1], [10, 5, 1, 1]], 0.12, 4, 91, free, solid)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)
	for cell in MapKit.scatter(edges, 0.10, 3, 93):
		if solid.has(cell) or props.get_cell_source_id(cell) >= 0:
			continue
		props.set_cell(cell, ForgeFloor.SOURCE, MapKit._pick(ForgeFloor.RUBBLE, cell, 94))

	var decos: Array = []
	var ti := 0
	for spot in [
		_sc(24, 24), _sc(88, 24), _sc(56, 18), _sc(56, 42),
		_sc(26, 52), _sc(86, 52), _sc(56, 60), _sc(56, 71),
	]:
		var cell := _pick_open(walk, spot)
		ti += 1
		decos.append({
			"name": "AshTorch%d" % ti,
			"frames": "deco_forge_torch",
			"pos": _tile_pos(cell),
			"scale": 1.3,
			"light": 0.7,
			"color": "Color(1, 0.55, 0.2, 1)",
		})

	var lights := ""
	var li := 0
	for cell: Vector2i in lava_cells.keys():
		if MapKit.hash2(cell.x, cell.y, 95) % 29 != 0:
			continue
		li += 1
		var p := _tile_pos(cell)
		lights += (
			"\n[node name=\"LavaGlow%d\" type=\"PointLight2D\" parent=\"SceneProps\"]\n" % li
			+ "position = Vector2(%s, %s)\n" % [str(p.x), str(p.y)]
			+ "color = Color(1, 0.4, 0.12, 1)\nenergy = 0.7\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.3\n"
		)

	var taken := _keepout([entrance, portal], _sn(6))
	var hostiles := _mobs(walk, taken, [
		["AshKnight", "trpg/trpg_knight", _sc(56, 50), 1],
		["AshOrc", "trpg/trpg_armored_orc", _sc(30, 48), 1],
	], _sn(5))

	assert(walk.has(entrance) and walk.has(portal), "ash spawn blocked")
	assert(walk.size() > 400, "ash too small: %d" % walk.size())
	print("east_ash_fields walk=", walk.size(), " lava=", lava_cells.size())

	_write_biome({
		"root": "east_ash_fields",
		"out": OUT_DIR + "east_ash_fields.tscn",
		"tileset": FORGE_TS,
		"bg": "Color(0.04, 0.015, 0.012, 1)",
		"modulate": "Color(0.82, 0.74, 0.72, 1)",
		"music": "res://assets/audio/music/shadow_temple.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"decos": decos,
		"hostiles": hostiles,
		"entrance": _tile_pos(entrance),
		"portal": _tile_pos(portal),
		"entrance_id": 63,
		"portal_id": 163,
		"portal_color": "Color(0.74, 0.25, 0, 1)",
		"portal_label": "Goblin Woodland",
		"walk_count": walk.size(),
		"wall_count": walls.get_used_cells().size(),
		"prop_count": props.get_used_cells().size(),
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
		"lights": lights,
	})


# --- Writers ----------------------------------------------------------------

func _frame_ext(decos: Array) -> Array:
	var frame_ext := ""
	var frame_ids: Dictionary = {}
	var next_id := 0
	for d in decos:
		var slug: String = d["frames"]
		if frame_ids.has(slug):
			continue
		var eid := "sf%d" % next_id
		next_id += 1
		frame_ids[slug] = eid
		frame_ext += "[ext_resource type=\"SpriteFrames\" path=\"res://source/common/gameplay/props/sprite_frames/%s.tres\" id=\"%s\"]\n" % [slug, eid]
	return [frame_ext, frame_ids]


func _hostile_bits(hostiles: Array) -> Dictionary:
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
	return {
		"ext": hostile_ext,
		"nodes": hostile_nodes,
		"id_map": id_map_lines,
	}


func _deco_nodes(decos: Array, frame_ids: Dictionary) -> String:
	var scene_nodes := ""
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
	return scene_nodes


func _write_biome(cfg: Dictionary) -> void:
	var decos: Array = cfg.get("decos", [])
	var hostiles: Array = cfg.get("hostiles", [])
	var frames := _frame_ext(decos)
	var frame_ext: String = frames[0]
	var frame_ids: Dictionary = frames[1]
	var hb := _hostile_bits(hostiles)
	var music_ext := "[ext_resource type=\"AudioStream\" path=\"%s\" id=\"music\"]\n" % cfg["music"]
	var camps := (
		"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
		+ "position = Vector2(%s, %s)\n" % [
			str((cfg["entrance"] as Vector2 + Vector2(32, -32)).x),
			str((cfg["entrance"] as Vector2 + Vector2(32, -32)).y),
		]
	)
	var text := """[gd_scene format=3]

[ext_resource type=\"Script\" uid=\"uid://7mbux4mybta0\" path=\"%s\" id=\"1_map\"]
[ext_resource type=\"TileSet\" path=\"%s\" id=\"2_tiles\"]
%s[ext_resource type=\"Script\" uid=\"uid://wq8klpndipnu\" path=\"%s\" id=\"4_rp\"]
[ext_resource type=\"PackedScene\" uid=\"uid://b2ckixon7ryh6\" path=\"%s\" id=\"5_warper\"]
[ext_resource type=\"PackedScene\" uid=\"uid://0m5eq6iylq26\" path=\"%s\" id=\"6_portal\"]
[ext_resource type=\"Resource\" uid=\"uid://c0m2t2hjlih2p\" path=\"%s\" id=\"7_woodland\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"8_camp\"]
[ext_resource type=\"Texture2D\" path=\"%s\" id=\"9_glow\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"deco\"]
%s%s
[node name=\"%s\" type=\"Node2D\" node_paths=PackedStringArray(\"replicated_props_container\")]
y_sort_enabled = true
script = ExtResource(\"1_map\")
replicated_props_container = NodePath(\"ReplicatedPropsContainer\")
map_background_color = %s
music = ExtResource(\"music\")
camera_limit_left = -16
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
destination_label = \"%s\"
target_instance = ExtResource(\"7_woodland\")
warper_id = %d
target_id = 60
""" % [
		MAP_SCRIPT, cfg["tileset"], music_ext, RP_SCRIPT, WARPER, PORTAL, WOODLAND, CAMP, GLOW,
		DECO_SCN, frame_ext, hb["ext"],
		cfg["root"], cfg["bg"], int(cfg["cam_right"]), int(cfg["cam_bottom"]), cfg["modulate"],
		cfg["ground_b64"], cfg["walls_b64"], cfg["props_b64"],
		cfg.get("lights", ""), camps, _deco_nodes(decos, frame_ids),
		hb["id_map"], hb["nodes"],
		str(cfg["entrance"].x), str(cfg["entrance"].y),
		str(cfg["entrance"].x), str(cfg["entrance"].y), int(cfg["entrance_id"]),
		str(cfg["portal"].x), str(cfg["portal"].y), cfg["portal_color"],
		cfg.get("portal_label", "Goblin Woodland"),
		int(cfg["portal_id"]),
	]
	var f := FileAccess.open(cfg["out"], FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print(
		"wrote ", cfg["out"],
		" walk=", cfg.get("walk_count", 0),
		" walls=", cfg.get("wall_count", 0),
		" props=", cfg.get("prop_count", 0),
		" decos=", decos.size(),
		" mobs=", hostiles.size()
	)


func _write_hub(cfg: Dictionary) -> void:
	var decos: Array = cfg.get("decos", [])
	var frames := _frame_ext(decos)
	var frame_ext: String = frames[0]
	var frame_ids: Dictionary = frames[1]
	var music_ext := "[ext_resource type=\"AudioStream\" path=\"%s\" id=\"music\"]\n" % cfg["music"]
	var camp_pos: Vector2 = cfg["camp"]
	var labels := """
[node name=\"LabelWoodland\" type=\"Label\" parent=\".\"]
offset_left = %s
offset_top = %s
offset_right = %s
offset_bottom = %s
theme_override_colors/font_color = Color(0.85, 0.95, 0.7, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 14
text = \"Woodland\"
horizontal_alignment = 1

[node name=\"LabelDunes\" type=\"Label\" parent=\".\"]
offset_left = %s
offset_top = %s
offset_right = %s
offset_bottom = %s
theme_override_colors/font_color = Color(0.95, 0.85, 0.45, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 14
text = \"East Dunes\"
horizontal_alignment = 1

[node name=\"LabelWetlands\" type=\"Label\" parent=\".\"]
offset_left = %s
offset_top = %s
offset_right = %s
offset_bottom = %s
theme_override_colors/font_color = Color(0.45, 0.9, 0.65, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 14
text = \"East Wetlands\"
horizontal_alignment = 1

[node name=\"LabelAsh\" type=\"Label\" parent=\".\"]
offset_left = %s
offset_top = %s
offset_right = %s
offset_bottom = %s
theme_override_colors/font_color = Color(1, 0.55, 0.3, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 14
text = \"Ash Fields\"
horizontal_alignment = 1

[node name=\"LabelHub\" type=\"Label\" parent=\".\"]
offset_left = %s
offset_top = %s
offset_right = %s
offset_bottom = %s
theme_override_colors/font_color = Color(1, 0.92, 0.7, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 18
text = \"East Wilds\"
horizontal_alignment = 1
""" % [
		str(cfg["woodland_portal"].x - 60), str(cfg["woodland_portal"].y - 48),
		str(cfg["woodland_portal"].x + 60), str(cfg["woodland_portal"].y - 28),
		str(cfg["dunes_portal"].x - 60), str(cfg["dunes_portal"].y - 48),
		str(cfg["dunes_portal"].x + 60), str(cfg["dunes_portal"].y - 28),
		str(cfg["wetlands_portal"].x - 70), str(cfg["wetlands_portal"].y - 48),
		str(cfg["wetlands_portal"].x + 70), str(cfg["wetlands_portal"].y - 28),
		str(cfg["ash_portal"].x - 60), str(cfg["ash_portal"].y - 48),
		str(cfg["ash_portal"].x + 60), str(cfg["ash_portal"].y - 28),
		str(cfg["entrance"].x - 70), str(cfg["entrance"].y - 80),
		str(cfg["entrance"].x + 70), str(cfg["entrance"].y - 56),
	]

	var text := """[gd_scene format=3]

[ext_resource type=\"Script\" uid=\"uid://7mbux4mybta0\" path=\"%s\" id=\"1_map\"]
[ext_resource type=\"TileSet\" path=\"%s\" id=\"2_tiles\"]
%s[ext_resource type=\"Script\" uid=\"uid://wq8klpndipnu\" path=\"%s\" id=\"4_rp\"]
[ext_resource type=\"PackedScene\" uid=\"uid://b2ckixon7ryh6\" path=\"%s\" id=\"5_warper\"]
[ext_resource type=\"PackedScene\" uid=\"uid://0m5eq6iylq26\" path=\"%s\" id=\"6_portal\"]
[ext_resource type=\"Resource\" uid=\"uid://c0m2t2hjlih2p\" path=\"%s\" id=\"7_woodland\"]
[ext_resource type=\"Resource\" path=\"%seast_dunes.tres\" id=\"8_dunes\"]
[ext_resource type=\"Resource\" path=\"%seast_wetlands.tres\" id=\"9_wet\"]
[ext_resource type=\"Resource\" path=\"%seast_ash_fields.tres\" id=\"10_ash\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"11_camp\"]
[ext_resource type=\"Texture2D\" path=\"%s\" id=\"9_glow\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"deco\"]
%s
[node name=\"%s\" type=\"Node2D\" node_paths=PackedStringArray(\"replicated_props_container\")]
y_sort_enabled = true
script = ExtResource(\"1_map\")
replicated_props_container = NodePath(\"ReplicatedPropsContainer\")
map_background_color = %s
music = ExtResource(\"music\")
camera_limit_left = -16
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

[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"11_camp\")]
position = Vector2(%s, %s)
%s
[node name=\"ReplicatedPropsContainer\" type=\"Node2D\" parent=\".\" node_paths=PackedStringArray(\"id_to_node\", \"node_to_id\")]
y_sort_enabled = true
script = ExtResource(\"4_rp\")
id_to_node = {}
node_to_id = {}

[node name=\"RespawnPoint\" parent=\".\" instance=ExtResource(\"5_warper\")]
position = Vector2(%s, %s)

[node name=\"Entrance\" parent=\".\" instance=ExtResource(\"5_warper\")]
position = Vector2(%s, %s)
warper_id = 60

[node name=\"WoodlandPortal\" parent=\".\" instance=ExtResource(\"6_portal\")]
position = Vector2(%s, %s)
portal_color = Color(0.45, 0.7, 0.35, 1)
destination_label = \"Goblin Woodland\"
target_instance = ExtResource(\"7_woodland\")
warper_id = 160
target_id = 60

[node name=\"DunesPortal\" parent=\".\" instance=ExtResource(\"6_portal\")]
position = Vector2(%s, %s)
portal_color = Color(0.85, 0.66, 0.25, 1)
destination_label = \"East Dunes\"
target_instance = ExtResource(\"8_dunes\")
warper_id = 71
target_id = 61

[node name=\"WetlandsPortal\" parent=\".\" instance=ExtResource(\"6_portal\")]
position = Vector2(%s, %s)
portal_color = Color(0, 0.53, 0.27, 1)
destination_label = \"East Wetlands\"
target_instance = ExtResource(\"9_wet\")
warper_id = 72
target_id = 62

[node name=\"AshPortal\" parent=\".\" instance=ExtResource(\"6_portal\")]
position = Vector2(%s, %s)
portal_color = Color(0.74, 0.25, 0, 1)
destination_label = \"Ash Fields\"
target_instance = ExtResource(\"10_ash\")
warper_id = 73
target_id = 63
%s
""" % [
		MAP_SCRIPT, cfg["tileset"], music_ext, RP_SCRIPT, WARPER, PORTAL, WOODLAND,
		INST, INST, INST, CAMP, GLOW, DECO_SCN, frame_ext,
		cfg["root"], cfg["bg"], int(cfg["cam_right"]), int(cfg["cam_bottom"]), cfg["modulate"],
		cfg["ground_b64"], cfg["walls_b64"], cfg["props_b64"],
		str(camp_pos.x), str(camp_pos.y),
		_deco_nodes(decos, frame_ids),
		str(cfg["entrance"].x), str(cfg["entrance"].y),
		str(cfg["entrance"].x), str(cfg["entrance"].y),
		str(cfg["woodland_portal"].x), str(cfg["woodland_portal"].y),
		str(cfg["dunes_portal"].x), str(cfg["dunes_portal"].y),
		str(cfg["wetlands_portal"].x), str(cfg["wetlands_portal"].y),
		str(cfg["ash_portal"].x), str(cfg["ash_portal"].y),
		labels,
	]
	var f := FileAccess.open(cfg["out"], FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print(
		"wrote ", cfg["out"],
		" walk=", cfg.get("walk_count", 0),
		" walls=", cfg.get("wall_count", 0),
		" props=", cfg.get("prop_count", 0)
	)
