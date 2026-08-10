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

var W: int = 64
var H: int = 48
var _bounds := Rect2i(0, 0, 64, 48)


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
	_set_size(112, 84)
	var ts: TileSet = load(SEWERS_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts

	var entrance_hint := Vector2i(56, 72)
	var floor_mask := _carve(
		[
			[Vector2i(56, 71), 9.0, 0.26, 11],
			[Vector2i(48, 62), 6.5, 0.30, 12],
			[Vector2i(64, 62), 6.5, 0.30, 13],
			[Vector2i(24, 50), 9.5, 0.26, 14],
			[Vector2i(88, 50), 9.5, 0.26, 15],
			[Vector2i(56, 44), 10.0, 0.24, 16],
			[Vector2i(30, 24), 9.0, 0.28, 17],
			[Vector2i(82, 24), 9.0, 0.28, 18],
			[Vector2i(56, 16), 8.0, 0.28, 19],
		],
		[
			[Vector2i(56, 64), Vector2i(56, 54), 2.6, 2.5, 31],
			[Vector2i(50, 60), Vector2i(30, 52), 2.2, 3.0, 32],
			[Vector2i(62, 60), Vector2i(82, 52), 2.2, 3.0, 33],
			[Vector2i(26, 44), Vector2i(30, 32), 2.2, 3.0, 34],
			[Vector2i(86, 44), Vector2i(82, 32), 2.2, 3.0, 35],
			[Vector2i(36, 22), Vector2i(50, 17), 2.2, 2.5, 36],
			[Vector2i(76, 22), Vector2i(62, 17), 2.2, 2.5, 37],
			[Vector2i(48, 42), Vector2i(34, 28), 2.0, 3.5, 38],
			[Vector2i(64, 42), Vector2i(78, 28), 2.0, 3.5, 39],
		],
		4,
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
	var portal := _pick_open(walk, entrance + Vector2i(0, 5))

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
		Vector2i(24, 50), Vector2i(88, 50), Vector2i(56, 44), Vector2i(30, 24),
		Vector2i(82, 24), Vector2i(56, 16), Vector2i(48, 62), Vector2i(64, 62),
		Vector2i(56, 71),
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

	assert(walk.has(entrance) and walk.has(portal), "sewers spawn blocked")
	assert(walk.size() > 900, "sewers too small: %d" % walk.size())
	print("sewers walk=", walk.size(), " floor=", floor_mask.size())

	_write_map({
		"root": "sewers",
		"out": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
		"tileset": SEWERS_TS,
		"bg": "Color(0.015, 0.025, 0.02, 1)",
		"modulate": "Color(0.72, 0.82, 0.74, 1)",
		"music": "res://assets/audio/music/fungus.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"critters": [],
		"decos": decos,
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
				str(_tile_pos(entrance + Vector2i(2, -2)).x),
				str(_tile_pos(entrance + Vector2i(2, -2)).y),
			]
		),
	})


# --- Fire Forge -------------------------------------------------------------
# Foundry halls cut into rock, walled with the DG Fire masonry ring (cols 1-4,
# rows 1-3) and pooled with lava from the 16x16 lava pack.

func _build_fire_forge() -> void:
	_set_size(112, 84)
	var ts: TileSet = load(FORGE_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts

	var entrance_hint := Vector2i(56, 72)
	var floor_mask := _carve(
		[
			[Vector2i(56, 71), 8.5, 0.26, 51],
			[Vector2i(56, 60), 7.0, 0.28, 52],
			[Vector2i(26, 52), 9.0, 0.26, 53],
			[Vector2i(86, 52), 9.0, 0.26, 54],
			[Vector2i(56, 42), 10.0, 0.24, 55],
			[Vector2i(24, 24), 9.0, 0.28, 56],
			[Vector2i(88, 24), 9.0, 0.28, 57],
			[Vector2i(56, 18), 8.5, 0.26, 58],
		],
		[
			[Vector2i(56, 64), Vector2i(56, 52), 2.8, 2.0, 61],
			[Vector2i(48, 58), Vector2i(30, 54), 2.4, 3.0, 62],
			[Vector2i(64, 58), Vector2i(82, 54), 2.4, 3.0, 63],
			[Vector2i(28, 44), Vector2i(26, 32), 2.4, 3.0, 64],
			[Vector2i(84, 44), Vector2i(86, 32), 2.4, 3.0, 65],
			[Vector2i(32, 20), Vector2i(48, 18), 2.4, 2.5, 66],
			[Vector2i(80, 20), Vector2i(64, 18), 2.4, 2.5, 67],
			[Vector2i(50, 38), Vector2i(34, 28), 2.2, 3.5, 68],
			[Vector2i(62, 38), Vector2i(78, 28), 2.2, 3.5, 69],
		],
		4,
		entrance_hint
	)

	# DG Fire's own floor bank (flat terracotta) so floor and masonry share a palette.
	var forge_floors := [
		Vector2i(5, 1), Vector2i(7, 1), Vector2i(5, 2),
		Vector2i(7, 2), Vector2i(5, 3), Vector2i(7, 3),
	]
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, 3, MapKit._pick(forge_floors, cell, 71))

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
	var portal := _pick_open(walk, entrance + Vector2i(0, 5))

	# Lava pools sunk into the foundry floors — hazards, not decoration.
	var lava_cells: Dictionary = {}
	for spot in [
		[Vector2i(24, 24), 4.0, 81], [Vector2i(88, 24), 4.0, 82],
		[Vector2i(26, 52), 3.6, 83], [Vector2i(86, 52), 3.6, 84],
		[Vector2i(56, 42), 4.4, 85],
	]:
		var pool: Dictionary = {}
		MapKit.blob(pool, spot[0], spot[1], 0.30, int(spot[2]), _bounds)
		pool = MapKit.smooth(pool, _bounds, 1, 5, 4)
		for cell: Vector2i in pool.keys():
			if walk.has(cell):
				lava_cells[cell] = true
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

	var decos: Array = []
	var ti := 0
	for spot in [
		Vector2i(24, 24), Vector2i(88, 24), Vector2i(56, 18), Vector2i(56, 42),
		Vector2i(26, 52), Vector2i(86, 52), Vector2i(56, 60), Vector2i(56, 71),
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

	assert(walk.has(entrance) and walk.has(portal), "forge spawn blocked")
	assert(walk.size() > 900, "forge too small: %d" % walk.size())
	print("forge walk=", walk.size(), " lava=", lava_cells.size())

	_write_map({
		"root": "fire_forge",
		"out": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
		"tileset": FORGE_TS,
		"bg": "Color(0.04, 0.015, 0.012, 1)",
		"modulate": "Color(0.82, 0.74, 0.72, 1)",
		"music": "res://assets/audio/music/shadow_temple.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"critters": [],
		"decos": decos,
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
				str(_tile_pos(entrance + Vector2i(2, -2)).x),
				str(_tile_pos(entrance + Vector2i(2, -2)).y),
			]
		),
	})


