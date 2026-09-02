extends SceneTree
## Build the Starfall Mining Cave — the high-tier mining instance reached from
## the Unquarried Shelf in Starfall Grove.
##
##   godot --headless --path . -s tools/build_starfall_mining_cave.gd
##   godot --path . --mode=client res://tools/verify_starfall_cave.tscn
##
## Same discipline as build_mining_cave.gd, which this is modelled on: nothing
## here stamps a rectangle of atlas cells. Caverns are organic masks, every rim
## cell resolves from its neighbours through MapKit.paint_rim, and props are
## blue-noise scattered. Hand-stamping is what produces floating wall segments
## and missing corners.
##
## WHY THE COLLISION IS CORRECT BY CONSTRUCTION
## The rpgw caves TileSet carries collision polygons on exactly one 10x9 block
## of atlas cells (0,0)-(9,8), which is the rim bank. `paint_rim` paints from
## that bank and nothing else, and it fills `blocked` with precisely the cells
## it painted — the void plus the TWO rows of south cliff face below it. So the
## walkable set this script reasons about is the same set the physics engine
## will enforce, and the collision sits flush with the visual base of the wall
## rather than at its top edge. `verify_starfall_cave.gd` re-checks that against
## the built scene rather than trusting this comment.
##
## ZONES, in walking order from the grove:
##   Lantern Landing  entrance hall, campfire, the way back
##   The Crossing     junction; every alcove hangs off this
##   Emberthroat      Dragon    lv65  volcanic vent, warm
##   Geode Hollow     Obsidian  lv70  dark crystal chamber
##   The Skylight     Celestial lv80  open chamber, shaft of pale light
##   Astral Vault     Astralite lv90  deepest, cold violet, behind a throat

const MapKit := preload("res://tools/lib/mapkit.gd")

const TILESET := "res://source/common/gameplay/maps/tilesets/rpgw_caves_tileset.tres"
const OUT_TSCN := "res://source/common/gameplay/maps/maps/starfall_mining_cave/starfall_mining_cave.tscn"

const W := 76
const H := 54
const TILE := 32
const BORDER := 3

## Ground bank: only the flat middle cells are safe to repeat. Everything
## outside it carries directional shading that tiles up as square wedges.
const GROUND_PLAIN: Array[Vector2i] = [
	Vector2i(32, 28), Vector2i(33, 28), Vector2i(32, 29), Vector2i(33, 29),
]
## Solid dark rock under every void cell — the rim corner art is ~70% opaque and
## punches through to the background without this backing.
const VOID_FILL := Vector2i(4, 3)

## Verified prop rectangles on decorative.png (source 1). Rows 8-15 are
## near-black silhouettes that stamp as black boxes on lit floor; only the lit
## bank is used. Format: x, y, w, h.
const SMALL_ROCKS := [[11, 3, 1, 1], [0, 7, 1, 1]]
const MED_ROCKS := [[9, 2, 2, 2], [5, 2, 2, 2], [7, 2, 2, 2]]
const BIG_ROCKS := [[0, 1, 3, 3], [3, 1, 2, 3]]
const CRYSTALS := [[0, 18], [3, 18], [0, 20], [3, 20], [5, 18], [8, 18], [5, 20], [8, 20]]
const FLOOR_SPECKS := [[1, 25], [3, 25], [5, 25], [1, 28], [3, 28], [5, 28]]

## One entry per themed alcove. `r` is the chamber radius; `ore_r` is how far
## from its centre a vein may sit and must be >= `r`, because veins go on floor
## that TOUCHES ROCK and that ring is the chamber wall. Set it below `r` and the
## search only sees the open middle of the room, where there are no edge cells.
const ZONES := [
	{
		"key": "dragon", "label": "Emberthroat", "c": Vector2i(13, 26),
		"r": 8.0, "ore_r": 9, "count": 6, "terrain": 3,
		"light": Color(1.0, 0.52, 0.24), "energy": 1.15, "scale": 2.6,
	},
	{
		"key": "obsidian", "label": "Geode Hollow", "c": Vector2i(48, 45),
		"r": 8.5, "ore_r": 9, "count": 5, "terrain": 2,
		"light": Color(0.72, 0.35, 1.0), "energy": 0.95, "scale": 2.3,
	},
	{
		"key": "celestial", "label": "The Skylight", "c": Vector2i(50, 19),
		"r": 9.0, "ore_r": 10, "count": 5, "terrain": 1,
		"light": Color(1.0, 0.96, 0.78), "energy": 1.45, "scale": 3.4,
	},
	{
		"key": "astralite", "label": "Astral Vault", "c": Vector2i(68, 9),
		"r": 7.0, "ore_r": 8, "count": 4, "terrain": 2,
		"light": Color(0.72, 0.64, 1.0), "energy": 1.2, "scale": 2.5,
	},
]

