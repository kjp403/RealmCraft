extends SceneTree
## Rebuild the Mining Cave from the RPG Worlds Caves pack (32×32).
##
## Nothing here stamps a rectangle of atlas cells. Caverns are organic masks,
## the chasm rim resolves per-cell from its neighbours, ground patches are
## painted with Godot terrain autotiling, and detail is blue-noise scattered.
##
##   godot --headless --path . --import
##   godot --headless --path . -s tools/build_rpgw_cave_tileset.gd
##   godot --headless --path . -s tools/build_mining_cave.gd

const MapKit := preload("res://tools/lib/mapkit.gd")

const TILESET := "res://source/common/gameplay/maps/tilesets/rpgw_caves_tileset.tres"
const OUT_TSCN := "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"

const W := 64
const H := 46
const TILE := 32

## The ground bank is one large gradient block, not a set of interchangeable
## variants: every tile outside its flat middle carries directional shading that
## tiles up as square wedges. Only the flat cells are safe to repeat, and floor
## interest comes from the scattered props instead.
const GROUND_PLAIN: Array[Vector2i] = [
	Vector2i(32, 28), Vector2i(33, 28), Vector2i(32, 29), Vector2i(33, 29),
]
## Solid dark rock, laid under every void cell as a backing for the rim art.
const VOID_FILL := Vector2i(4, 3)

## Bridge pieces (see MainLev2.0 rows 32–37).
const BRIDGE_DECK: Array[Vector2i] = [
	Vector2i(45, 32), Vector2i(46, 32), Vector2i(47, 32), Vector2i(48, 32), Vector2i(49, 32),
]
const BRIDGE_UNDER: Array[Vector2i] = [
	Vector2i(45, 33), Vector2i(46, 33), Vector2i(47, 33), Vector2i(48, 33), Vector2i(49, 33),
]

## Regions of decorative.png. Actual props are discovered as connected clusters
## inside these bands, so a formation is never sliced apart.
## Props verified against the sheet as complete, self-contained rectangles.
## Rows 8–15 hold near-black silhouette variants that stamp as black boxes on a
## lit floor, so only the lit bank (rows 1–7) is used.
## Format: x, y, width, height.
const SMALL_ROCKS := [[11, 3, 1, 1], [0, 7, 1, 1]]
const MED_ROCKS := [[9, 2, 2, 2], [5, 2, 2, 2], [7, 2, 2, 2]]
const BIG_ROCKS := [[0, 1, 3, 3], [3, 1, 2, 3]]
const CRYSTALS := [[0, 18], [3, 18], [0, 20], [3, 20], [5, 18], [8, 18], [5, 20], [8, 20]]
const FLOOR_SPECKS := [[1, 25], [3, 25], [5, 25], [1, 28], [3, 28], [5, 28]]

var _bounds := Rect2i(0, 0, W, H)


func _initialize() -> void:
	var ts: TileSet = load(TILESET)
	assert(ts != null, "missing rpgw tileset — run build_rpgw_cave_tileset.gd first")

	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var detail := TileMapLayer.new()
	detail.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts

	var floor_mask := _carve_caverns()
	var void_mask: Dictionary = {}
	for y in H:
		for x in W:
			var cell := Vector2i(x, y)
			if not floor_mask.has(cell):
				void_mask[cell] = true

	_paint_ground(ground, floor_mask)
	# Rim corner tiles are only ~70% opaque — they expect solid rock behind them.
	# Without this underlay their transparent corners punch through to the
	# background and read as flat grey squares.
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 0, VOID_FILL)

	var spec := _rim_spec()
	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, spec, _bounds, blocked)

	# Walkable is the floor minus whatever the cliff face covers.
	var walk: Dictionary = {}
	for cell: Vector2i in floor_mask.keys():
		if not blocked.has(cell):
			walk[cell] = true

	var bridges := _build_bridges(props, walls, walk, void_mask)

	var entrance := _pick_open(walk, Vector2i(11, 37))
	walk = MapKit.largest_region(walk, entrance)
	var portal := _pick_open(walk, entrance + Vector2i(-3, 2))

	# Patches are painted across the whole floor, including the strip the cliff
	# face covers, so a seam never stops dead against a wall.
	_paint_ground_patches(detail, floor_mask, walk)

	var keepout: Dictionary = {}
	for spot in [entrance, portal, entrance + Vector2i(2, -1)]:
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				keepout[spot + Vector2i(ox, oy)] = true
	var solid_props := _paint_detail(props, walk, blocked, keepout)
	for cell: Vector2i in solid_props.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	var ores := _place_ores(walk, blocked)
	var lights := _light_positions(walk)

	_verify(walk, entrance, portal, bridges)

	_write_tscn(
		MapKit.to_base64(ground),
		MapKit.to_base64(detail),
		MapKit.to_base64(walls),
		MapKit.to_base64(props),
		ores,
		lights,
		entrance,
		portal
	)
	print(
		"OK mining_cave floor=", floor_mask.size(),
		" walk=", walk.size(),
		" void=", void_mask.size(),
		" ground=", ground.get_used_cells().size(),
		" detail=", detail.get_used_cells().size(),
		" walls=", walls.get_used_cells().size(),
		" props=", props.get_used_cells().size(),
		" ores=", ores.size(),
		" bridges=", bridges.size()
	)
	quit(0)


