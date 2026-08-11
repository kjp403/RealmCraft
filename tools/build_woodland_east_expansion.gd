extends SceneTree
## Goblin Woodlands — East Expansion (contiguous outdoor wing).
##
## One authored map the player walks into from the east gate. Three terrain
## regions (dunes / wetlands / ash) share a single walkable topology with a
## woodland approach — MapKit chambers + tunnels, proper rims, props, lighting.
## Reuses desert/sewers/forge TILESETS as art only. Never edits those biome maps.
##
##   godot --headless --path . -s tools/build_woodland_east_expansion.gd

const MapKit := preload("res://tools/lib/mapkit.gd")
const ForgeFloor := preload("res://tools/lib/forgefloor.gd")

const WOOD_TS := "res://source/common/gameplay/maps/tilesets/woodland_tileset.tres"
const DESERT_TS := "res://source/common/gameplay/maps/tilesets/desert_tileset.tres"
const SEWERS_TS := "res://source/common/gameplay/maps/tilesets/sewers_tileset.tres"
const FORGE_TS := "res://source/common/gameplay/maps/tilesets/fire_forge_tileset.tres"

const WARPER := "res://source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn"
const PORTAL := "res://source/common/gameplay/maps/components/interaction_areas/warper/portal/portal.tscn"
const WOODLAND := "res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland.tres"
const CAMP := "res://source/common/gameplay/lighting/campfire.tscn"
const GLOW := "res://source/common/gameplay/lighting/light_radial.tres"
const MAP_SCRIPT := "res://source/common/gameplay/maps/map.gd"
const RP_SCRIPT := "res://source/common/network/sync/replicated_props.gd"
const DECO_SCN := "res://source/common/gameplay/props/animated_deco.tscn"
const HOSTILE_SCN := "res://source/common/gameplay/characters/npc/hostile_npc.tscn"
const TYPES := "res://source/common/gameplay/characters/npc/types/"
const OUT := "res://source/common/gameplay/maps/maps/woodland/woodland_east.tscn"
const INST_OUT := "res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland_east.tres"

## 2x surface scale — real outdoor wing, not a stub plaza.
const SURFACE_S := 2
const SURFACE_WOBBLE := 1.0

var W: int = 240
var H: int = 180
var _bounds := Rect2i(0, 0, 240, 180)


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


func _assign_biome(floor_mask: Dictionary, centers: Dictionary) -> Dictionary:
	## Nearest landmark ownership. Path corridors stay contiguous visually because
	## material changes only at soft boundaries — no walls between biomes.
	var out: Dictionary = {}
	for cell: Vector2i in floor_mask.keys():
		var best_name := "wood"
		var best_d := 1 << 30
		for biome_name: String in centers.keys():
			var c: Vector2i = centers[biome_name]
			var d: int = (cell - c).length_squared()
			# Soft bias: wood owns the western approach strip.
			if biome_name == "wood" and cell.x < _sn(34):
				d = int(float(d) * 0.55)
			if biome_name == "dunes" and cell.y < _sn(38):
				d = int(float(d) * 0.75)
			if biome_name == "wet" and cell.x > _sn(78):
				d = int(float(d) * 0.7)
			if biome_name == "ash" and cell.y > _sn(58):
				d = int(float(d) * 0.7)
			if d < best_d:
				best_d = d
				best_name = biome_name
		out[cell] = best_name
	return out


func _subset(floor_mask: Dictionary, biome_of: Dictionary, name: String) -> Dictionary:
	var out: Dictionary = {}
	for cell: Vector2i in floor_mask.keys():
		if biome_of.get(cell, "") == name:
			out[cell] = true
	return out