var _bounds := Rect2i(0, 0, W, H)


func _initialize() -> void:
	var ts: TileSet = load(TILESET)
	assert(ts != null, "missing rpgw tileset — run build_rpgw_cave_tileset.gd first")

	var ground := _layer(ts)
	var detail := _layer(ts)
	var walls := _layer(ts)
	var props := _layer(ts)
	var ceiling := _layer(ts)

	var floor_mask := _carve()
	var void_mask: Dictionary = {}
	for y in H:
		for x in W:
			var cell := Vector2i(x, y)
			if not floor_mask.has(cell):
				void_mask[cell] = true

	_paint_ground(ground, floor_mask)
	for cell: Vector2i in void_mask.keys():
		ground.set_cell(cell, 0, VOID_FILL)

	var blocked: Dictionary = {}
	MapKit.paint_rim(walls, void_mask, _rim_spec(), _bounds, blocked)

	# Walkable = floor minus whatever the cliff face covers.
	var walk: Dictionary = {}
	for cell: Vector2i in floor_mask.keys():
		if not blocked.has(cell):
			walk[cell] = true

	var entrance := _pick_open(walk, Vector2i(13, 46))
	walk = MapKit.largest_region(walk, entrance)
	var portal := _pick_open(walk, entrance + Vector2i(3, 2))

	_paint_patches(detail, floor_mask, walk)

	# Nothing may be stamped where a player arrives or where the campfire sits.
	var keepout: Dictionary = {}
	for spot: Vector2i in [entrance, portal, entrance + Vector2i(-2, -1)]:
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				keepout[spot + Vector2i(ox, oy)] = true

	# Ore anchors are reserved BEFORE props are scattered, so a boulder can
	# never land on the tile a vein needs and squeeze the approach to it.
	var ores := _place_ores(walk, blocked, keepout)
	for ore: Dictionary in ores:
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				keepout[(ore["cell"] as Vector2i) + Vector2i(ox, oy)] = true

	var solid_props := _paint_props(props, walk, blocked, keepout)
	for cell: Vector2i in solid_props.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, entrance)

	_paint_ceiling(ceiling, void_mask, blocked, walk)

	var lights := _lights(walk, entrance)
	_verify(walk, entrance, portal, ores)

	_write_tscn(
		MapKit.to_base64(ground), MapKit.to_base64(detail), MapKit.to_base64(walls),
		MapKit.to_base64(props), MapKit.to_base64(ceiling),
		ores, lights, entrance, portal
	)
	print(
		"OK starfall_mining_cave floor=", floor_mask.size(),
		" walk=", walk.size(),
		" void=", void_mask.size(),
		" ground=", ground.get_used_cells().size(),
		" detail=", detail.get_used_cells().size(),
		" walls=", walls.get_used_cells().size(),
		" props=", props.get_used_cells().size(),
		" ceiling=", ceiling.get_used_cells().size(),
		" ores=", ores.size()
	)
	quit(0)


func _layer(ts: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	return layer


## str(Color) yields "(r, g, b, a)" with no type name, which is not valid in a
## .tscn and makes the whole scene fail to parse. Emit the literal by hand.
func _color_str(c: Color) -> String:
	return "Color(%s, %s, %s, %s)" % [c.r, c.g, c.b, c.a]


func _tile_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)


func _pick_open(mask: Dictionary, wanted: Vector2i) -> Vector2i:
	if mask.has(wanted):
		return wanted
	var best := wanted
	var best_d: int = 1 << 30
	for cell: Vector2i in mask.keys():
		var d: int = (cell - wanted).length_squared()
		if d < best_d:
			best_d = d
			best = cell
	return best