# --- Shape ------------------------------------------------------------------

func _carve_caverns() -> Dictionary:
	var mask: Dictionary = {}
	# Chambers: wide irregular caverns rather than discs, each with a satellite
	# lobe so the silhouette is never a clean circle.
	var chambers := [
		{"c": Vector2i(12, 36), "r": 8.0, "w": 0.30, "s": 11},   # entrance hall
		{"c": Vector2i(17, 31), "r": 5.5, "w": 0.34, "s": 12},
		{"c": Vector2i(12, 22), "r": 7.5, "w": 0.32, "s": 13},   # west gallery
		{"c": Vector2i(18, 17), "r": 5.0, "w": 0.36, "s": 14},
		{"c": Vector2i(28, 12), "r": 8.0, "w": 0.30, "s": 15},   # north hall
		{"c": Vector2i(35, 16), "r": 5.5, "w": 0.34, "s": 16},
		{"c": Vector2i(33, 27), "r": 8.5, "w": 0.28, "s": 17},   # central junction
		{"c": Vector2i(27, 33), "r": 5.5, "w": 0.34, "s": 18},
		{"c": Vector2i(48, 13), "r": 7.5, "w": 0.30, "s": 19},   # north-east hall
		{"c": Vector2i(54, 20), "r": 6.0, "w": 0.33, "s": 20},
		{"c": Vector2i(52, 30), "r": 8.0, "w": 0.30, "s": 21},   # east gallery
		{"c": Vector2i(44, 37), "r": 7.0, "w": 0.31, "s": 22},   # south-east hall
	]
	for ch in chambers:
		MapKit.blob(mask, ch["c"], ch["r"], ch["w"], int(ch["s"]), _bounds)

	# Haulage tunnels — wandering, not L-pipes.
	var links := [
		[Vector2i(12, 32), Vector2i(12, 26), 2.2, 2.5, 31],
		[Vector2i(15, 20), Vector2i(24, 13), 2.0, 3.0, 32],
		[Vector2i(31, 15), Vector2i(33, 22), 2.4, 2.5, 33],
		[Vector2i(17, 34), Vector2i(26, 33), 2.2, 2.5, 34],
		[Vector2i(29, 31), Vector2i(38, 36), 2.2, 3.0, 35],
		[Vector2i(38, 14), Vector2i(44, 13), 2.2, 2.5, 36],
		[Vector2i(52, 24), Vector2i(52, 26), 2.6, 1.5, 37],
		[Vector2i(48, 36), Vector2i(50, 33), 2.4, 2.0, 38],
		[Vector2i(38, 27), Vector2i(46, 29), 2.4, 3.0, 39],
	]
	for link in links:
		MapKit.tunnel(mask, link[0], link[1], link[2], link[3], int(link[4]), _bounds)

	# Keep a solid rock margin so the cavern never touches the map border.
	var trimmed: Dictionary = {}
	for cell: Vector2i in mask.keys():
		if cell.x >= 3 and cell.y >= 4 and cell.x < W - 3 and cell.y < H - 3:
			trimmed[cell] = true
	# Smooth away single-cell spikes; rims read as continuous rock afterwards.
	var smoothed := MapKit.smooth(trimmed, _bounds, 2, 5, 4)
	return MapKit.largest_region(smoothed, _pick_open(smoothed, Vector2i(12, 36)))


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


