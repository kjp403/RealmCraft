extends SceneTree
## Goblin Woodlands East — contiguous outdoor wing.
## WOODLAND TILESET ONLY. No desert/sewers/forge tilesets. No stripe fills.
##
## Layout: forest approach → crossroads → northern sandy clearings (future desert),
## eastern marsh ponds (future swamp), southern rocky shelves (future volcano),
## SE beach apron. All still reads as Goblin Woodlands.
##
##   godot --headless --path . -s tools/build_woodland_east_expansion.gd

const MapKit := preload("res://tools/lib/mapkit.gd")

const WOOD_TS := "res://source/common/gameplay/maps/tilesets/woodland_tileset.tres"
const WARPER := "res://source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn"
const PORTAL := "res://source/common/gameplay/maps/components/interaction_areas/warper/portal/portal.tscn"
const WOODLAND := "res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland.tres"
const CAMP := "res://source/common/gameplay/lighting/campfire.tscn"
const MAP_SCRIPT := "res://source/common/gameplay/maps/map.gd"
const RP_SCRIPT := "res://source/common/network/sync/replicated_props.gd"
const DECO_SCN := "res://source/common/gameplay/props/animated_deco.tscn"
const HOSTILE_SCN := "res://source/common/gameplay/characters/npc/hostile_npc.tscn"
const TYPES := "res://source/common/gameplay/characters/npc/types/"
const OUT := "res://source/common/gameplay/maps/maps/woodland/woodland_east.tscn"
const INST_OUT := "res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland_east.tres"

const SRC_FLOOR := 0
const SRC_WALL := 1
const SRC_VEG := 2
const SRC_TREE_S := 3
const SRC_TREE_M := 4
const SRC_TREE_L := 5
const SRC_TREE_XL := 6
const SRC_WATER := 8

const GRASS: Array[Vector2i] = [Vector2i(1, 10), Vector2i(2, 10), Vector2i(3, 10)]
const DIRT: Array[Vector2i] = [Vector2i(5, 7), Vector2i(6, 6), Vector2i(6, 8), Vector2i(7, 5), Vector2i(8, 6)]
const SAND: Array[Vector2i] = [Vector2i(10, 7), Vector2i(11, 6), Vector2i(11, 8), Vector2i(12, 5), Vector2i(13, 6), Vector2i(14, 7)]
const STONE: Array[Vector2i] = [Vector2i(16, 1), Vector2i(16, 2), Vector2i(17, 2), Vector2i(18, 1), Vector2i(18, 3)]
const WALL: Array[Vector2i] = [Vector2i(2, 6), Vector2i(3, 6), Vector2i(2, 7), Vector2i(3, 7), Vector2i(5, 2)]
const VEG: Array[Vector2i] = [Vector2i(1, 9), Vector2i(5, 9), Vector2i(7, 10), Vector2i(12, 2), Vector2i(8, 9)]
const WATER: Array[Vector2i] = [
	Vector2i(2, 2), Vector2i(2, 5), Vector2i(1, 6), Vector2i(3, 6),
	Vector2i(0, 7), Vector2i(4, 7), Vector2i(1, 8), Vector2i(3, 8), Vector2i(2, 9),
]

const SURFACE_S := 2

var W: int = 200
var H: int = 160
var _bounds := Rect2i(0, 0, 200, 160)


func _sc(x: int, y: int) -> Vector2i:
	return Vector2i(x * SURFACE_S, y * SURFACE_S)


func _sr(v: float) -> float:
	return v * float(SURFACE_S)


func _sn(n: int) -> int:
	return n * SURFACE_S


func _sw(w: float) -> float:
	return minf(w, 0.42)


func _initialize() -> void:
	_build()
	print("WOODLAND_EAST_EXPANSION_PASS")
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
		if cell.x >= margin and cell.y >= margin + 2 and cell.x < W - margin and cell.y < H - margin:
			trimmed[cell] = true
	return MapKit.largest_region(MapKit.smooth(trimmed, _bounds, 2, 5, 4), _pick_open(trimmed, anchor))