func _build() -> void:
	_set_size(_sn(120), _sn(90))

	var wood_ts: TileSet = load(WOOD_TS)
	var desert_ts: TileSet = load(DESERT_TS)
	var sewers_ts: TileSet = load(SEWERS_TS)
	var forge_ts: TileSet = load(FORGE_TS)

	var ground_wood := TileMapLayer.new()
	ground_wood.tile_set = wood_ts
	var walls_wood := TileMapLayer.new()
	walls_wood.tile_set = wood_ts
	var decor_wood := TileMapLayer.new()
	decor_wood.tile_set = wood_ts

	var ground_dunes := TileMapLayer.new()
	ground_dunes.tile_set = desert_ts
	var walls_dunes := TileMapLayer.new()
	walls_dunes.tile_set = desert_ts
	var props_dunes := TileMapLayer.new()
	props_dunes.tile_set = desert_ts

	var ground_wet := TileMapLayer.new()
	ground_wet.tile_set = sewers_ts
	var walls_wet := TileMapLayer.new()
	walls_wet.tile_set = sewers_ts
	var props_wet := TileMapLayer.new()
	props_wet.tile_set = sewers_ts

	var ground_ash := TileMapLayer.new()
	ground_ash.tile_set = forge_ts
	var walls_ash := TileMapLayer.new()
	walls_ash.tile_set = forge_ts
	var props_ash := TileMapLayer.new()
	props_ash.tile_set = forge_ts

	# Backdrop void (desert pit fill) so the map reads as one outdoor cliff bowl.
	var backdrop := TileMapLayer.new()
	backdrop.tile_set = desert_ts

	# --- Topology: woodland approach → crossroads → three biome lobes --------
	var entrance_hint := _sc(14, 48)
	var crossroads := _sc(48, 48)
	var dunes_heart := _sc(48, 20)
	var wet_heart := _sc(96, 46)
	var ash_heart := _sc(52, 72)
	var beach_heart := _sc(78, 80)

	var floor_mask := _carve(
		[
			# Woodland approach grove
			[entrance_hint, _sr(9.0), _sw(0.26), 301],
			[_sc(28, 48), _sr(8.0), _sw(0.28), 302],
			[_sc(36, 42), _sr(6.5), _sw(0.30), 303],
			[_sc(36, 54), _sr(6.5), _sw(0.30), 304],
			# Crossroads clearing
			[crossroads, _sr(11.0), _sw(0.22), 305],
			[_sc(56, 48), _sr(7.0), _sw(0.28), 306],
			# Dunes north
			[dunes_heart, _sr(12.0), _sw(0.24), 307],
			[_sc(28, 22), _sr(9.0), _sw(0.28), 308],
			[_sc(68, 22), _sr(9.0), _sw(0.28), 309],
			[_sc(48, 10), _sr(8.0), _sw(0.28), 310],
			[_sc(34, 32), _sr(7.0), _sw(0.30), 311],
			[_sc(62, 32), _sr(7.0), _sw(0.30), 312],
			# Wetlands east
			[wet_heart, _sr(12.0), _sw(0.24), 313],
			[_sc(82, 34), _sr(8.5), _sw(0.28), 314],
			[_sc(82, 58), _sr(8.5), _sw(0.28), 315],
			[_sc(108, 34), _sr(8.0), _sw(0.28), 316],
			[_sc(108, 58), _sr(8.0), _sw(0.28), 317],
			[_sc(100, 20), _sr(7.0), _sw(0.30), 318],
			[_sc(100, 70), _sr(7.0), _sw(0.30), 319],
			# Ash south
			[ash_heart, _sr(11.0), _sw(0.24), 320],
			[_sc(30, 72), _sr(8.5), _sw(0.28), 321],
			[_sc(74, 72), _sr(8.5), _sw(0.28), 322],
			[_sc(48, 82), _sr(8.0), _sw(0.28), 323],
			[_sc(64, 62), _sr(7.0), _sw(0.30), 324],
			# Beach apron (south-east sand shelf)
			[beach_heart, _sr(9.0), _sw(0.26), 325],
			[_sc(96, 78), _sr(7.5), _sw(0.28), 326],
		],
		[
			# Spines: west→cross→biomes
			[_sc(14, 48), _sc(48, 48), _sr(3.2), _sr(2.0), 401],
			[_sc(48, 48), _sc(48, 20), _sr(3.0), _sr(2.0), 402],
			[_sc(48, 48), _sc(96, 46), _sr(3.0), _sr(2.2), 403],
			[_sc(48, 48), _sc(52, 72), _sr(3.0), _sr(2.0), 404],
			# Dunes internal
			[_sc(48, 20), _sc(28, 22), _sr(2.6), _sr(2.5), 405],
			[_sc(48, 20), _sc(68, 22), _sr(2.6), _sr(2.5), 406],
			[_sc(48, 20), _sc(48, 10), _sr(2.4), _sr(2.0), 407],
			[_sc(34, 32), _sc(48, 48), _sr(2.2), _sr(2.5), 408],
			[_sc(62, 32), _sc(48, 48), _sr(2.2), _sr(2.5), 409],
			# Wetlands internal
			[_sc(96, 46), _sc(82, 34), _sr(2.4), _sr(2.5), 410],
			[_sc(96, 46), _sc(82, 58), _sr(2.4), _sr(2.5), 411],
			[_sc(96, 46), _sc(108, 34), _sr(2.4), _sr(2.5), 412],
			[_sc(96, 46), _sc(108, 58), _sr(2.4), _sr(2.5), 413],
			[_sc(100, 20), _sc(96, 40), _sr(2.2), _sr(2.5), 414],
			[_sc(100, 70), _sc(96, 55), _sr(2.2), _sr(2.5), 415],
			# Ash internal + beach join
			[_sc(52, 72), _sc(30, 72), _sr(2.6), _sr(2.5), 416],
			[_sc(52, 72), _sc(74, 72), _sr(2.6), _sr(2.5), 417],
			[_sc(52, 72), _sc(48, 82), _sr(2.4), _sr(2.0), 418],
			[_sc(74, 72), _sc(78, 80), _sr(2.4), _sr(2.5), 419],
			[_sc(78, 80), _sc(96, 78), _sr(2.6), _sr(2.0), 420],
			[_sc(96, 70), _sc(96, 78), _sr(2.2), _sr(2.5), 421],
		],
		_sn(4),
		entrance_hint
	)

	# Mesa islands in dunes (carve holes like east_dunes)
	for spot in [
		[_sc(38, 18), _sh(3.2), 501], [_sc(58, 16), _sh(3.0), 502],
		[_sc(48, 28), _sh(2.8), 503],
	]:
		var mesa: Dictionary = {}
		MapKit.blob(mesa, spot[0], spot[1], _sw(0.28), int(spot[2]), _bounds)
		mesa = MapKit.smooth(mesa, _bounds, 1, 5, 4)
		for cell: Vector2i in mesa.keys():
			floor_mask.erase(cell)
	floor_mask = MapKit.largest_region(floor_mask, _pick_open(floor_mask, entrance_hint))

	var centers := {
		"wood": _sc(22, 48),
		"dunes": dunes_heart,
		"wet": wet_heart,
		"ash": ash_heart,
	}
	# Beach shelf prefers ash/sand reading — pull ash ownership south-east.
	centers["ash"] = _sc(60, 76)
	var biome_of := _assign_biome(floor_mask, centers)
	# Force beach apron to ash/sand material for coastal read.
	for cell: Vector2i in floor_mask.keys():
		if cell.y >= _sn(76) and cell.x >= _sn(70):
			biome_of[cell] = "ash"

	var wood_floor := _subset(floor_mask, biome_of, "wood")
	var dunes_floor := _subset(floor_mask, biome_of, "dunes")
	var wet_floor := _subset(floor_mask, biome_of, "wet")
	var ash_floor := _subset(floor_mask, biome_of, "ash")

	# Dirt path spine for readability across biomes.
	var path: Dictionary = {}
	MapKit.tunnel(path, entrance_hint, crossroads, _sr(2.2), _sr(1.6), 521, _bounds)
	MapKit.tunnel(path, crossroads, dunes_heart, _sr(2.0), _sr(1.6), 522, _bounds)
	MapKit.tunnel(path, crossroads, wet_heart, _sr(2.0), _sr(1.8), 523, _bounds)
	MapKit.tunnel(path, crossroads, ash_heart, _sr(2.0), _sr(1.6), 524, _bounds)
	MapKit.tunnel(path, ash_heart, beach_heart, _sr(1.8), _sr(1.6), 525, _bounds)

	# --- Paint woodland -----------------------------------------------------
	var grass: Array[Vector2i] = [Vector2i(1, 10), Vector2i(2, 10), Vector2i(3, 10)]
	var dirt: Array[Vector2i] = [Vector2i(5, 7), Vector2i(6, 6), Vector2i(6, 8), Vector2i(7, 5), Vector2i(8, 6)]
	var veg: Array[Vector2i] = [Vector2i(1, 9), Vector2i(5, 9), Vector2i(7, 10), Vector2i(12, 2)]
	for cell: Vector2i in wood_floor.keys():
		var atlas: Vector2i = MapKit._pick(dirt, cell, 531) if path.has(cell) or MapKit.rand01(cell.x, cell.y, 532) < 0.28 else MapKit._pick(grass, cell, 533)
		ground_wood.set_cell(cell, 0, atlas)
		if path.has(cell):
			continue
		if MapKit.rand01(cell.x, cell.y, 534) < 0.09:
			decor_wood.set_cell(cell, 2, MapKit._pick(veg, cell, 535))
		elif MapKit.rand01(cell.x, cell.y, 536) < 0.04:
			decor_wood.set_cell(cell, 4 if MapKit.hash2(cell.x, cell.y, 537) % 2 == 0 else 5, Vector2i(0, 0))

	# --- Paint dunes --------------------------------------------------------
	var sand := [
		Vector2i(2, 1), Vector2i(3, 1), Vector2i(1, 2), Vector2i(2, 2),
		Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(3, 3),
	]
	var sand_dirt := [Vector2i(2, 2), Vector2i(3, 2), Vector2i(1, 2), Vector2i(4, 2)]
	for cell: Vector2i in dunes_floor.keys():
		if path.has(cell):
			ground_dunes.set_cell(cell, 0, MapKit._pick(sand_dirt, cell, 541))
		else:
			ground_dunes.set_cell(cell, 0, MapKit._pick(sand, cell, 542))

	# --- Paint wetlands -----------------------------------------------------
	var wet_floors := [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
	]
	for cell: Vector2i in wet_floor.keys():
		ground_wet.set_cell(cell, 0, MapKit._pick(wet_floors, cell, 551))

	# --- Paint ash (+ beach sand via forge slate / scorch) ------------------
	var ash_links: Array = [
		[_sc(48, 48), _sc(52, 72), _sr(3.0), _sr(2.0), 404],
		[_sc(52, 72), _sc(30, 72), _sr(2.6), _sr(2.5), 416],
		[_sc(52, 72), _sc(74, 72), _sr(2.6), _sr(2.5), 417],
		[_sc(52, 72), _sc(48, 82), _sr(2.4), _sr(2.0), 418],
		[_sc(74, 72), _sc(78, 80), _sr(2.4), _sr(2.5), 419],
	]
	var lava_cells: Dictionary = {}
	for spot in [
		[_sc(30, 72), _sh(3.8), 561], [_sc(74, 70), _sh(3.6), 562],
		[_sc(52, 78), _sh(4.0), 563], [_sc(42, 68), _sh(2.8), 564],
		[_sc(64, 76), _sh(3.0), 565], [_sc(58, 84), _sh(2.6), 566],
	]:
		var pool: Dictionary = {}
		MapKit.blob(pool, spot[0], spot[1], _sw(0.30), int(spot[2]), _bounds)
		pool = MapKit.smooth(pool, _bounds, 1, 5, 4)
		for cell: Vector2i in pool.keys():
			if ash_floor.has(cell) and not path.has(cell):
				lava_cells[cell] = true

	var paved: Dictionary = {}
	for link: Array in ash_links:
		MapKit.tunnel(paved, link[0], link[1], float(link[2]) * 0.45, float(link[3]), int(link[4]), _bounds)
	for bay in [ash_heart, _sc(30, 72), _sc(74, 72), beach_heart]:
		ForgeFloor.apron(paved, bay, _sn(3))
	for cell: Vector2i in lava_cells.keys():
		paved.erase(cell)
	for cell: Vector2i in ash_floor.keys():
		if not path.has(cell):
			continue
		paved[cell] = true

	var scorch := ForgeFloor.scorch_of(lava_cells, ash_floor, 3)
	var depth := ForgeFloor.depth_field(ash_floor)
	var owned: Dictionary = {}
	for spot in [_sc(52, 68), _sc(36, 72), _sc(68, 72)]:
		if ash_floor.has(_pick_open(ash_floor, spot)):
			for cell: Vector2i in ForgeFloor.hearth(ground_ash, ash_floor, _pick_open(ash_floor, spot)).keys():
				owned[cell] = true
	for cell: Vector2i in owned.keys():
		paved.erase(cell)
	for cell: Vector2i in ForgeFloor.pave(ground_ash, paved, ash_floor, depth, 72, 0.28, float(SURFACE_S)).keys():
		owned[cell] = true
	ForgeFloor.paint_slate(ground_ash, ash_floor, depth, 71, {
		"scorch": scorch, "skip": owned, "unit": float(SURFACE_S),
	})
	var lava_tiles := [Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11)]
	for cell: Vector2i in lava_cells.keys():
		ground_ash.set_cell(cell, 1, MapKit._pick(lava_tiles, cell, 571))

	# Beach shelf: override far SE ash cells with desert sand on dunes layer for coastal read.
	for cell: Vector2i in ash_floor.keys():
		if cell.y < _sn(78) or cell.x < _sn(72):
			continue
		ground_ash.erase_cell(cell)
		ground_dunes.set_cell(cell, 0, MapKit._pick(sand, cell, 575))
		biome_of[cell] = "dunes"
		dunes_floor[cell] = true
		# keep in floor_mask; remove from ash paint ownership for walls
		ash_floor.erase(cell)

	# --- Void backdrop + biome rims (walls only vs void) --------------------
	var void_mask := _void_of(floor_mask)
	for cell: Vector2i in void_mask.keys():
		backdrop.set_cell(cell, 0, Vector2i(7, 6))

	var blocked: Dictionary = {}

	# Dunes rim (cliff face)
	var dunes_void := _void_touching(void_mask, dunes_floor)
	var dunes_spec := MapKit.RimSpec.new()
	dunes_spec.source = 0
	dunes_spec.fill = [Vector2i(7, 6)]
	dunes_spec.n = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	dunes_spec.s = [Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)]
	dunes_spec.w = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	dunes_spec.e = [Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3)]
	dunes_spec.nw = Vector2i(0, 0)
	dunes_spec.ne = Vector2i(5, 0)
	dunes_spec.sw = Vector2i(0, 4)
	dunes_spec.se = Vector2i(5, 4)
	dunes_spec.s_face = [Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5)]
	dunes_spec.s_base = [Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6)]
	dunes_spec.sw_face = Vector2i(0, 5)
	dunes_spec.sw_base = Vector2i(0, 6)
	dunes_spec.se_face = Vector2i(5, 5)
	dunes_spec.se_base = Vector2i(5, 6)
	dunes_spec.face_rows = 2
	MapKit.paint_rim(walls_dunes, dunes_void, dunes_spec, _bounds, blocked)

	# Wetlands rim
	var wet_void := _void_touching(void_mask, wet_floor)
	var wet_spec := _rim(
		0,
		[Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0), Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1)],
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)],
		[Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)],
		[Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)],
		[Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3)],
		Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 4), Vector2i(5, 4)
	)
	MapKit.paint_rim(walls_wet, wet_void, wet_spec, _bounds, blocked)

	# Ash rim
	var ash_void := _void_touching(void_mask, ash_floor)
	var ash_spec := _rim(
		3,
		[Vector2i(2, 2), Vector2i(3, 2)],
		[Vector2i(2, 1), Vector2i(3, 1)],
		[Vector2i(2, 3), Vector2i(3, 3)],
		[Vector2i(1, 2)],
		[Vector2i(4, 2)],
		Vector2i(1, 1), Vector2i(4, 1), Vector2i(1, 3), Vector2i(4, 3)
	)
	MapKit.paint_rim(walls_ash, ash_void, ash_spec, _bounds, blocked)

	# Woodland soft rim (stone wall tiles)
	var wood_void := _void_touching(void_mask, wood_floor)
	var wall_tiles: Array[Vector2i] = [Vector2i(2, 6), Vector2i(3, 6), Vector2i(2, 7), Vector2i(3, 7)]
	for cell: Vector2i in wood_void.keys():
		# Only rim cells adjacent to wood floor
		var touch := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if wood_floor.has(cell + d):
				touch = true
				break
		if not touch:
			continue
		walls_wood.set_cell(cell, 1, MapKit._pick(wall_tiles, cell, 581))
		blocked[cell] = true

	# Lava blocks walk
	for cell: Vector2i in lava_cells.keys():
		blocked[cell] = true

	var walk := _walkable(floor_mask, blocked)
	var entrance := _pick_open(walk, entrance_hint)
	walk = MapKit.largest_region(walk, entrance)
	var portal := _pick_open(walk, entrance + Vector2i(_sn(3), 0))
	var camp_cell := _pick_open(walk, crossroads)

	assert(walk.has(entrance) and walk.has(portal), "spawn blocked")
	assert(walk.size() > 2500, "east expansion too small: %d" % walk.size())

	# --- Props --------------------------------------------------------------
	var keepout := _keepout([entrance, portal, camp_cell], 4)
	var solid: Dictionary = {}
	var free_dunes: Dictionary = {}
	var free_wet: Dictionary = {}
	var free_ash: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if keepout.has(cell):
			continue
		match biome_of.get(cell, ""):
			"dunes":
				free_dunes[cell] = true
			"wet":
				free_wet[cell] = true
			"ash":
				free_ash[cell] = true

	_scatter_props(props_dunes, 0, MapKit.edge_cells(dunes_floor, blocked), [[10, 7, 2, 2], [12, 7, 2, 2], [10, 1, 2, 2]], 0.10, 5, 601, free_dunes, solid)
	_scatter_flat(props_dunes, 0, MapKit.interior_cells(dunes_floor, blocked, 3), [[10, 5], [11, 5], [12, 5], [13, 5]], 0.08, 3, 602, solid)

	_scatter_props(props_wet, 0, MapKit.edge_cells(wet_floor, blocked), [[6, 4, 1, 2], [7, 4, 1, 2], [8, 4, 1, 2]], 0.12, 4, 611, free_wet, solid)
	_scatter_flat(props_wet, 0, MapKit.interior_cells(wet_floor, blocked, 3), [[9, 4], [9, 5], [7, 7], [8, 6]], 0.06, 3, 612, solid)

	for cell: Vector2i in MapKit.scatter(MapKit.edge_cells(ash_floor, blocked), 0.10, 5, 621):
		if not free_ash.has(cell) or solid.has(cell):
			continue
		props_ash.set_cell(cell, ForgeFloor.SOURCE, MapKit._pick(ForgeFloor.RUBBLE, cell, 622))
		solid[cell] = true

	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	# --- Decos / lights / mobs ---------------------------------------------
	var decos: Array = []
	var ti := 0
	for spot in [
		_sc(22, 48), _sc(48, 48), _sc(48, 20), _sc(28, 22), _sc(68, 22),
		_sc(96, 46), _sc(82, 34), _sc(108, 58), _sc(52, 72), _sc(30, 72),
		_sc(74, 72), _sc(78, 80), _sc(100, 20), _sc(36, 54),
	]:
		var cell := _pick_open(walk, spot)
		ti += 1
		var biome: String = str(biome_of.get(cell, "wood"))
		var frames := "deco_torch"
		var color := "Color(1, 0.78, 0.42, 1)"
		var light := 0.55
		var scale := 1.25
		if biome == "wet":
			frames = "deco_torch" if ti % 3 != 0 else "deco_candle_a"
			color = "Color(0.55, 0.95, 0.6, 1)" if ti % 3 == 0 else "Color(1, 0.72, 0.38, 1)"
			light = 0.85
			scale = 1.35
		elif biome == "ash":
			color = "Color(1, 0.55, 0.25, 1)"
			light = 0.7
		elif biome == "dunes":
			color = "Color(1, 0.82, 0.5, 1)"
			light = 0.5
		decos.append({
			"name": "EastTorch%d" % ti,
			"frames": frames,
			"pos": _tile_pos(cell),
			"scale": scale,
			"light": light,
			"color": color,
		})

	var taken := _keepout([entrance, portal, camp_cell], _sn(6))
	var hostiles := _mobs(walk, taken, [
		["DuneScout", "trpg/trpg_archer", _sc(48, 22), 1],
		["DuneOrc", "trpg/trpg_orc", _sc(32, 24), 1],
		["MarshSlime", "trpg/trpg_slime", _sc(96, 46), 1],
		["MarshBat", "trpg/trpg_bat", _sc(108, 50), 1],
		["AshCinder", "trpg/trpg_cinder_fomorian", _sc(52, 72), 1],
		["AshOrc", "trpg/trpg_orc", _sc(74, 74), 1],
	], _sn(5))

	# Soft landmark labels (not portals)
	var labels := [
		{"name": "LabelApproach", "text": "Goblin Woodlands East", "pos": _tile_pos(_pick_open(walk, _sc(22, 42)))},
		{"name": "LabelCrossroads", "text": "East Crossroads", "pos": _tile_pos(camp_cell) + Vector2(0, -48)},
		{"name": "LabelDunes", "text": "Sunken Dunes", "pos": _tile_pos(_pick_open(walk, _sc(48, 14)))},
		{"name": "LabelWetlands", "text": "Murkwood Marsh", "pos": _tile_pos(_pick_open(walk, _sc(96, 40)))},
		{"name": "LabelAsh", "text": "Ash Foothills", "pos": _tile_pos(_pick_open(walk, _sc(52, 66)))},
		{"name": "LabelBeach", "text": "East Shore", "pos": _tile_pos(_pick_open(walk, _sc(84, 80)))},
	]

	print(
		"woodland_east walk=", walk.size(),
		" wood=", wood_floor.size(),
		" dunes=", dunes_floor.size(),
		" wet=", wet_floor.size(),
		" ash=", ash_floor.size(),
		" lava=", lava_cells.size()
	)

	_write({
		"entrance": _tile_pos(entrance),
		"portal": _tile_pos(portal),
		"camp": _tile_pos(camp_cell),
		"decos": decos,
		"hostiles": hostiles,
		"labels": labels,
		"backdrop_b64": _b64(backdrop),
		"ground_wood_b64": _b64(ground_wood),
		"walls_wood_b64": _b64(walls_wood),
		"decor_wood_b64": _b64(decor_wood),
		"ground_dunes_b64": _b64(ground_dunes),
		"walls_dunes_b64": _b64(walls_dunes),
		"props_dunes_b64": _b64(props_dunes),
		"ground_wet_b64": _b64(ground_wet),
		"walls_wet_b64": _b64(walls_wet),
		"props_wet_b64": _b64(props_wet),
		"ground_ash_b64": _b64(ground_ash),
		"walls_ash_b64": _b64(walls_ash),
		"props_ash_b64": _b64(props_ash),
		"walk_count": walk.size(),
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
	})
	_write_instance()