# --- Painting ---------------------------------------------------------------

func _rim_spec() -> MapKit.RimSpec:
	var spec := MapKit.RimSpec.new()
	spec.source = 0
	# One dark interior tile: the fill covers huge areas and any variation in it
	# tiles up as a visible checker.
	spec.fill = [Vector2i(4, 3)]
	spec.n = [Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)]
	spec.s = [Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6)]
	spec.w = [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5)]
	spec.e = [Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5)]
	spec.nw = Vector2i(2, 0)
	spec.ne = Vector2i(7, 0)
	spec.sw = Vector2i(2, 6)
	spec.se = Vector2i(7, 6)
	spec.s_face = [Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7)]
	spec.s_base = [Vector2i(3, 8), Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8)]
	spec.sw_face = Vector2i(2, 7)
	spec.sw_base = Vector2i(2, 8)
	spec.se_face = Vector2i(7, 7)
	spec.se_base = Vector2i(7, 8)
	spec.face_rows = 2
	return spec


func _paint_ground(ground: TileMapLayer, floor_mask: Dictionary) -> void:
	for cell: Vector2i in floor_mask.keys():
		ground.set_cell(cell, 0, MapKit._pick(GROUND_PLAIN, cell, 41))


## Soft mineral seams. The builder only says *where*; the blend tile for every
## cell is resolved from its four corners against a table read off the artwork.
func _paint_ground_patches(detail: TileMapLayer, floor_mask: Dictionary, _walk: Dictionary) -> void:
	var atlas := (load(TILESET) as TileSet).get_source(0) as TileSetAtlasSource
	var tex: Texture2D = atlas.texture
	var lookups := {
		1: MapKit.corner_lookup(tex, 32, Rect2i(10, 31, 5, 9), Color8(61, 68, 45)),
		2: MapKit.corner_lookup(tex, 32, Rect2i(25, 31, 5, 9), Color8(53, 57, 58)),
		3: MapKit.corner_lookup(tex, 32, Rect2i(40, 31, 5, 9), Color8(77, 59, 48)),
	}
	var patches := [
		{"terrain": 3, "c": Vector2i(12, 36), "r": 5.5, "s": 61},
		{"terrain": 3, "c": Vector2i(33, 27), "r": 6.0, "s": 62},
		{"terrain": 3, "c": Vector2i(48, 14), "r": 4.5, "s": 63},
		{"terrain": 2, "c": Vector2i(28, 12), "r": 5.5, "s": 64},
		{"terrain": 2, "c": Vector2i(52, 30), "r": 5.0, "s": 65},
		{"terrain": 2, "c": Vector2i(13, 22), "r": 4.5, "s": 66},
		{"terrain": 1, "c": Vector2i(44, 37), "r": 4.5, "s": 67},
		{"terrain": 1, "c": Vector2i(17, 31), "r": 3.5, "s": 68},
		{"terrain": 1, "c": Vector2i(54, 21), "r": 3.5, "s": 69},
	]
	for patch in patches:
		var blob_mask: Dictionary = {}
		MapKit.blob(blob_mask, patch["c"], patch["r"], 0.22, int(patch["s"]), _bounds)
		# Smooth before painting: a ragged 1-cell edge makes the autotiled border
		# read as a starburst instead of a mineral seam.
		blob_mask = MapKit.smooth(blob_mask, _bounds, 2, 5, 4)
		var cells: Dictionary = {}
		for cell: Vector2i in blob_mask.keys():
			if floor_mask.has(cell):
				cells[cell] = true
		if cells.size() < 6:
			continue
		MapKit.paint_corner_patch(
			detail, 0, lookups[int(patch["terrain"])], cells, _bounds, int(patch["s"]), floor_mask
		)