# --- Shape ------------------------------------------------------------------

func _carve() -> Dictionary:
	var mask: Dictionary = {}
	# Halls. Every alcove is a real chamber, not a bulge in a corridor, so each
	# tier gets a place a player can stand around in with other players.
	var chambers := [
		{"c": Vector2i(13, 46), "r": 7.5, "w": 0.28, "s": 401},   # Lantern Landing
		{"c": Vector2i(29, 38), "r": 5.5, "w": 0.30, "s": 402},   # The Crossing
		{"c": Vector2i(13, 26), "r": 8.0, "w": 0.30, "s": 403},   # Emberthroat
		{"c": Vector2i(48, 45), "r": 8.5, "w": 0.28, "s": 404},   # Geode Hollow
		{"c": Vector2i(50, 19), "r": 9.0, "w": 0.24, "s": 405},   # The Skylight
		{"c": Vector2i(61, 13), "r": 3.0, "w": 0.20, "s": 406},   # vault antechamber
		{"c": Vector2i(68, 9), "r": 7.0, "w": 0.22, "s": 407},    # Astral Vault
	]
	for ch: Dictionary in chambers:
		MapKit.blob(mask, ch["c"], ch["r"], ch["w"], int(ch["s"]), _bounds)

	# Haulage tunnels. Width 2.4-2.8 puts every main route at roughly 5 tiles
	# across — two players pass without shoving each other into the rock. The
	# vault throat is narrower to read as a gate, but never below 3 tiles.
	var links := [
		[Vector2i(16, 43), Vector2i(26, 40), 2.4, 1.2, 421],   # landing -> crossing
		[Vector2i(26, 35), Vector2i(15, 31), 2.4, 1.2, 422],   # crossing -> Emberthroat
		[Vector2i(33, 40), Vector2i(43, 44), 2.4, 1.2, 423],   # crossing -> Geode
		[Vector2i(32, 35), Vector2i(45, 24), 2.4, 1.4, 424],   # crossing -> Skylight
		[Vector2i(50, 39), Vector2i(51, 27), 2.2, 1.0, 425],   # Geode -> Skylight loop
		[Vector2i(56, 16), Vector2i(60, 14), 1.9, 0.8, 426],   # Skylight -> antechamber
		[Vector2i(62, 12), Vector2i(65, 10), 1.8, 0.6, 427],   # throat -> vault
	]
	for link: Array in links:
		MapKit.tunnel(mask, link[0], link[1], link[2], link[3], int(link[4]), _bounds)

	# Guarantee the vault throat survives smoothing and region trimming — a
	# sealed alcove is the arena_1 failure and it is invisible until playtest.
	for x: int in range(61, 67):
		for y: int in range(9, 13):
			mask[Vector2i(x, y)] = true

	# Solid rock margin so no cavern touches the map border.
	var trimmed: Dictionary = {}
	for cell: Vector2i in mask.keys():
		if cell.x >= BORDER and cell.y >= BORDER + 1 \
				and cell.x < W - BORDER and cell.y < H - BORDER:
			trimmed[cell] = true
	return MapKit.smooth(trimmed, _bounds, 2, 5, 4)


func _rim_spec() -> MapKit.RimSpec:
	# The rim bank is the ONLY part of the atlas carrying collision polygons, so
	# every cell named here is both drawn and solid. Do not substitute a tile
	# from elsewhere in the sheet — it would look like rock and walk like floor.
	var spec := MapKit.RimSpec.new()
	spec.source = 0
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
		ground.set_cell(cell, 0, MapKit._pick(GROUND_PLAIN, cell, 431))