# --- Desert -----------------------------------------------------------------
# Open sand basin ringed by mesa cliffs, with rock outcrops standing in the
# middle. The cliff art hangs two rows below its cell, so face_rows = 2.

func _build_desert() -> void:
	_set_size(104, 76)
	var ts: TileSet = load(DESERT_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts

	var entrance_hint := Vector2i(52, 64)
	var floor_mask := _carve(
		[
			[Vector2i(52, 63), 10.0, 0.24, 101],
			[Vector2i(52, 50), 12.0, 0.22, 102],
			[Vector2i(26, 44), 10.0, 0.26, 103],
			[Vector2i(78, 44), 10.0, 0.26, 104],
			[Vector2i(52, 32), 12.0, 0.22, 105],
			[Vector2i(24, 20), 9.0, 0.28, 106],
			[Vector2i(80, 20), 9.0, 0.28, 107],
			[Vector2i(52, 16), 9.0, 0.26, 108],
		],
		[
			[Vector2i(52, 56), Vector2i(52, 44), 3.2, 2.0, 111],
			[Vector2i(40, 48), Vector2i(30, 46), 2.8, 2.5, 112],
			[Vector2i(64, 48), Vector2i(74, 46), 2.8, 2.5, 113],
			[Vector2i(28, 36), Vector2i(26, 26), 2.6, 3.0, 114],
			[Vector2i(76, 36), Vector2i(78, 26), 2.6, 3.0, 115],
			[Vector2i(32, 18), Vector2i(46, 16), 2.6, 2.5, 116],
			[Vector2i(72, 18), Vector2i(58, 16), 2.6, 2.5, 117],
		],
		4,
		entrance_hint
	)

	# Mesa outcrops standing inside the basin.
	for spot in [
		[Vector2i(38, 40), 3.4, 121], [Vector2i(66, 40), 3.4, 122],
		[Vector2i(52, 24), 3.0, 123], [Vector2i(34, 56), 2.8, 124],
		[Vector2i(70, 56), 2.8, 125], [Vector2i(52, 41), 3.2, 126],
	]:
		var mesa: Dictionary = {}
		MapKit.blob(mesa, spot[0], spot[1], 0.28, int(spot[2]), _bounds)
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
	var portal := _pick_open(walk, entrance + Vector2i(0, 5))

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
		Vector2i(30, 46), Vector2i(74, 46), Vector2i(52, 34), Vector2i(52, 58),
		Vector2i(20, 25), Vector2i(84, 25), Vector2i(20, 55), Vector2i(84, 55),
		Vector2i(40, 18), Vector2i(64, 18), Vector2i(36, 62), Vector2i(68, 62),
		Vector2i(15, 40), Vector2i(90, 40), Vector2i(48, 48), Vector2i(60, 36),
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
	for spot in [Vector2i(24, 20), Vector2i(80, 20), Vector2i(52, 16), Vector2i(52, 63)]:
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

	assert(walk.has(entrance) and walk.has(portal), "desert spawn blocked")
	assert(walk.size() > 900, "desert too small: %d" % walk.size())
	print("desert walk=", walk.size(), " floor=", floor_mask.size())

	_write_map({
		"root": "desert",
		"out": "res://source/common/gameplay/maps/maps/desert/desert.tscn",
		"tileset": DESERT_TS,
		"bg": "Color(0.09, 0.07, 0.05, 1)",
		"modulate": "Color(1, 0.97, 0.9, 1)",
		"music": "res://assets/audio/music/fungus.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"critters": critters,
		"decos": decos,
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
				str(_tile_pos(entrance + Vector2i(2, -2)).x),
				str(_tile_pos(entrance + Vector2i(2, -2)).y),
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
%s
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
id_to_node = {}
node_to_id = {}

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
		CRITTER_SCN, DECO_SCN, frame_ext,
		cfg["root"], cfg["bg"], music_line, cam_r, cam_b, cfg["modulate"],
		cfg["ground_b64"], cfg["walls_b64"], cfg["props_b64"],
		cfg.get("lights", ""), cfg.get("camps", ""), scene_nodes,
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
		" decos=", decos.size()
	)