## Detail is deliberately sparse: the reference shots keep large clear floors and
## concentrate silhouettes against the rock. Returns the cells that now block.
func _paint_detail(
	props: TileMapLayer,
	walk: Dictionary,
	blocked: Dictionary,
	keepout: Dictionary
) -> Dictionary:
	var boulders: Array = []
	for r in SMALL_ROCKS:
		boulders.append(MapKit.rect_cluster(r[0], r[1], r[2], r[3]))
	var formations: Array = []
	for r in MED_ROCKS + BIG_ROCKS:
		formations.append(MapKit.rect_cluster(r[0], r[1], r[2], r[3]))
	var small_crystals: Array = []
	for r in CRYSTALS:
		small_crystals.append(MapKit.rect_cluster(r[0], r[1], 1, 1))
	var specks: Array = []
	for r in FLOOR_SPECKS:
		specks.append(MapKit.rect_cluster(r[0], r[1], 1, 1))

	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)
	var solid: Dictionary = {}

	# A blocking prop may only stand where the floor is wide enough that losing
	# the cell cannot plug a tunnel.
	var roomy := func(cell: Vector2i) -> bool:
		if keepout.has(cell):
			return false
		var n: int = 0
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if walk.has(cell + Vector2i(ox, oy)):
					n += 1
		return n >= 6

	# Big rock formations as landmarks, stamped whole.
	if not formations.is_empty():
		var free: Dictionary = {}
		for cell: Vector2i in inner:
			if not keepout.has(cell):
				free[cell] = true
		var anchors := MapKit.scatter(inner, 0.5, 6, 70, roomy)
		var used: int = 0
		for anchor: Vector2i in anchors:
			if used >= 7:
				break
			var cluster: Dictionary = formations[MapKit.hash2(anchor.x, anchor.y, 69) % formations.size()]
			var placed := MapKit.stamp_cluster(props, 1, cluster, anchor, free, _bounds)
			if placed.is_empty():
				continue
			for cell: Vector2i in placed:
				solid[cell] = true
				free.erase(cell)
			used += 1

	# Single boulders and stalagmites hug the rock walls, as in the references.
	if not boulders.is_empty():
		var wall_free: Dictionary = {}
		for cell: Vector2i in walk.keys():
			if not solid.has(cell) and not keepout.has(cell):
				wall_free[cell] = true
		for cell in MapKit.scatter(edges, 0.24, 3, 71, roomy):
			if solid.has(cell):
				continue
			var cluster: Dictionary = boulders[MapKit.hash2(cell.x, cell.y, 72) % boulders.size()]
			var placed := MapKit.stamp_cluster(props, 1, cluster, cell, wall_free, _bounds)
			for c2: Vector2i in placed:
				solid[c2] = true
				wall_free.erase(c2)

	# Crystal seams: a few clusters rather than an even sprinkle.
	var seams := [Vector2i(28, 12), Vector2i(52, 30), Vector2i(12, 22), Vector2i(48, 13)]
	if not small_crystals.is_empty():
		var open_cells: Dictionary = {}
		for cell: Vector2i in walk.keys():
			if props.get_cell_source_id(cell) < 0 and not keepout.has(cell):
				open_cells[cell] = true
		for i in seams.size():
			var seam: Vector2i = seams[i]
			var near: Array[Vector2i] = []
			for cell: Vector2i in edges:
				if (cell - seam).length_squared() <= 36 and open_cells.has(cell):
					near.append(cell)
			for cell in MapKit.scatter(near, 0.30, 2, 80 + i):
				var cluster: Dictionary = small_crystals[MapKit.hash2(cell.x, cell.y, 81 + i) % small_crystals.size()]
				var placed := MapKit.stamp_cluster(props, 1, cluster, cell, open_cells, _bounds)
				for c2: Vector2i in placed:
					open_cells.erase(c2)

	# Lichen and pebbles: flat, non-blocking floor detail.
	if not specks.is_empty():
		for cell in MapKit.scatter(inner, 0.13, 2, 91):
			if props.get_cell_source_id(cell) >= 0 or keepout.has(cell):
				continue
			var cluster: Dictionary = specks[MapKit.hash2(cell.x, cell.y, 92) % specks.size()]
			props.set_cell(cell, 1, cluster["origin"])
	return solid