func _void_touching(void_mask: Dictionary, floor_subset: Dictionary) -> Dictionary:
	## Void cells that border this biome's floor — rim paint target for that tileset.
	var out: Dictionary = {}
	for cell: Vector2i in void_mask.keys():
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			if floor_subset.has(cell + d):
				out[cell] = true
				break
	# Also include deep void near those rim cells so face_rows have room (paint_rim expects full void).
	# Use the global void but rim painter only writes adjacent-to-floor cells via neighbor tests;
	# pass full void_mask filtered to cells within 3 of this biome.
	var expanded: Dictionary = {}
	for cell: Vector2i in out.keys():
		for oy in range(-3, 4):
			for ox in range(-3, 4):
				var n := cell + Vector2i(ox, oy)
				if void_mask.has(n):
					expanded[n] = true
	return expanded if not expanded.is_empty() else out


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
			+ "theme_override_colors/font_color = Color(1, 0.92, 0.7, 1)\n"
			+ "theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)\n"
			+ "theme_override_constants/outline_size = 4\n"
			+ "theme_override_font_sizes/font_size = 15\n"
			+ "text = \"%s\"\n"
			+ "horizontal_alignment = 1\n"
		) % [
			L["name"],
			str(p.x - 70), str(p.y - 12), str(p.x + 70), str(p.y + 12),
			L["text"],
		]
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
[ext_resource type=\"TileSet\" path=\"%s\" id=\"3_desert\"]
[ext_resource type=\"TileSet\" path=\"%s\" id=\"4_sewers\"]
[ext_resource type=\"TileSet\" path=\"%s\" id=\"5_forge\"]
[ext_resource type=\"AudioStream\" path=\"res://assets/audio/music/fungus.ogg\" id=\"music\"]
[ext_resource type=\"Script\" uid=\"uid://wq8klpndipnu\" path=\"%s\" id=\"6_rp\"]
[ext_resource type=\"PackedScene\" uid=\"uid://b2ckixon7ryh6\" path=\"%s\" id=\"7_warper\"]
[ext_resource type=\"PackedScene\" uid=\"uid://0m5eq6iylq26\" path=\"%s\" id=\"8_portal\"]
[ext_resource type=\"Resource\" uid=\"uid://c0m2t2hjlih2p\" path=\"%s\" id=\"9_woodland\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"8_camp\"]
[ext_resource type=\"Texture2D\" path=\"%s\" id=\"9_glow\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"deco\"]
%s%s
[node name=\"woodland_east\" type=\"Node2D\" node_paths=PackedStringArray(\"replicated_props_container\")]
y_sort_enabled = true
script = ExtResource(\"1_map\")
replicated_props_container = NodePath(\"ReplicatedPropsContainer\")
map_background_color = Color(0.05, 0.055, 0.04, 1)
music = ExtResource(\"music\")
camera_limit_left = -16
camera_limit_top = -16
camera_limit_right = %d
camera_limit_bottom = %d
aoi_mode = 1
aoi_cell_size = Vector2i(250, 250)
aoi_visible_radius_cells = 2

[node name=\"CanvasModulate\" type=\"CanvasModulate\" parent=\".\"]
color = Color(0.92, 0.94, 0.88, 1)

[node name=\"Tiles\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true

[node name=\"Backdrop\" type=\"TileMapLayer\" parent=\"Tiles\"]
z_index = -3
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"3_desert\")

[node name=\"GroundWood\" type=\"TileMapLayer\" parent=\"Tiles\"]
z_index = -1
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"2_wood\")

[node name=\"GroundDunes\" type=\"TileMapLayer\" parent=\"Tiles\"]
z_index = -1
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"3_desert\")

[node name=\"GroundWetlands\" type=\"TileMapLayer\" parent=\"Tiles\"]
z_index = -1
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"4_sewers\")

[node name=\"GroundAsh\" type=\"TileMapLayer\" parent=\"Tiles\"]
z_index = -1
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"5_forge\")

[node name=\"WallsWood\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"2_wood\")

[node name=\"WallsDunes\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"3_desert\")

[node name=\"WallsWetlands\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"4_sewers\")

[node name=\"WallsAsh\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"5_forge\")

[node name=\"DecorWood\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"2_wood\")

[node name=\"PropsDunes\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"3_desert\")

[node name=\"PropsWetlands\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"4_sewers\")

[node name=\"PropsAsh\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"5_forge\")

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
		MAP_SCRIPT, WOOD_TS, DESERT_TS, SEWERS_TS, FORGE_TS, RP_SCRIPT, WARPER, PORTAL, WOODLAND, CAMP, GLOW,
		DECO_SCN, frame_ext, hb["ext"],
		int(cfg["cam_right"]), int(cfg["cam_bottom"]),
		cfg["backdrop_b64"],
		cfg["ground_wood_b64"], cfg["ground_dunes_b64"], cfg["ground_wet_b64"], cfg["ground_ash_b64"],
		cfg["walls_wood_b64"], cfg["walls_dunes_b64"], cfg["walls_wet_b64"], cfg["walls_ash_b64"],
		cfg["decor_wood_b64"], cfg["props_dunes_b64"], cfg["props_wet_b64"], cfg["props_ash_b64"],
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
	print(
		"wrote ", OUT,
		" walk=", cfg.get("walk_count", 0),
		" decos=", decos.size(),
		" mobs=", hostiles.size()
	)


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