## Each alcove stands on its own FLOOR MATERIAL, autotiled with a proper blend
## edge, so a chamber reads as a place from the corridor. This is the part that
## actually separates the zones: wide multiplayer corridors inevitably read as
## openings at map scale, so distinctness has to come from the ground and the
## light rather than from how thin the rock between rooms is.
##
## The three banks are LEARNED from the artwork by corner_lookup rather than
## transcribed, and painting them with the same tiles as the base ground (which
## an earlier pass did) is a silent no-op — the layer fills up and nothing
## changes on screen.
func _paint_patches(detail: TileMapLayer, floor_mask: Dictionary, _walk: Dictionary) -> void:
	var atlas := (load(TILESET) as TileSet).get_source(0) as TileSetAtlasSource
	var tex: Texture2D = atlas.texture
	var lookups := {
		1: MapKit.corner_lookup(tex, 32, Rect2i(10, 31, 5, 9), Color8(61, 68, 45)),
		2: MapKit.corner_lookup(tex, 32, Rect2i(25, 31, 5, 9), Color8(53, 57, 58)),
		3: MapKit.corner_lookup(tex, 32, Rect2i(40, 31, 5, 9), Color8(77, 59, 48)),
	}
	var patches: Array = []
	for zone: Dictionary in ZONES:
		patches.append({
			"terrain": int(zone["terrain"]), "c": zone["c"],
			"r": float(zone["r"]) - 1.0, "s": 481 + patches.size(),
		})
	# The landing and the junction get their own floor too, so the route in
	# reads as worked ground rather than as more cavern.
	patches.append({"terrain": 3, "c": Vector2i(13, 46), "r": 5.5, "s": 491})
	patches.append({"terrain": 2, "c": Vector2i(29, 38), "r": 4.0, "s": 492})

	for patch: Dictionary in patches:
		var blob_mask: Dictionary = {}
		MapKit.blob(blob_mask, patch["c"], patch["r"], 0.22, int(patch["s"]), _bounds)
		# Smooth first: a ragged 1-cell edge autotiles into a starburst rather
		# than a seam.
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


# --- Ore --------------------------------------------------------------------

## Veins sit on floor cells that touch rock, which is where an embedded seam
## belongs. Spacing is 3 tiles (96px) against HarvestController.GATHER_RANGE of
## 48px, so a click can only ever resolve to one vein and two players can work
## neighbouring seams without standing on each other.
func _place_ores(walk: Dictionary, blocked: Dictionary, keepout: Dictionary) -> Array:
	var out: Array = []
	var used: Dictionary = {}
	for zone: Dictionary in ZONES:
		var centre: Vector2i = zone["c"]
		var r2: int = int(zone["ore_r"]) * int(zone["ore_r"])
		var near: Array[Vector2i] = []
		for cell: Vector2i in MapKit.edge_cells(walk, blocked):
			if used.has(cell) or keepout.has(cell):
				continue
			if (cell - centre).length_squared() > r2:
				continue
			# Needs room to stand on at least three sides or the vein is a
			# bottleneck the moment a second player walks up to it.
			var open: int = 0
			for step: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if walk.has(cell + step):
					open += 1
			if open >= 3:
				near.append(cell)
		# scatter()'s spacing is a Chebyshev +/-N box, so 2 already guarantees a
		# 3-tile (96px) gap — comfortably past the 72px a click needs to resolve
		# to one vein, while 3 reserves a 7x7 and starves the smaller chambers.
		# Density 1.0 keeps the layout deterministic rather than dropping ~5%.
		var picked := MapKit.scatter(near, 1.0, 2, 451 + out.size())
		var count: int = 0
		for cell: Vector2i in picked:
			if count >= int(zone["count"]):
				break
			used[cell] = true
			out.append({"kind": String(zone["key"]), "cell": cell, "pos": _tile_pos(cell)})
			count += 1
		assert(
			count == int(zone["count"]),
			"%s: placed %d of %d veins" % [zone["label"], count, int(zone["count"])]
		)
	return out


# --- Props ------------------------------------------------------------------