## Span the chasms that split the cavern. Each bridge reopens a run of void
## cells, so the crossing is real geometry rather than decoration.
func _build_bridges(
	props: TileMapLayer,
	walls: TileMapLayer,
	walk: Dictionary,
	void_mask: Dictionary
) -> Array:
	var built: Array = []
	var candidates := [
		{"y": 22, "x0": 18, "x1": 30},
		{"y": 31, "x0": 36, "x1": 48},
		{"y": 17, "x0": 38, "x1": 46},
	]
	for cand in candidates:
		var y: int = int(cand["y"])
		var span: Array[Vector2i] = []
		var ok: bool = true
		for x in range(int(cand["x0"]), int(cand["x1"]) + 1):
			var cell := Vector2i(x, y)
			if not void_mask.has(cell):
				continue
			span.append(cell)
		if span.size() < 3 or span.size() > 14:
			continue
		# Both ends must land on walkable ground or the bridge leads nowhere.
		var left_anchor := Vector2i(span[0].x - 1, y)
		var right_anchor := Vector2i(span[span.size() - 1].x + 1, y)
		if not walk.has(left_anchor) or not walk.has(right_anchor):
			ok = false
		if not ok:
			continue
		for cell: Vector2i in span:
			walls.erase_cell(cell)
			props.set_cell(cell, 0, MapKit._pick(BRIDGE_DECK, cell, 101))
			walk[cell] = true
			var under := cell + Vector2i(0, 1)
			if void_mask.has(under) and _bounds.has_point(under):
				props.set_cell(under, 0, MapKit._pick(BRIDGE_UNDER, cell, 102))
		built.append({"y": y, "x0": span[0].x, "x1": span[span.size() - 1].x})
	return built


# --- Content ----------------------------------------------------------------

func _place_ores(walk: Dictionary, blocked: Dictionary) -> Array:
	# Copper/tin stay in the Starting Area — Mining Cave focuses on mid+ ores.
	# East cluster (~tile 48,13 ≈ world 1550,430) is the Mining-50 deep vault:
	# adamant + runite only. Iron 2x, coal 5x vs original counts, plus mithril.
	var edges := MapKit.edge_cells(walk, blocked)
	var zones := [
		{"kind": "iron", "c": Vector2i(33, 27), "r": 11, "n": 12},
		{"kind": "iron", "c": Vector2i(52, 30), "r": 10, "n": 8},
		{"kind": "coal", "c": Vector2i(28, 12), "r": 10, "n": 15},
		{"kind": "coal", "c": Vector2i(20, 28), "r": 9, "n": 15},
		{"kind": "coal", "c": Vector2i(40, 34), "r": 9, "n": 15},
		{"kind": "mithril", "c": Vector2i(36, 18), "r": 8, "n": 3},
		{"kind": "mithril", "c": Vector2i(44, 28), "r": 8, "n": 2},
		{"kind": "adamant", "c": Vector2i(48, 13), "r": 7, "n": 4},
		{"kind": "runite", "c": Vector2i(50, 11), "r": 6, "n": 2},
	]
	var used: Dictionary = {}
	var out: Array = []
	for zone in zones:
		var center: Vector2i = zone["c"]
		var r2: int = int(zone["r"]) * int(zone["r"])
		var near: Array[Vector2i] = []
		for cell: Vector2i in edges:
			if (cell - center).length_squared() <= r2 and not used.has(cell):
				near.append(cell)
		var picked := MapKit.scatter(near, 0.9, 2, 111 + out.size())
		var count: int = 0
		for cell: Vector2i in picked:
			if count >= int(zone["n"]):
				break
			used[cell] = true
			out.append({"kind": String(zone["kind"]), "pos": _tile_pos(cell)})
			count += 1
	return out


func _light_positions(walk: Dictionary) -> Array:
	var spots := [
		{"c": Vector2i(12, 36), "color": "Color(1, 0.76, 0.46, 1)", "energy": 1.25, "scale": 3.0},
		{"c": Vector2i(12, 22), "color": "Color(1, 0.7, 0.4, 1)", "energy": 1.05, "scale": 2.6},
		{"c": Vector2i(28, 12), "color": "Color(0.6, 0.85, 1, 1)", "energy": 1.05, "scale": 2.8},
		{"c": Vector2i(33, 27), "color": "Color(1, 0.72, 0.42, 1)", "energy": 1.15, "scale": 3.0},
		{"c": Vector2i(48, 13), "color": "Color(0.6, 0.86, 1, 1)", "energy": 1.0, "scale": 2.6},
		{"c": Vector2i(52, 30), "color": "Color(0.62, 1, 0.72, 1)", "energy": 1.0, "scale": 2.6},
		{"c": Vector2i(44, 37), "color": "Color(1, 0.72, 0.42, 1)", "energy": 1.0, "scale": 2.6},
	]
	var out: Array = []
	for spot in spots:
		var cell: Vector2i = _pick_open(walk, spot["c"])
		out.append({
			"pos": _tile_pos(cell),
			"color": String(spot["color"]),
			"energy": float(spot["energy"]),
			"scale": float(spot["scale"]),
		})
	return out