func _keepout(spots: Array, radius: int) -> Dictionary:
	var out: Dictionary = {}
	for spot in spots:
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				out[spot + Vector2i(ox, oy)] = true
	return out


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


func _build() -> void:
	_set_size(_sn(100), _sn(80))
	var ts: TileSet = load(WOOD_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var decor := TileMapLayer.new()
	decor.tile_set = ts
	var features := TileMapLayer.new()
	features.tile_set = ts

	var entrance_hint := _sc(12, 42)
	var crossroads := _sc(40, 42)
	var north_clearing := _sc(42, 18)
	var east_marsh := _sc(78, 40)
	var south_shelf := _sc(44, 64)
	var beach := _sc(72, 70)

	# Contiguous forest wing — lobed groves, not stripes / not foreign biomes.
	var floor_mask := _carve(
		[
			[entrance_hint, _sr(10.0), _sw(0.26), 101],
			[_sc(24, 42), _sr(9.0), _sw(0.28), 102],
			[_sc(32, 36), _sr(7.5), _sw(0.30), 103],
			[_sc(32, 48), _sr(7.5), _sw(0.30), 104],
			[crossroads, _sr(12.0), _sw(0.22), 105],
			[_sc(50, 42), _sr(8.0), _sw(0.28), 106],
			# Northern sandy clearings (future desert approach — woodland sand only)
			[north_clearing, _sr(11.0), _sw(0.24), 107],
			[_sc(28, 18), _sr(8.0), _sw(0.28), 108],
			[_sc(56, 18), _sr(8.0), _sw(0.28), 109],
			[_sc(42, 8), _sr(7.0), _sw(0.30), 110],
			[_sc(34, 28), _sr(6.5), _sw(0.30), 111],
			[_sc(50, 28), _sr(6.5), _sw(0.30), 112],
			# Eastern wet woods (future swamp — woodland water ponds)
			[east_marsh, _sr(11.0), _sw(0.24), 113],
			[_sc(68, 30), _sr(8.0), _sw(0.28), 114],
			[_sc(68, 50), _sr(8.0), _sw(0.28), 115],
			[_sc(88, 30), _sr(7.5), _sw(0.28), 116],
			[_sc(88, 50), _sr(7.5), _sw(0.28), 117],
			[_sc(78, 20), _sr(6.5), _sw(0.30), 118],
			[_sc(78, 58), _sr(6.5), _sw(0.30), 119],
			# Southern rocky shelves (future volcano — woodland stone)
			[south_shelf, _sr(10.0), _sw(0.24), 120],
			[_sc(28, 64), _sr(7.5), _sw(0.28), 121],
			[_sc(60, 64), _sr(7.5), _sw(0.28), 122],
			[_sc(44, 74), _sr(7.0), _sw(0.28), 123],
			[_sc(54, 54), _sr(6.5), _sw(0.30), 124],
			# Beach apron
			[beach, _sr(8.5), _sw(0.26), 125],
			[_sc(86, 70), _sr(7.0), _sw(0.28), 126],
		],
		[
			[_sc(12, 42), _sc(40, 42), _sr(3.2), _sr(2.0), 201],
			[_sc(40, 42), _sc(42, 18), _sr(3.0), _sr(2.0), 202],
			[_sc(40, 42), _sc(78, 40), _sr(3.0), _sr(2.2), 203],
			[_sc(40, 42), _sc(44, 64), _sr(3.0), _sr(2.0), 204],
			[_sc(42, 18), _sc(28, 18), _sr(2.4), _sr(2.5), 205],
			[_sc(42, 18), _sc(56, 18), _sr(2.4), _sr(2.5), 206],
			[_sc(42, 18), _sc(42, 8), _sr(2.2), _sr(2.0), 207],
			[_sc(78, 40), _sc(68, 30), _sr(2.4), _sr(2.5), 208],
			[_sc(78, 40), _sc(68, 50), _sr(2.4), _sr(2.5), 209],
			[_sc(78, 40), _sc(88, 30), _sr(2.4), _sr(2.5), 210],
			[_sc(78, 40), _sc(88, 50), _sr(2.4), _sr(2.5), 211],
			[_sc(44, 64), _sc(28, 64), _sr(2.4), _sr(2.5), 212],
			[_sc(44, 64), _sc(60, 64), _sr(2.4), _sr(2.5), 213],
			[_sc(44, 64), _sc(44, 74), _sr(2.2), _sr(2.0), 214],
			[_sc(60, 64), _sc(72, 70), _sr(2.4), _sr(2.5), 215],
			[_sc(72, 70), _sc(86, 70), _sr(2.4), _sr(2.0), 216],
			[_sc(78, 58), _sc(72, 68), _sr(2.0), _sr(2.5), 217],
		],
		_sn(4),
		entrance_hint
	)

	# Rock outcrop islands (carve holes) for readable outdoor topography.
	for spot in [
		[_sc(36, 16), 3.4, 301], [_sc(50, 14), 3.0, 302], [_sc(42, 26), 2.8, 303],
		[_sc(70, 36), 2.6, 304], [_sc(84, 44), 2.8, 305], [_sc(36, 60), 2.8, 306],
	]:
		var mesa: Dictionary = {}
		MapKit.blob(mesa, spot[0], float(spot[1]) * float(SURFACE_S) * 0.55, _sw(0.28), int(spot[2]), _bounds)
		mesa = MapKit.smooth(mesa, _bounds, 1, 5, 4)
		for cell: Vector2i in mesa.keys():
			floor_mask.erase(cell)
	floor_mask = MapKit.largest_region(floor_mask, _pick_open(floor_mask, entrance_hint))

	# Trail spines
	var path: Dictionary = {}
	MapKit.tunnel(path, entrance_hint, crossroads, _sr(2.4), _sr(1.6), 321, _bounds)
	MapKit.tunnel(path, crossroads, north_clearing, _sr(2.1), _sr(1.6), 322, _bounds)
	MapKit.tunnel(path, crossroads, east_marsh, _sr(2.1), _sr(1.8), 323, _bounds)
	MapKit.tunnel(path, crossroads, south_shelf, _sr(2.1), _sr(1.6), 324, _bounds)
	MapKit.tunnel(path, south_shelf, beach, _sr(1.9), _sr(1.6), 325, _bounds)

	# Region masks (still woodland materials — sand/water/stone from woodland atlas)
	var sand_zone: Dictionary = {}
	var marsh_zone: Dictionary = {}
	var stone_zone: Dictionary = {}
	var beach_zone: Dictionary = {}
	for cell: Vector2i in floor_mask.keys():
		var dn: float = float((cell - north_clearing).length_squared())
		var dm: float = float((cell - east_marsh).length_squared())
		var ds: float = float((cell - south_shelf).length_squared())
		var db: float = float((cell - beach).length_squared())
		var dw: float = float((cell - entrance_hint).length_squared())
		var dc: float = float((cell - crossroads).length_squared())
		if cell.y >= _sn(68) and cell.x >= _sn(60):
			beach_zone[cell] = true
		elif dn <= dm and dn <= ds and dn < dw * 0.85 and cell.y < _sn(34):
			sand_zone[cell] = true
		elif dm <= dn and dm <= ds and cell.x > _sn(60):
			marsh_zone[cell] = true
		elif ds <= dn and ds <= dm and cell.y > _sn(54):
			stone_zone[cell] = true
		elif dc < _sr(14.0) * _sr(14.0):
			pass # crossroads stays grass/dirt

	# Ponds in marsh (water = blocked). Use real woodland water atlas cells only.
	var water_cells: Dictionary = {}
	for spot in [
		[_sc(78, 40), 5.5, 401], [_sc(70, 48), 4.6, 402], [_sc(86, 34), 4.8, 403],
		[_sc(82, 52), 4.4, 404], [_sc(74, 28), 4.0, 405], [_sc(90, 44), 3.8, 406],
		[_sc(66, 38), 3.6, 407],
	]:
		var pool: Dictionary = {}
		MapKit.blob(pool, spot[0], float(spot[1]) * float(SURFACE_S) * 0.55, _sw(0.30), int(spot[2]), _bounds)
		pool = MapKit.smooth(pool, _bounds, 1, 5, 4)
		for cell: Vector2i in pool.keys():
			if floor_mask.has(cell) and marsh_zone.has(cell) and not path.has(cell):
				water_cells[cell] = true

	# --- Paint floors -------------------------------------------------------
	for cell: Vector2i in floor_mask.keys():
		if water_cells.has(cell):
			ground.set_cell(cell, SRC_WATER, MapKit._pick(WATER, cell, 411))
			continue
		if path.has(cell):
			ground.set_cell(cell, SRC_FLOOR, MapKit._pick(DIRT, cell, 412))
			continue
		if beach_zone.has(cell):
			ground.set_cell(cell, SRC_FLOOR, MapKit._pick(SAND, cell, 413))
			continue
		if sand_zone.has(cell):
			# Open sandy glade — reads as future desert approach without foreign art
			if MapKit.rand01(cell.x, cell.y, 414) < 0.08:
				ground.set_cell(cell, SRC_FLOOR, MapKit._pick(GRASS, cell, 415))
			elif MapKit.rand01(cell.x, cell.y, 4145) < 0.12:
				ground.set_cell(cell, SRC_FLOOR, MapKit._pick(DIRT, cell, 4156))
			else:
				ground.set_cell(cell, SRC_FLOOR, MapKit._pick(SAND, cell, 416))
			continue
		if stone_zone.has(cell):
			# Rocky shelf — woodland stone dominant
			if MapKit.rand01(cell.x, cell.y, 417) < 0.18:
				ground.set_cell(cell, SRC_FLOOR, MapKit._pick(DIRT, cell, 418))
			elif MapKit.rand01(cell.x, cell.y, 419) < 0.12:
				ground.set_cell(cell, SRC_FLOOR, MapKit._pick(GRASS, cell, 420))
			else:
				ground.set_cell(cell, SRC_FLOOR, MapKit._pick(STONE, cell, 421))
			continue
		if marsh_zone.has(cell):
			# Damp woods: dirt + grass, shore around ponds
			var near_water := false
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if water_cells.has(cell + d):
					near_water = true
					break
			if near_water:
				ground.set_cell(cell, SRC_FLOOR, MapKit._pick(DIRT, cell, 422))
			elif MapKit.rand01(cell.x, cell.y, 423) < 0.4:
				ground.set_cell(cell, SRC_FLOOR, MapKit._pick(DIRT, cell, 424))
			else:
				ground.set_cell(cell, SRC_FLOOR, MapKit._pick(GRASS, cell, 425))
			continue
		# Default forest floor
		if MapKit.rand01(cell.x, cell.y, 426) < 0.18:
			ground.set_cell(cell, SRC_FLOOR, MapKit._pick(DIRT, cell, 427))
		else:
			ground.set_cell(cell, SRC_FLOOR, MapKit._pick(GRASS, cell, 428))

	# --- Rim walls (void against cliff) -------------------------------------
	var blocked: Dictionary = {}
	for cell: Vector2i in water_cells.keys():
		blocked[cell] = true

	for y in H:
		for x in W:
			var cell := Vector2i(x, y)
			if floor_mask.has(cell):
				continue
			var touch := false
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if floor_mask.has(cell + d):
					touch = true
					break
			if not touch:
				continue
			walls.set_cell(cell, SRC_WALL, MapKit._pick(WALL, cell, 431))
			blocked[cell] = true
			# Soft second rim for cliff read
			for d2 in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = cell + d2
				if floor_mask.has(n) or walls.get_cell_source_id(n) >= 0:
					continue
				if not _bounds.has_point(n):
					continue
				if MapKit.rand01(n.x, n.y, 432) < 0.55:
					walls.set_cell(n, SRC_WALL, MapKit._pick(WALL, n, 433))

	var walk: Dictionary = {}
	for cell: Vector2i in floor_mask.keys():
		if not blocked.has(cell):
			walk[cell] = true
	var entrance := _pick_open(walk, entrance_hint)
	walk = MapKit.largest_region(walk, entrance)
	var portal := _pick_open(walk, entrance + Vector2i(_sn(3), 0))
	var camp_cell := _pick_open(walk, crossroads)

	assert(walk.has(entrance) and walk.has(portal), "spawn blocked")
	assert(walk.size() > 2000, "east wing too small: %d" % walk.size())

	# --- Decor: trees, veg (forest density) ---------------------------------
	var keepout := _keepout([entrance, portal, camp_cell], 5)
	var solid: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if keepout.has(cell) or path.has(cell) or water_cells.has(cell):
			continue
		# Clearings stay more open
		var in_clearing := sand_zone.has(cell) or stone_zone.has(cell) or beach_zone.has(cell)
		var tree_chance := 0.02 if in_clearing else 0.12
		var veg_chance := 0.05 if in_clearing else 0.10
		if sand_zone.has(cell) or beach_zone.has(cell):
			tree_chance = 0.012
			veg_chance = 0.04
		if marsh_zone.has(cell):
			tree_chance = 0.09
			veg_chance = 0.15
		if stone_zone.has(cell):
			tree_chance = 0.03
			veg_chance = 0.06
		if MapKit.rand01(cell.x, cell.y, 441) < tree_chance:
			var roll := MapKit.rand01(cell.x, cell.y, 442)
			var src := SRC_TREE_M
			if roll < 0.15:
				src = SRC_TREE_S
			elif roll < 0.55:
				src = SRC_TREE_M
			elif roll < 0.85:
				src = SRC_TREE_L
			else:
				src = SRC_TREE_XL
			decor.set_cell(cell, src, Vector2i(0, 0))
			solid[cell] = true
			walk.erase(cell)
		elif MapKit.rand01(cell.x, cell.y, 443) < veg_chance:
			features.set_cell(cell, SRC_VEG, MapKit._pick(VEG, cell, 444))

	walk = MapKit.largest_region(walk, entrance)
	assert(walk.has(entrance) and walk.has(portal), "trees blocked spawn")

	# --- Decos / lights / mobs / labels -------------------------------------
	var decos: Array = []
	var ti := 0
	for spot in [
		_sc(12, 42), _sc(40, 42), _sc(42, 18), _sc(28, 18), _sc(56, 18),
		_sc(78, 40), _sc(68, 30), _sc(88, 50), _sc(44, 64), _sc(28, 64),
		_sc(60, 64), _sc(72, 70), _sc(50, 42), _sc(34, 48),
	]:
		var cell := _pick_open(walk, spot)
		ti += 1
		decos.append({
			"name": "ForestTorch%d" % ti,
			"frames": "deco_torch",
			"pos": _tile_pos(cell),
			"scale": 1.2,
			"light": 0.55,
			"color": "Color(1, 0.78, 0.42, 1)",
		})

	var taken := _keepout([entrance, portal, camp_cell], _sn(6))
	var hostiles := _mobs(walk, taken, [
		["EastGoblin", "trpg/trpg_orc", _sc(42, 20), 1],
		["EastArcher", "trpg/trpg_archer", _sc(34, 28), 1],
		["MarshSlime", "trpg/trpg_slime", _sc(78, 42), 1],
		["MarshBat", "trpg/trpg_bat", _sc(86, 48), 1],
		["ShelfOrc", "trpg/trpg_armored_orc", _sc(44, 64), 1],
		["BeachScout", "trpg/trpg_archer", _sc(72, 70), 1],
	], _sn(5))

	var labels := [
		{"name": "LabelApproach", "text": "Goblin Woodlands East", "pos": _tile_pos(_pick_open(walk, _sc(18, 36)))},
		{"name": "LabelCrossroads", "text": "East Crossroads", "pos": _tile_pos(camp_cell) + Vector2(0, -40)},
		{"name": "LabelSand", "text": "Sunlit Clearings", "pos": _tile_pos(_pick_open(walk, _sc(42, 12)))},
		{"name": "LabelMarsh", "text": "Murkwood Ponds", "pos": _tile_pos(_pick_open(walk, _sc(78, 34)))},
		{"name": "LabelShelf", "text": "Stone Shelves", "pos": _tile_pos(_pick_open(walk, _sc(44, 60)))},
		{"name": "LabelBeach", "text": "East Shore", "pos": _tile_pos(_pick_open(walk, _sc(76, 70)))},
	]

	print(
		"woodland_east walk=", walk.size(),
		" sand=", sand_zone.size(),
		" marsh=", marsh_zone.size(),
		" stone=", stone_zone.size(),
		" beach=", beach_zone.size(),
		" water=", water_cells.size(),
		" trees=", decor.get_used_cells().size()
	)

	_write({
		"entrance": _tile_pos(entrance),
		"portal": _tile_pos(portal),
		"camp": _tile_pos(camp_cell),
		"decos": decos,
		"hostiles": hostiles,
		"labels": labels,
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"decor_b64": _b64(decor),
		"features_b64": _b64(features),
		"walk_count": walk.size(),
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
	})
	_write_instance()


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
		hostile_ext += "[ext_resource type=\"PackedScene\" uid=\"uid://v32667qwpj2l\" path=\"%s\" id=\"hostile\"]\n" % HOSTILE_SCN
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
	return {"ext": hostile_ext, "nodes": hostile_nodes, "id_map": id_map_lines}


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


func _label_nodes(labels: Array) -> String:
	var out := ""
	for L in labels:
		var p: Vector2 = L["pos"]
		out += (
			"\n[node name=\"%s\" type=\"Label\" parent=\".\"]\n"
			+ "offset_left = %s\n"
			+ "offset_top = %s\n"
			+ "offset_right = %s\n"
			+ "offset_bottom = %s\n"
			+ "theme_override_colors/font_color = Color(0.9, 0.95, 0.7, 1)\n"
			+ "theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)\n"
			+ "theme_override_constants/outline_size = 4\n"
			+ "theme_override_font_sizes/font_size = 15\n"
			+ "text = \"%s\"\n"
			+ "horizontal_alignment = 1\n"
		) % [L["name"], str(p.x - 80), str(p.y - 12), str(p.x + 80), str(p.y + 12), L["text"]]
	return out


func _write(cfg: Dictionary) -> void:
	var decos: Array = cfg.get("decos", [])
	var hostiles: Array = cfg.get("hostiles", [])
	var frames := _frame_ext(decos)
	var frame_ext: String = frames[0]
	var frame_ids: Dictionary = frames[1]
	var hb := _hostile_bits(hostiles)
	var camps := (
		"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
		+ "position = Vector2(%s, %s)\n" % [str(cfg["camp"].x), str(cfg["camp"].y)]
	)
	var text := """[gd_scene format=3]

[ext_resource type=\"Script\" uid=\"uid://7mbux4mybta0\" path=\"%s\" id=\"1_map\"]
[ext_resource type=\"TileSet\" path=\"%s\" id=\"2_wood\"]
[ext_resource type=\"AudioStream\" path=\"res://assets/audio/music/lost_woods.ogg\" id=\"music\"]
[ext_resource type=\"Script\" uid=\"uid://wq8klpndipnu\" path=\"%s\" id=\"6_rp\"]
[ext_resource type=\"PackedScene\" uid=\"uid://b2ckixon7ryh6\" path=\"%s\" id=\"7_warper\"]
[ext_resource type=\"PackedScene\" uid=\"uid://0m5eq6iylq26\" path=\"%s\" id=\"8_portal\"]
[ext_resource type=\"Resource\" uid=\"uid://c0m2t2hjlih2p\" path=\"%s\" id=\"9_woodland\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"8_camp\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"deco\"]
%s%s
[node name=\"woodland_east\" type=\"Node2D\" node_paths=PackedStringArray(\"replicated_props_container\")]
y_sort_enabled = true
script = ExtResource(\"1_map\")
replicated_props_container = NodePath(\"ReplicatedPropsContainer\")
map_background_color = Color(0.06, 0.07, 0.05, 1)
music = ExtResource(\"music\")
camera_limit_left = -16
camera_limit_top = -16
camera_limit_right = %d
camera_limit_bottom = %d
aoi_mode = 1
aoi_cell_size = Vector2i(250, 250)
aoi_visible_radius_cells = 2

[node name=\"CanvasModulate\" type=\"CanvasModulate\" parent=\".\"]
color = Color(0.95, 0.97, 0.9, 1)

[node name=\"Tiles\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true

[node name=\"Ground\" type=\"TileMapLayer\" parent=\"Tiles\"]
z_index = -1
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"2_wood\")

[node name=\"Walls\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"2_wood\")

[node name=\"Decor\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"2_wood\")

[node name=\"Features\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"2_wood\")

[node name=\"SceneProps\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true
%s%s
[node name=\"ReplicatedPropsContainer\" type=\"Node2D\" parent=\".\" node_paths=PackedStringArray(\"id_to_node\", \"node_to_id\")]
y_sort_enabled = true
script = ExtResource(\"6_rp\")
%s%s
[node name=\"RespawnPoint\" parent=\".\" instance=ExtResource(\"7_warper\")]
position = Vector2(%s, %s)

[node name=\"Entrance\" parent=\".\" instance=ExtResource(\"7_warper\")]
position = Vector2(%s, %s)
warper_id = 60

[node name=\"WoodlandPortal\" parent=\".\" instance=ExtResource(\"8_portal\")]
position = Vector2(%s, %s)
portal_color = Color(0.45, 0.7, 0.35, 1)
destination_label = \"Goblin Woodland\"
target_instance = ExtResource(\"9_woodland\")
warper_id = 160
target_id = 60
%s
""" % [
		MAP_SCRIPT, WOOD_TS, RP_SCRIPT, WARPER, PORTAL, WOODLAND, CAMP, DECO_SCN,
		frame_ext, hb["ext"],
		int(cfg["cam_right"]), int(cfg["cam_bottom"]),
		cfg["ground_b64"], cfg["walls_b64"], cfg["decor_b64"], cfg["features_b64"],
		camps, _deco_nodes(decos, frame_ids),
		hb["id_map"], hb["nodes"],
		str(cfg["entrance"].x), str(cfg["entrance"].y),
		str(cfg["entrance"].x), str(cfg["entrance"].y),
		str(cfg["portal"].x), str(cfg["portal"].y),
		_label_nodes(cfg.get("labels", [])),
	]
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", OUT, " walk=", cfg.get("walk_count", 0), " decos=", decos.size(), " mobs=", hostiles.size())


func _write_instance() -> void:
	var text := """[gd_resource type=\"Resource\" script_class=\"InstanceResource\" format=3]

[ext_resource type=\"Script\" uid=\"uid://deqjrbn7hm53u\" path=\"res://source/common/gameplay/maps/instance/instance_resource.gd\" id=\"1_script\"]
[ext_resource type=\"Resource\" uid=\"uid://c0m2t2hjlih2p\" path=\"res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland.tres\" id=\"2_woodland\"]

[resource]
script = ExtResource(\"1_script\")
instance_name = &\"woodland_east\"
map_path = \"res://source/common/gameplay/maps/maps/woodland/woodland_east.tscn\"
zone_title = \"Goblin Woodlands East\"
level_min = 5
level_max = 15
show_discovery = true
death_return_instance = ExtResource(\"2_woodland\")
death_return_warper_id = 60
metadata/_custom_type_script = \"uid://deqjrbn7hm53u\"
"""
	var f := FileAccess.open(INST_OUT, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", INST_OUT)