func _paint_props(
	props: TileMapLayer, walk: Dictionary, blocked: Dictionary, keepout: Dictionary
) -> Dictionary:
	var formations: Array = []
	for r: Array in MED_ROCKS + BIG_ROCKS:
		formations.append(MapKit.rect_cluster(r[0], r[1], r[2], r[3]))
	var boulders: Array = []
	for r: Array in SMALL_ROCKS:
		boulders.append(MapKit.rect_cluster(r[0], r[1], r[2], r[3]))
	var specks: Array = []
	for r: Array in FLOOR_SPECKS:
		specks.append(MapKit.rect_cluster(r[0], r[1], 1, 1))

	var edges := MapKit.edge_cells(walk, blocked)
	var inner := MapKit.interior_cells(walk, blocked, 3)
	var solid: Dictionary = {}

	# A blocking prop may only stand where the floor is wide enough that losing
	# the cell cannot plug a route.
	var roomy := func(cell: Vector2i) -> bool:
		if keepout.has(cell):
			return false
		var n: int = 0
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if walk.has(cell + Vector2i(ox, oy)):
					n += 1
		return n >= 8

	var free: Dictionary = {}
	for cell: Vector2i in inner:
		if not keepout.has(cell):
			free[cell] = true
	var used: int = 0
	for anchor: Vector2i in MapKit.scatter(inner, 0.45, 7, 461, roomy):
		if used >= 8:
			break
		var cluster: Dictionary = formations[MapKit.hash2(anchor.x, anchor.y, 462) % formations.size()]
		var placed := MapKit.stamp_cluster(props, 1, cluster, anchor, free, _bounds)
		if placed.is_empty():
			continue
		for cell: Vector2i in placed:
			solid[cell] = true
			free.erase(cell)
		used += 1

	var wall_free: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if not solid.has(cell) and not keepout.has(cell):
			wall_free[cell] = true
	for cell: Vector2i in MapKit.scatter(edges, 0.20, 3, 463, roomy):
		if solid.has(cell):
			continue
		var cluster: Dictionary = boulders[MapKit.hash2(cell.x, cell.y, 464) % boulders.size()]
		for c2: Vector2i in MapKit.stamp_cluster(props, 1, cluster, cell, wall_free, _bounds):
			solid[c2] = true
			wall_free.erase(c2)

	# Floor specks are flat decals — never solid, so they may fall anywhere the
	# player is not about to stand on arrival.
	for cell: Vector2i in MapKit.scatter(inner, 0.18, 2, 465):
		if solid.has(cell) or keepout.has(cell):
			continue
		var cluster: Dictionary = specks[MapKit.hash2(cell.x, cell.y, 466) % specks.size()]
		MapKit.stamp_cluster(props, 1, cluster, cell, {cell: true}, _bounds)
	return solid


## Overhead layer: crystal clusters hanging from the rock ABOVE the player, on
## the void side of a chamber's north rim. Drawn from the decorative sheet,
## which carries no collision polygons at all, so nothing here can ever block a
## player no matter where it lands.
func _paint_ceiling(
	ceiling: TileMapLayer, void_mask: Dictionary, blocked: Dictionary, walk: Dictionary
) -> void:
	var crystals: Array = []
	for r: Array in CRYSTALS:
		crystals.append(MapKit.rect_cluster(r[0], r[1], 1, 1))
	var overhang: Array[Vector2i] = []
	for zone: Dictionary in ZONES:
		var centre: Vector2i = zone["c"]
		var reach: int = int(zone["r"]) + 2
		for cell: Vector2i in blocked.keys():
			if void_mask.has(cell):
				continue   # rock body, not the overhanging lip
			if (cell - centre).length_squared() > reach * reach:
				continue
			# Bottom row of the south cliff face with open floor beneath it:
			# the lip a player standing in the chamber sees above them.
			if walk.has(cell + Vector2i.DOWN):
				overhang.append(cell)
	var free: Dictionary = {}
	for cell: Vector2i in overhang:
		free[cell] = true
	for cell: Vector2i in MapKit.scatter(overhang, 0.35, 2, 471):
		var cluster: Dictionary = crystals[MapKit.hash2(cell.x, cell.y, 472) % crystals.size()]
		MapKit.stamp_cluster(ceiling, 1, cluster, cell, free, _bounds)


# --- Lighting ---------------------------------------------------------------

func _lights(walk: Dictionary, entrance: Vector2i) -> Array:
	var out: Array = []
	out.append({
		"name": "LandingGlow", "pos": _tile_pos(_pick_open(walk, entrance)),
		"color": Color(1.0, 0.78, 0.45), "energy": 1.0, "scale": 2.4,
	})
	out.append({
		"name": "CrossingGlow", "pos": _tile_pos(_pick_open(walk, Vector2i(29, 38))),
		"color": Color(0.86, 0.82, 0.78), "energy": 0.8, "scale": 2.6,
	})
	for zone: Dictionary in ZONES:
		out.append({
			"name": String(zone["label"]).replace(" ", "") + "Glow",
			"pos": _tile_pos(_pick_open(walk, zone["c"])),
			"color": zone["light"], "energy": zone["energy"], "scale": zone["scale"],
		})
	return out