func _tile_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)


func _verify(walk: Dictionary, entrance: Vector2i, portal: Vector2i, bridges: Array) -> void:
	assert(walk.has(entrance), "entrance not walkable")
	assert(walk.has(portal), "portal not walkable")
	assert(walk.size() > 900, "cavern too small: %d" % walk.size())
	var reach := MapKit.largest_region(walk, entrance)
	assert(reach.size() == walk.size(), "unreachable pocket: %d of %d" % [reach.size(), walk.size()])
	print("verify walk=", walk.size(), " reachable=", reach.size(), " bridges=", bridges.size())


# --- Scene ------------------------------------------------------------------

func _write_tscn(
	ground_b64: String,
	detail_b64: String,
	walls_b64: String,
	props_b64: String,
	ores: Array,
	lights: Array,
	entrance: Vector2i,
	portal: Vector2i
) -> void:
	var ore_nodes := ""
	var counts := {"iron": 0, "coal": 0, "mithril": 0, "adamant": 0, "runite": 0}
	var res_ids := {
		"iron": "13_iron",
		"coal": "14_coal",
		"mithril": "15_mith",
		"adamant": "16_adam",
		"runite": "17_rune",
	}
	for ore in ores:
		var kind: String = ore["kind"]
		counts[kind] = int(counts[kind]) + 1
		var pos: Vector2 = ore["pos"]
		ore_nodes += (
			"\n[node name=\"%sVein%d\" parent=\"MineableNodes\" instance=ExtResource(\"10_mine\")]\n"
			+ "y_sort_enabled = true\n"
			+ "position = Vector2(%s, %s)\n"
			+ "data = ExtResource(\"%s\")\n"
		) % [kind.capitalize(), int(counts[kind]), str(pos.x), str(pos.y), res_ids[kind]]

	var light_nodes := ""
	for i in lights.size():
		var light: Dictionary = lights[i]
		var pos: Vector2 = light["pos"]
		light_nodes += (
			"\n[node name=\"CaveLamp%d\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(%s, %s)\n"
			+ "color = %s\nenergy = %s\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = %s\n"
		) % [i + 1, str(pos.x), str(pos.y), light["color"], str(light["energy"]), str(light["scale"])]

	var entrance_pos := _tile_pos(entrance)
	var portal_pos := _tile_pos(portal)
	var camp_pos := _tile_pos(entrance + Vector2i(2, -1))
	var cam_r := W * TILE + 16
	var cam_b := H * TILE + 16

	var text := """[gd_scene format=3 uid=\"uid://cminingcave001\"]

[ext_resource type=\"Script\" uid=\"uid://7mbux4mybta0\" path=\"res://source/common/gameplay/maps/map.gd\" id=\"1_map\"]
[ext_resource type=\"TileSet\" path=\"res://source/common/gameplay/maps/tilesets/rpgw_caves_tileset.tres\" id=\"2_tiles\"]
[ext_resource type=\"AudioStream\" uid=\"uid://epws31tb1n8o\" path=\"res://assets/audio/music/shadow_temple.ogg\" id=\"3_music\"]
[ext_resource type=\"Script\" uid=\"uid://wq8klpndipnu\" path=\"res://source/common/network/sync/replicated_props.gd\" id=\"4_rp\"]
[ext_resource type=\"PackedScene\" uid=\"uid://b2ckixon7ryh6\" path=\"res://source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn\" id=\"5_warper\"]
[ext_resource type=\"PackedScene\" uid=\"uid://0m5eq6iylq26\" path=\"res://source/common/gameplay/maps/components/interaction_areas/warper/portal/portal.tscn\" id=\"6_portal\"]
[ext_resource type=\"Resource\" uid=\"uid://c0m2t2hjlih2p\" path=\"res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland.tres\" id=\"7_woodland\"]
[ext_resource type=\"PackedScene\" path=\"res://source/common/gameplay/lighting/campfire.tscn\" id=\"8_camp\"]
[ext_resource type=\"Texture2D\" path=\"res://source/common/gameplay/lighting/light_radial.tres\" id=\"9_glow\"]
[ext_resource type=\"PackedScene\" uid=\"uid://dqo57ux3v3lkq\" path=\"res://source/common/gameplay/maps/components/mineable_node.tscn\" id=\"10_mine\"]
[ext_resource type=\"Resource\" uid=\"uid://cutpirmfqwx8b\" path=\"res://source/common/gameplay/maps/components/mineable_nodes/iron_vein.tres\" id=\"13_iron\"]
[ext_resource type=\"Resource\" uid=\"uid://dtpviov364y0b\" path=\"res://source/common/gameplay/maps/components/mineable_nodes/coal_vein.tres\" id=\"14_coal\"]
[ext_resource type=\"Resource\" uid=\"uid://cmithrilvein01\" path=\"res://source/common/gameplay/maps/components/mineable_nodes/mithril_vein.tres\" id=\"15_mith\"]
[ext_resource type=\"Resource\" uid=\"uid://cadamantvein01\" path=\"res://source/common/gameplay/maps/components/mineable_nodes/adamant_vein.tres\" id=\"16_adam\"]
[ext_resource type=\"Resource\" uid=\"uid://crunitevein001\" path=\"res://source/common/gameplay/maps/components/mineable_nodes/runite_vein.tres\" id=\"17_rune\"]
[ext_resource type=\"Script\" path=\"res://source/common/gameplay/maps/components/skill_level_gate.gd\" id=\"18_gate\"]

[node name=\"mining_cave\" type=\"Node2D\" node_paths=PackedStringArray(\"replicated_props_container\")]
y_sort_enabled = true
script = ExtResource(\"1_map\")
replicated_props_container = NodePath(\"ReplicatedPropsContainer\")
map_background_color = Color(0.02, 0.018, 0.022, 1)
music = ExtResource(\"3_music\")
camera_limit_left = -16
camera_limit_top = -16
camera_limit_right = %d
camera_limit_bottom = %d

[node name=\"CanvasModulate\" type=\"CanvasModulate\" parent=\".\"]
color = Color(0.74, 0.7, 0.72, 1)

[node name=\"Tiles\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true

[node name=\"Ground\" type=\"TileMapLayer\" parent=\"Tiles\"]
z_index = -2
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"2_tiles\")

[node name=\"GroundDetail\" type=\"TileMapLayer\" parent=\"Tiles\"]
z_index = -1
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
%s
[node name=\"CampfireStaging\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]
position = Vector2(%s, %s)

[node name=\"ReplicatedPropsContainer\" type=\"Node2D\" parent=\".\" node_paths=PackedStringArray(\"id_to_node\", \"node_to_id\")]
y_sort_enabled = true
script = ExtResource(\"4_rp\")
id_to_node = {}
node_to_id = {}

[node name=\"MineableNodes\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true
%s

[node name=\"DeepVeinGate\" type=\"StaticBody2D\" parent=\".\"]
position = Vector2(1520, 480)
script = ExtResource(\"18_gate\")
required_skill = &\"mining\"
required_level = 50
gate_size = Vector2(120, 28)
label_text = \"Mining 50+\"

[node name=\"RespawnPoint\" parent=\".\" instance=ExtResource(\"5_warper\")]
position = Vector2(%s, %s)

[node name=\"Entrance\" parent=\".\" instance=ExtResource(\"5_warper\")]
position = Vector2(%s, %s)
warper_id = 30

[node name=\"WoodlandPortal\" parent=\".\" instance=ExtResource(\"6_portal\")]
position = Vector2(%s, %s)
portal_color = Color(0.35, 0.55, 0.28, 1)
destination_label = \"Goblin Woodland\"
target_instance = ExtResource(\"7_woodland\")
warper_id = 131
target_id = 130
""" % [
		cam_r, cam_b,
		ground_b64, detail_b64, walls_b64, props_b64,
		light_nodes,
		str(camp_pos.x), str(camp_pos.y),
		ore_nodes,
		str(entrance_pos.x), str(entrance_pos.y),
		str(entrance_pos.x), str(entrance_pos.y),
		str(portal_pos.x), str(portal_pos.y),
	]

	var path := ProjectSettings.globalize_path(OUT_TSCN)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", path)