# --- Verify -----------------------------------------------------------------

func _verify(walk: Dictionary, entrance: Vector2i, portal: Vector2i, ores: Array) -> void:
	assert(walk.has(entrance), "entrance not walkable")
	assert(walk.has(portal), "grove portal not walkable")
	assert(walk.size() > 1000, "cavern too small: %d" % walk.size())
	var reach := MapKit.largest_region(walk, entrance)
	assert(reach.size() == walk.size(), "unreachable pocket: %d of %d" % [reach.size(), walk.size()])
	for ore: Dictionary in ores:
		assert(walk.has(ore["cell"]), "vein at %s is not on walkable floor" % [ore["cell"]])
		assert(reach.has(ore["cell"]), "vein at %s is unreachable" % [ore["cell"]])
	# Every pair must clear 1.5x GATHER_RANGE so a click resolves to one vein.
	var closest: float = 1e9
	for i: int in ores.size():
		for j: int in range(i + 1, ores.size()):
			var d: float = (ores[i]["pos"] as Vector2).distance_to(ores[j]["pos"] as Vector2)
			closest = minf(closest, d)
	assert(closest > 72.0, "veins too close: %.0fpx" % closest)
	print("verify walk=%d reachable=%d ores=%d closest=%.0fpx" % [
		walk.size(), reach.size(), ores.size(), closest,
	])


# --- Scene ------------------------------------------------------------------

func _write_tscn(
	ground_b64: String, detail_b64: String, walls_b64: String,
	props_b64: String, ceiling_b64: String,
	ores: Array, lights: Array, entrance: Vector2i, portal: Vector2i
) -> void:
	var res_ids := {
		"dragon": "20_dragon", "obsidian": "21_obsidian",
		"celestial": "22_celestial", "astralite": "23_astralite",
	}
	var counts := {"dragon": 0, "obsidian": 0, "celestial": 0, "astralite": 0}
	var ore_nodes := ""
	for ore: Dictionary in ores:
		var kind: String = ore["kind"]
		counts[kind] = int(counts[kind]) + 1
		var pos: Vector2 = ore["pos"]
		ore_nodes += (
			"\n[node name=\"%sVein%d\" parent=\"MineableNodes\" instance=ExtResource(\"10_mine\")]\n"
			+ "y_sort_enabled = true\nposition = Vector2(%s, %s)\ndata = ExtResource(\"%s\")\n"
		) % [kind.capitalize(), int(counts[kind]), str(pos.x), str(pos.y), res_ids[kind]]

	var light_nodes := ""
	for light: Dictionary in lights:
		var pos: Vector2 = light["pos"]
		light_nodes += (
			"\n[node name=\"%s\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(%s, %s)\ncolor = %s\nenergy = %s\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = %s\n"
		) % [light["name"], str(pos.x), str(pos.y), _color_str(light["color"]),
			str(light["energy"]), str(light["scale"])]

	var entrance_pos := _tile_pos(entrance)
	var portal_pos := _tile_pos(portal)
	var camp_pos := _tile_pos(entrance + Vector2i(-2, -1))

	var text := """[gd_scene format=3 uid="uid://cstarfallcave01"]

[ext_resource type="Script" uid="uid://7mbux4mybta0" path="res://source/common/gameplay/maps/map.gd" id="1_map"]
[ext_resource type="TileSet" path="res://source/common/gameplay/maps/tilesets/rpgw_caves_tileset.tres" id="2_tiles"]
[ext_resource type="AudioStream" uid="uid://lx71aecmr0ks" path="res://assets/audio/music/alone.ogg" id="3_music"]
[ext_resource type="Script" uid="uid://wq8klpndipnu" path="res://source/common/network/sync/replicated_props.gd" id="4_rp"]
[ext_resource type="PackedScene" uid="uid://b2ckixon7ryh6" path="res://source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn" id="5_warper"]
[ext_resource type="PackedScene" uid="uid://0m5eq6iylq26" path="res://source/common/gameplay/maps/components/interaction_areas/warper/portal/portal.tscn" id="6_portal"]
[ext_resource type="Resource" path="res://source/common/gameplay/maps/instance/instance_collection/biomes/starfall_grove.tres" id="7_grove"]
[ext_resource type="PackedScene" path="res://source/common/gameplay/lighting/campfire.tscn" id="8_camp"]
[ext_resource type="Texture2D" path="res://source/common/gameplay/lighting/light_radial.tres" id="9_glow"]
[ext_resource type="PackedScene" uid="uid://dqo57ux3v3lkq" path="res://source/common/gameplay/maps/components/mineable_node.tscn" id="10_mine"]
[ext_resource type="Resource" path="res://source/common/gameplay/maps/components/mineable_nodes/dragon_vein.tres" id="20_dragon"]
[ext_resource type="Resource" path="res://source/common/gameplay/maps/components/mineable_nodes/obsidian_vein.tres" id="21_obsidian"]
[ext_resource type="Resource" path="res://source/common/gameplay/maps/components/mineable_nodes/celestial_vein.tres" id="22_celestial"]
[ext_resource type="Resource" path="res://source/common/gameplay/maps/components/mineable_nodes/astralite_vein.tres" id="23_astralite"]

[node name="starfall_mining_cave" type="Node2D" node_paths=PackedStringArray("replicated_props_container")]
y_sort_enabled = true
script = ExtResource("1_map")
replicated_props_container = NodePath("ReplicatedPropsContainer")
map_background_color = Color(0.015, 0.014, 0.02, 1)
music = ExtResource("3_music")
camera_limit_left = -16
camera_limit_top = -16
camera_limit_right = %d
camera_limit_bottom = %d

[node name="CanvasModulate" type="CanvasModulate" parent="."]
color = Color(0.62, 0.6, 0.68, 1)

[node name="Tiles" type="Node2D" parent="."]
y_sort_enabled = true

[node name="Ground" type="TileMapLayer" parent="Tiles"]
z_index = -3
tile_map_data = PackedByteArray("%s")
tile_set = ExtResource("2_tiles")

[node name="GroundDetail" type="TileMapLayer" parent="Tiles"]
z_index = -2
tile_map_data = PackedByteArray("%s")
tile_set = ExtResource("2_tiles")

[node name="Walls" type="TileMapLayer" parent="Tiles"]
y_sort_enabled = true
tile_map_data = PackedByteArray("%s")
tile_set = ExtResource("2_tiles")

[node name="Props" type="TileMapLayer" parent="Tiles"]
y_sort_enabled = true
tile_map_data = PackedByteArray("%s")
tile_set = ExtResource("2_tiles")

[node name="Ceiling" type="TileMapLayer" parent="Tiles"]
z_index = 200
tile_map_data = PackedByteArray("%s")
tile_set = ExtResource("2_tiles")

[node name="SceneProps" type="Node2D" parent="."]
y_sort_enabled = true
%s
[node name="CampfireStaging" parent="SceneProps" instance=ExtResource("8_camp")]
position = Vector2(%s, %s)

[node name="ReplicatedPropsContainer" type="Node2D" parent="." node_paths=PackedStringArray("id_to_node", "node_to_id")]
y_sort_enabled = true
script = ExtResource("4_rp")
id_to_node = {}
node_to_id = {}

[node name="MineableNodes" type="Node2D" parent="."]
y_sort_enabled = true
%s

[node name="RespawnPoint" parent="." instance=ExtResource("5_warper")]
position = Vector2(%s, %s)

[node name="Entrance" parent="." instance=ExtResource("5_warper")]
position = Vector2(%s, %s)
warper_id = 34

[node name="GrovePortal" parent="." instance=ExtResource("6_portal")]
position = Vector2(%s, %s)
portal_color = Color(0.36, 0.86, 0.82, 1)
destination_label = "Starfall Grove"
target_instance = ExtResource("7_grove")
warper_id = 135
target_id = 35
""" % [
		W * TILE + 16, H * TILE + 16,
		ground_b64, detail_b64, walls_b64, props_b64, ceiling_b64,
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
