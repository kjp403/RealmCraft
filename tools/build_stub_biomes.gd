extends SceneTree
## Rebuild Desert / Fire Forge / Sewers to shipping quality:
## - Desert: authored mesa + temple stamps from Desert/Ground (not one sand box)
## - Fire Forge / Sewers: Fungus room footprints (same silhouette craft as Mining Cave)
##   with biome-specific floors/walls/props
##   godot --headless --path . -s tools/build_stub_biomes.gd

const DESERT_TS := "res://source/common/gameplay/maps/tilesets/desert_tileset.tres"
const FORGE_ACCENT_TS := "res://source/common/gameplay/maps/tilesets/fire_forge_tileset.tres"
const SEWERS_ACCENT_TS := "res://source/common/gameplay/maps/tilesets/sewers_tileset.tres"
const MINE_TS := "res://source/common/gameplay/maps/tilesets/mining_cave_tileset.tres"
const STAMP_DIR := "res://tools/stamps/"

## Dirt floors from mining_cave (never fungus grass).
const DIRT_FLOORS: Array[Vector2i] = [
	Vector2i(8, 15), Vector2i(7, 15), Vector2i(9, 15), Vector2i(8, 14),
	Vector2i(10, 15), Vector2i(6, 15), Vector2i(10, 13), Vector2i(8, 13),
	Vector2i(7, 14), Vector2i(9, 14), Vector2i(7, 16), Vector2i(9, 16),
]

const HOSTILE := "res://source/common/gameplay/characters/npc/hostile_npc.tscn"
const WARPER := "res://source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn"
const PORTAL := "res://source/common/gameplay/maps/components/interaction_areas/warper/portal/portal.tscn"
const HUB := "res://source/common/gameplay/maps/instance/instance_collection/overworld.tres"
const CAMP := "res://source/common/gameplay/lighting/campfire.tscn"
const GLOW := "res://source/common/gameplay/lighting/light_radial.tres"
const MAP_SCRIPT := "res://source/common/gameplay/maps/map.gd"
const RP_SCRIPT := "res://source/common/network/sync/replicated_props.gd"

const W := 60
const H := 45


func _initialize() -> void:
	_build_desert()
	_build_fire_forge()
	_build_sewers()
	print("STUB_BIOMES_PASS")
	quit(0)


func _hash(cell: Vector2i) -> int:
	return absi((cell.x * 73856093) ^ (cell.y * 19349663))


func _pick(arr: Array, cell: Vector2i) -> Vector2i:
	return arr[_hash(cell) % arr.size()]


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < W and cell.y < H


func _b64(layer: TileMapLayer) -> String:
	return Marshalls.raw_to_base64(layer.tile_map_data)


func _tile_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 16.0 + 8.0, cell.y * 16.0 + 8.0)


func _keepouts(cx: int) -> Array:
	return [Vector2i(cx, H - 3), Vector2i(cx, H - 6), Vector2i(cx, H - 7)]


func _load_stamp(path: String) -> Dictionary:
	## Full Mining/Fungus stamp: keeps authored wall atlas coords.
	var text := FileAccess.get_file_as_string(path)
	var size := Vector2i.ZERO
	var ground_cells: Array = []
	var wall_cells: Array = []
	for line in text.split("\n"):
		var p := line.strip_edges().split(" ")
		if p.is_empty() or p[0].is_empty():
			continue
		if p[0] == "SIZE":
			size = Vector2i(int(p[1]), int(p[2]))
		elif p[0] == "G":
			ground_cells.append({
				"pos": Vector2i(int(p[1]), int(p[2])),
				"atlas": Vector2i(int(p[3]), int(p[4])),
			})
		elif p[0] == "W":
			wall_cells.append({
				"pos": Vector2i(int(p[1]), int(p[2])),
				"atlas": Vector2i(int(p[3]), int(p[4])),
			})
	return {"size": size, "ground": ground_cells, "walls": wall_cells}


func _dirt_at(cell: Vector2i) -> Vector2i:
	return DIRT_FLOORS[_hash(cell) % DIRT_FLOORS.size()]


func _stamp_mine_room(
	ground: TileMapLayer,
	walls: TileMapLayer,
	walk: Dictionary,
	origin: Vector2i,
	stamp_path: String
) -> void:
	var stamp := _load_stamp(stamp_path)
	for g in stamp["ground"]:
		var cell: Vector2i = origin + g["pos"]
		if not _in_bounds(cell):
			continue
		ground.set_cell(cell, 0, _dirt_at(cell))
		walk[cell] = true
		if walls.get_cell_source_id(cell) >= 0:
			walls.erase_cell(cell)
	for wcell in stamp["walls"]:
		var cell2: Vector2i = origin + wcell["pos"]
		if not _in_bounds(cell2) or walk.has(cell2):
			continue
		walls.set_cell(cell2, 0, wcell["atlas"])


func _carve_mine_corridor(
	ground: TileMapLayer,
	walls: TileMapLayer,
	walk: Dictionary,
	a: Vector2i,
	b: Vector2i,
	width: int = 3
) -> void:
	var half := int(width / 2)
	var x := a.x
	var y := a.y
	while true:
		for oy in range(-half, half + 1):
			for ox in range(-half, half + 1):
				var cell := Vector2i(x + ox, y + oy)
				if not _in_bounds(cell):
					continue
				if walls.get_cell_source_id(cell) >= 0:
					walls.erase_cell(cell)
				ground.set_cell(cell, 0, _dirt_at(cell))
				walk[cell] = true
		if x == b.x and y == b.y:
			break
		if x != b.x:
			x += 1 if b.x > x else -1
		elif y != b.y:
			y += 1 if b.y > y else -1
	# North lip columns (authored pairs from Mining Cave).
	var cols: Array = [
		[Vector2i(2, 6), Vector2i(2, 7)],
		[Vector2i(2, 15), Vector2i(2, 16)],
		[Vector2i(3, 15), Vector2i(3, 16)],
		[Vector2i(4, 5), Vector2i(4, 6)],
	]
	var x0: int = mini(a.x, b.x) - half
	var x1: int = maxi(a.x, b.x) + half
	var y0: int = mini(a.y, b.y) - half
	var y1: int = maxi(a.y, b.y) + half
	var horiz := (maxi(a.x, b.x) - mini(a.x, b.x)) >= (maxi(a.y, b.y) - mini(a.y, b.y))
	if horiz:
		var i := 0
		for xx in range(x0, x1 + 1):
			var col: Array = cols[i % cols.size()]
			i += 1
			var above := Vector2i(xx, y0 - 1)
			var above2 := Vector2i(xx, y0 - 2)
			if _in_bounds(above) and not walk.has(above):
				walls.set_cell(above, 0, col[1] if col.size() > 1 else col[0])
			if _in_bounds(above2) and not walk.has(above2):
				walls.set_cell(above2, 0, col[0])
			var below := Vector2i(xx, y1 + 1)
			if _in_bounds(below) and not walk.has(below):
				walls.set_cell(below, 0, Vector2i(1, 1))
	else:
		for yy in range(y0, y1 + 1):
			var left := Vector2i(x0 - 1, yy)
			var right := Vector2i(x1 + 1, yy)
			if _in_bounds(left) and not walk.has(left):
				walls.set_cell(left, 0, Vector2i(4, 5))
			if _in_bounds(right) and not walk.has(right):
				walls.set_cell(right, 0, Vector2i(0, 3))


func _place_props_wall_aligned(
	props: TileMapLayer,
	walk: Dictionary,
	walls: TileMapLayer,
	atlases: Array,
	source: int,
	count: int,
	keepout: Array
) -> void:
	var placed := 0
	var cells: Array = walk.keys()
	cells.sort_custom(func(a, b): return _hash(a) < _hash(b))
	for cell: Vector2i in cells:
		if placed >= count:
			break
		if _hash(cell) % 5 != 0:
			continue
		var near_wall := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if walls.get_cell_source_id(cell + d) >= 0:
				near_wall = true
				break
		if not near_wall:
			continue
		var blocked := false
		for k in keepout:
			if cell.distance_squared_to(k) < 36:
				blocked = true
				break
		if blocked:
			continue
		if props.get_cell_source_id(cell) >= 0:
			continue
		props.set_cell(cell, source, _pick(atlases, cell))
		placed += 1


func _stamp_atlas_block(
	layer: TileMapLayer,
	origin: Vector2i,
	atlas0: Vector2i,
	size: Vector2i,
	source: int,
	skip_empty: Callable = Callable()
) -> void:
	for y in range(size.y):
		for x in range(size.x):
			if skip_empty.is_valid() and skip_empty.call(atlas0 + Vector2i(x, y)):
				continue
			var cell := origin + Vector2i(x, y)
			if _in_bounds(cell):
				layer.set_cell(cell, source, atlas0 + Vector2i(x, y))


# --- Desert -----------------------------------------------------------------

## Authored 6×6 mesa from Desert/Ground.png (source 0). W = wall, G = sand top, . = skip.
const MESA_ROWS: Array[String] = [
	".WWWW.",
	"WGGGGW",
	"WGGGGW",
	"WGGGGW",
	"WGGGGW",
	".WWWW.",
]


func _stamp_mesa(ground: TileMapLayer, walls: TileMapLayer, walk: Dictionary, origin: Vector2i) -> void:
	for y in range(6):
		var row: String = MESA_ROWS[y]
		for x in range(6):
			var ch := row[x]
			var cell := origin + Vector2i(x, y)
			if not _in_bounds(cell) or ch == ".":
				continue
			var atlas := Vector2i(x, y)
			if ch == "G":
				ground.set_cell(cell, 0, atlas)
				walk[cell] = true
				if walls.get_cell_source_id(cell) >= 0:
					walls.erase_cell(cell)
			else:
				walls.set_cell(cell, 0, atlas)
				walk.erase(cell)
				if ground.get_cell_source_id(cell) >= 0:
					ground.erase_cell(cell)


func _fill_sand_disk(ground: TileMapLayer, walk: Dictionary, center: Vector2i, radius: float) -> void:
	var sand: Array = [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
		Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3),
	]
	var r2 := int(radius * radius)
	for y in range(center.y - int(radius) - 1, center.y + int(radius) + 2):
		for x in range(center.x - int(radius) - 1, center.x + int(radius) + 2):
			var cell := Vector2i(x, y)
			if not _in_bounds(cell):
				continue
			var dx := x - center.x
			var dy := y - center.y
			# Mild noise so disks aren't perfect circles.
			var n := (_hash(cell) % 5) - 2
			if dx * dx + dy * dy <= r2 + n:
				ground.set_cell(cell, 0, _pick(sand, cell))
				walk[cell] = true


func _paint_desert_cliff_rim(walls: TileMapLayer, walk: Dictionary) -> void:
	## Ring walkable sand with Ground cliff faces (south physics tiles + rim tops).
	var cliff_s: Array = [Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5)]
	var cliff_n: Array = [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	var cliff_w: Array = [Vector2i(0, 2), Vector2i(0, 3)]
	var cliff_e: Array = [Vector2i(5, 2), Vector2i(5, 3)]
	var cliff_fill: Array = [Vector2i(7, 5), Vector2i(8, 5), Vector2i(7, 6), Vector2i(8, 6)]
	for cell: Vector2i in walk.keys():
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cell + d
			if not _in_bounds(n) or walk.has(n):
				continue
			if walls.get_cell_source_id(n) >= 0:
				continue
			var floor_n := walk.has(n + Vector2i.UP)
			var floor_s := walk.has(n + Vector2i.DOWN)
			var floor_w := walk.has(n + Vector2i.LEFT)
			var floor_e := walk.has(n + Vector2i.RIGHT)
			var atlas: Vector2i
			if floor_s and not floor_n:
				atlas = _pick(cliff_n, n)
			elif floor_n and not floor_s:
				atlas = _pick(cliff_s, n)
			elif floor_e and not floor_w:
				atlas = _pick(cliff_w, n)
			elif floor_w and not floor_e:
				atlas = _pick(cliff_e, n)
			else:
				atlas = _pick(cliff_fill, n)
			walls.set_cell(n, 0, atlas)


func _stamp_temple(ground: TileMapLayer, walls: TileMapLayer, props: TileMapLayer, walk: Dictionary, origin: Vector2i) -> void:
	## Modular temple from Ground rows 7–14 / cols 0–5 (blue-trim sandstone).
	## Shell = walls; open interior stays sand; south mouth kept walkable.
	for ty in range(8):
		for tx in range(6):
			var cell := origin + Vector2i(tx, ty)
			if not _in_bounds(cell):
				continue
			var atlas := Vector2i(tx, 7 + ty)
			var is_shell := tx == 0 or tx == 5 or ty == 0 or ty == 1 or ty == 7
			var is_inner_wall := (ty >= 2 and ty <= 5) and (tx == 1 or tx == 4)
			var is_door := ty >= 5 and tx >= 2 and tx <= 3
			if is_door:
				ground.set_cell(cell, 0, Vector2i(2, 2))
				walk[cell] = true
				if walls.get_cell_source_id(cell) >= 0:
					walls.erase_cell(cell)
				continue
			if is_shell or is_inner_wall:
				walls.set_cell(cell, 0, atlas)
				walk.erase(cell)
				if ground.get_cell_source_id(cell) >= 0:
					ground.erase_cell(cell)
			else:
				ground.set_cell(cell, 0, Vector2i(2, 2) if ((tx + ty) % 2) == 0 else Vector2i(3, 2))
				walk[cell] = true
				if walls.get_cell_source_id(cell) >= 0:
					walls.erase_cell(cell)
	# Stairs leading into the mouth (Ground 6–8, 8–12) as props overlay.
	var stair_origin := origin + Vector2i(1, 6)
	for sy in range(3):
		for sx in range(3):
			var sc := stair_origin + Vector2i(sx, sy)
			if walk.has(sc):
				props.set_cell(sc, 0, Vector2i(6 + sx, 8 + sy))


func _stamp_prop_block(props: TileMapLayer, origin: Vector2i, atlas0: Vector2i, size: Vector2i, source: int = 1) -> void:
	for y in range(size.y):
		for x in range(size.x):
			var cell := origin + Vector2i(x, y)
			if _in_bounds(cell):
				props.set_cell(cell, source, atlas0 + Vector2i(x, y))


func _build_desert() -> void:
	var ts: TileSet = load(DESERT_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts
	var walk: Dictionary = {}

	# Organic dune basins (soft disks), then authored mesa stamps on top.
	_fill_sand_disk(ground, walk, Vector2i(30, 22), 14.0)
	_fill_sand_disk(ground, walk, Vector2i(16, 16), 8.5)
	_fill_sand_disk(ground, walk, Vector2i(44, 16), 8.5)
	_fill_sand_disk(ground, walk, Vector2i(18, 30), 7.0)
	_fill_sand_disk(ground, walk, Vector2i(42, 30), 7.0)
	_fill_sand_disk(ground, walk, Vector2i(30, 36), 6.5)
	_fill_sand_disk(ground, walk, Vector2i(30, 10), 6.0)

	# Mesa plateaus (complete Ground modules) — overlapping for irregular skyline.
	for origin in [
		Vector2i(12, 12), Vector2i(15, 14),
		Vector2i(42, 12), Vector2i(39, 15),
		Vector2i(26, 8), Vector2i(29, 9),
		Vector2i(14, 26), Vector2i(40, 26),
	]:
		_stamp_mesa(ground, walls, walk, origin)

	_paint_desert_cliff_rim(walls, walk)
	# Ensure walk cells never keep wall tiles.
	for cell: Vector2i in walk.keys():
		if walls.get_cell_source_id(cell) >= 0:
			walls.erase_cell(cell)

	_stamp_temple(ground, walls, props, walk, Vector2i(27, 8))

	# Multi-tile Props.png stamps (source 1) — full columns, not 1×1 fragments.
	_stamp_prop_block(props, Vector2i(22, 10), Vector2i(0, 0), Vector2i(2, 6), 1) # tall obelisk
	_stamp_prop_block(props, Vector2i(36, 10), Vector2i(2, 0), Vector2i(2, 6), 1) # rounded pillar
	_stamp_prop_block(props, Vector2i(10, 20), Vector2i(4, 4), Vector2i(2, 4), 1) # broken pillar
	_stamp_prop_block(props, Vector2i(48, 20), Vector2i(6, 4), Vector2i(2, 3), 1) # urn cluster
	_stamp_prop_block(props, Vector2i(8, 28), Vector2i(0, 16), Vector2i(4, 4), 1) # dead tree
	_stamp_prop_block(props, Vector2i(46, 28), Vector2i(4, 16), Vector2i(3, 4), 1) # small dead tree

	# Ground-atlas flora (source 0) near rims only.
	var flora: Array = [
		Vector2i(10, 14), Vector2i(11, 14), Vector2i(12, 14),
		Vector2i(10, 15), Vector2i(11, 15), Vector2i(7, 15),
		Vector2i(8, 16), Vector2i(6, 16), Vector2i(12, 16),
	]
	var cx := int(W / 2)
	_place_props_wall_aligned(props, walk, walls, flora, 0, 34, _keepouts(cx))
	# Authored cactus clusters
	for spot in [
		Vector2i(12, 18), Vector2i(14, 20), Vector2i(11, 22),
		Vector2i(46, 18), Vector2i(48, 21), Vector2i(45, 24),
		Vector2i(20, 32), Vector2i(40, 32), Vector2i(24, 28), Vector2i(36, 28),
	]:
		if walk.has(spot) and props.get_cell_source_id(spot) < 0:
			props.set_cell(spot, 0, Vector2i(10 + _hash(spot) % 3, 14))

	var hostiles := [
		{"name": "CragYeti", "type": "trpg_crag_yeti", "pos": _tile_pos(Vector2i(14, 20))},
		{"name": "WerewolfStalker", "type": "trpg_werewolf_stalker", "pos": _tile_pos(Vector2i(46, 20))},
		{"name": "Cockatrice", "type": "trpg_lacerating_cockatrice", "pos": _tile_pos(Vector2i(30, 12))},
		{"name": "DesertOrc", "type": "trpg_orc", "pos": _tile_pos(Vector2i(20, 28))},
		{"name": "DesertArcher", "type": "trpg_archer", "pos": _tile_pos(Vector2i(40, 18))},
	]
	_write_map({
		"root": "desert",
		"out": "res://source/common/gameplay/maps/maps/desert/desert.tscn",
		"tileset": DESERT_TS,
		"bg": "Color(0.12, 0.08, 0.06, 1)",
		"modulate": "Color(1.05, 0.96, 0.82, 1)",
		"music": "res://assets/audio/music/lost_woods.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"hostiles": hostiles,
		"entrance": _tile_pos(Vector2i(cx, H - 6)),
		"portal": _tile_pos(Vector2i(cx, H - 3)),
		"entrance_id": 25,
		"portal_id": 125,
		"portal_color": "Color(0.53, 0.43, 0, 1)",
		"walk_count": walk.size(),
		"wall_count": walls.get_used_cells().size(),
		"prop_count": props.get_used_cells().size(),
		"lights": (
			"\n[node name=\"SunGlow\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(480, 200)\ncolor = Color(1, 0.92, 0.6, 1)\nenergy = 0.85\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 3.8\n"
			+ "\n[node name=\"TempleGlow\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(480, 200)\ncolor = Color(0.45, 0.75, 1, 1)\nenergy = 0.65\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.8\n"
			+ "\n[node name=\"OasisGlowW\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(220, 300)\ncolor = Color(1, 0.85, 0.5, 1)\nenergy = 0.45\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.5\n"
			+ "\n[node name=\"OasisGlowE\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(740, 300)\ncolor = Color(1, 0.85, 0.5, 1)\nenergy = 0.45\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.5\n"
		),
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [str(_tile_pos(Vector2i(cx, H - 7)).x), str(_tile_pos(Vector2i(cx, H - 7)).y)]
		),
	})


# --- Fire Forge -------------------------------------------------------------

func _build_fire_forge() -> void:
	## Structure = Mining Cave craft (authored Fungus wall stamps).
	## Accent layer = Fire Forge pack (barrels / framed vents) + hot lighting.
	var ts: TileSet = load(MINE_TS)
	var accent_ts: TileSet = load(FORGE_ACCENT_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts
	var accent := TileMapLayer.new()
	accent.tile_set = accent_ts
	var walk: Dictionary = {}

	_stamp_mine_room(ground, walls, walk, Vector2i(4, 8), STAMP_DIR + "fungus_square.txt")
	_stamp_mine_room(ground, walls, walk, Vector2i(38, 8), STAMP_DIR + "fungus_square.txt")
	_stamp_mine_room(ground, walls, walk, Vector2i(21, 4), STAMP_DIR + "fungus_tall.txt")
	_stamp_mine_room(ground, walls, walk, Vector2i(18, 26), STAMP_DIR + "fungus_wide.txt")

	_carve_mine_corridor(ground, walls, walk, Vector2i(20, 14), Vector2i(24, 14), 3)
	_carve_mine_corridor(ground, walls, walk, Vector2i(36, 14), Vector2i(40, 14), 3)
	_carve_mine_corridor(ground, walls, walk, Vector2i(29, 18), Vector2i(29, 28), 3)
	_carve_mine_corridor(ground, walls, walk, Vector2i(29, 38), Vector2i(29, 42), 3)

	# Strip walls that landed on open floor with 4 walk neighbors.
	for cell: Vector2i in walk.keys():
		if walls.get_cell_source_id(cell) < 0:
			continue
		var n := 0
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if walk.has(cell + d):
				n += 1
		if n >= 4:
			walls.erase_cell(cell)

	# Mine rock props (source 4 on mining tileset) — wall-aligned.
	var rock_spots: Array = [
		Vector2i(8, 10), Vector2i(14, 10), Vector2i(44, 10), Vector2i(50, 10),
		Vector2i(24, 8), Vector2i(34, 8), Vector2i(22, 30), Vector2i(36, 30),
		Vector2i(10, 18), Vector2i(48, 18), Vector2i(26, 32), Vector2i(32, 32),
	]
	for spot in rock_spots:
		if walk.has(spot) and walls.get_cell_source_id(spot) < 0:
			props.set_cell(spot, 4, Vector2i(0 + (_hash(spot) % 3) * 2, 1))

	# Fire-forge accent props — barrels/crates only (no orange lava slabs).
	for spot in [Vector2i(12, 14), Vector2i(46, 14), Vector2i(28, 12), Vector2i(30, 16), Vector2i(24, 30), Vector2i(34, 30)]:
		if walk.has(spot) and walls.get_cell_source_id(spot) < 0:
			accent.set_cell(spot, 0, Vector2i(8, 16)) # barrel
	for spot in [Vector2i(10, 16), Vector2i(48, 16), Vector2i(26, 28)]:
		if walk.has(spot) and walls.get_cell_source_id(spot) < 0:
			accent.set_cell(spot, 0, Vector2i(10, 16)) # crate

	var cx := int(W / 2)
	var hostiles := [
		{"name": "DemonA", "type": "trpg_demon_a", "pos": _tile_pos(Vector2i(12, 12))},
		{"name": "BloodMonster", "type": "trpg_blood_monster_a", "pos": _tile_pos(Vector2i(46, 12))},
		{"name": "EliteOrc", "type": "trpg_elite_orc", "pos": _tile_pos(Vector2i(30, 10))},
		{"name": "ConjuringOni", "type": "trpg_conjuring_oni", "pos": _tile_pos(Vector2i(28, 16))},
		{"name": "UmberHulk", "type": "trpg_umber_hulk", "pos": _tile_pos(Vector2i(30, 32))},
	]
	_write_map({
		"root": "fire_forge",
		"out": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
		"tileset": MINE_TS,
		"accent_tileset": FORGE_ACCENT_TS,
		"accent_b64": _b64(accent),
		"bg": "Color(0.05, 0.02, 0.02, 1)",
		"modulate": "Color(0.92, 0.55, 0.42, 1)",
		"music": "res://assets/audio/music/shadow_temple.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"hostiles": hostiles,
		"entrance": _tile_pos(Vector2i(cx, H - 6)),
		"portal": _tile_pos(Vector2i(cx, H - 3)),
		"entrance_id": 26,
		"portal_id": 126,
		"portal_color": "Color(0.74, 0.25, 0, 1)",
		"walk_count": walk.size(),
		"wall_count": walls.get_used_cells().size(),
		"prop_count": props.get_used_cells().size() + accent.get_used_cells().size(),
		"lights": (
			"\n[node name=\"ForgeGlowW\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(208, 240)\ncolor = Color(1, 0.4, 0.1, 1)\nenergy = 1.55\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.6\n"
			+ "\n[node name=\"ForgeGlowE\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(752, 240)\ncolor = Color(1, 0.38, 0.08, 1)\nenergy = 1.55\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.6\n"
			+ "\n[node name=\"AnvilGlow\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(480, 180)\ncolor = Color(1, 0.48, 0.15, 1)\nenergy = 1.35\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.3\n"
			+ "\n[node name=\"StagingGlow\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(480, 520)\ncolor = Color(1, 0.5, 0.2, 1)\nenergy = 1.0\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.9\n"
		),
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [str(_tile_pos(Vector2i(cx, H - 7)).x), str(_tile_pos(Vector2i(cx, H - 7)).y)]
		),
	})


# --- Sewers -----------------------------------------------------------------

func _build_sewers() -> void:
	## Structure = Mining Cave craft; identity from green modulate + Pixel Dungeon accents.
	var ts: TileSet = load(MINE_TS)
	var accent_ts: TileSet = load(SEWERS_ACCENT_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts
	var accent := TileMapLayer.new()
	accent.tile_set = accent_ts
	var walk: Dictionary = {}

	_stamp_mine_room(ground, walls, walk, Vector2i(4, 6), STAMP_DIR + "fungus_square.txt")
	_stamp_mine_room(ground, walls, walk, Vector2i(38, 6), STAMP_DIR + "fungus_square.txt")
	_stamp_mine_room(ground, walls, walk, Vector2i(18, 4), STAMP_DIR + "fungus_wide.txt")
	_stamp_mine_room(ground, walls, walk, Vector2i(20, 24), STAMP_DIR + "fungus_tall.txt")

	_carve_mine_corridor(ground, walls, walk, Vector2i(20, 12), Vector2i(24, 12), 3)
	_carve_mine_corridor(ground, walls, walk, Vector2i(36, 12), Vector2i(40, 12), 3)
	_carve_mine_corridor(ground, walls, walk, Vector2i(29, 16), Vector2i(29, 26), 3)
	_carve_mine_corridor(ground, walls, walk, Vector2i(29, 36), Vector2i(29, 42), 3)

	for cell: Vector2i in walk.keys():
		if walls.get_cell_source_id(cell) < 0:
			continue
		var n := 0
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if walk.has(cell + d):
				n += 1
		if n >= 4:
			walls.erase_cell(cell)

	# Darker "wet" channel through the hall (still dirt family, lower luminance picks).
	var wet: Array = [Vector2i(6, 15), Vector2i(7, 16), Vector2i(9, 16), Vector2i(10, 13)]
	for x in range(22, 38):
		for y in [18, 19]:
			var cell := Vector2i(x, y)
			if walk.has(cell):
				ground.set_cell(cell, 0, _pick(wet, cell))

	var rock_spots: Array = [
		Vector2i(8, 10), Vector2i(14, 12), Vector2i(44, 10), Vector2i(50, 12),
		Vector2i(24, 8), Vector2i(34, 28), Vector2i(12, 16), Vector2i(46, 16),
	]
	for spot in rock_spots:
		if walk.has(spot) and walls.get_cell_source_id(spot) < 0:
			props.set_cell(spot, 4, Vector2i(2, 1))

	# Pixel Dungeon accents — torches/webs/bones on wall-adjacent cells only.
	for x in [22, 26, 30, 34]:
		var c := Vector2i(x, 17)
		if walk.has(c):
			accent.set_cell(c, 0, Vector2i(0, 9))
	for spot in [Vector2i(10, 10), Vector2i(14, 10), Vector2i(46, 10), Vector2i(50, 10), Vector2i(24, 28), Vector2i(34, 30)]:
		if walk.has(spot):
			accent.set_cell(spot, 0, Vector2i(4, 6)) # web
	for spot in [Vector2i(12, 14), Vector2i(48, 14), Vector2i(28, 30)]:
		if walk.has(spot):
			accent.set_cell(spot, 0, Vector2i(8, 6)) # bones
	if walk.has(Vector2i(10, 14)):
		accent.set_cell(Vector2i(10, 14), 0, Vector2i(0, 8))
	if walk.has(Vector2i(48, 14)):
		accent.set_cell(Vector2i(48, 14), 0, Vector2i(1, 8))
	# Door props only at corridor mouths that still touch a wall tile.
	for door_origin in [Vector2i(28, 24), Vector2i(22, 12), Vector2i(36, 12)]:
		var touches_wall := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if walls.get_cell_source_id(door_origin + d) >= 0:
				touches_wall = true
		if not touches_wall:
			continue
		if walk.has(door_origin):
			accent.set_cell(door_origin, 0, Vector2i(6, 6))
		if walk.has(door_origin + Vector2i.RIGHT):
			accent.set_cell(door_origin + Vector2i.RIGHT, 0, Vector2i(7, 6))

	var cx := int(W / 2)
	var hostiles := [
		{"name": "AcidOoze", "type": "trpg_acid_ooze", "pos": _tile_pos(Vector2i(12, 12))},
		{"name": "CarrionCrawler", "type": "trpg_carrion_crawler", "pos": _tile_pos(Vector2i(46, 12))},
		{"name": "SewerSlime", "type": "trpg_slime", "pos": _tile_pos(Vector2i(28, 20))},
		{"name": "SewerBat", "type": "trpg_bat", "pos": _tile_pos(Vector2i(30, 10))},
		{"name": "SewerSkeleton", "type": "trpg_skeleton", "pos": _tile_pos(Vector2i(32, 18))},
		{"name": "PoisonGorgon", "type": "trpg_poisonous_gorgon", "pos": _tile_pos(Vector2i(30, 30))},
	]
	_write_map({
		"root": "sewers",
		"out": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
		"tileset": MINE_TS,
		"accent_tileset": SEWERS_ACCENT_TS,
		"accent_b64": _b64(accent),
		"bg": "Color(0.02, 0.03, 0.03, 1)",
		"modulate": "Color(0.55, 0.78, 0.62, 1)",
		"music": "res://assets/audio/music/fungus.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"hostiles": hostiles,
		"entrance": _tile_pos(Vector2i(cx, H - 6)),
		"portal": _tile_pos(Vector2i(cx, H - 3)),
		"entrance_id": 28,
		"portal_id": 128,
		"portal_color": "Color(0, 0.53, 0.27, 1)",
		"walk_count": walk.size(),
		"wall_count": walls.get_used_cells().size(),
		"prop_count": props.get_used_cells().size() + accent.get_used_cells().size(),
		"lights": (
			"\n[node name=\"SewerLamp1\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(192, 200)\ncolor = Color(0.55, 0.95, 0.55, 1)\nenergy = 1.05\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.0\n"
			+ "\n[node name=\"SewerLamp2\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(768, 200)\ncolor = Color(0.55, 0.95, 0.55, 1)\nenergy = 1.05\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.0\n"
			+ "\n[node name=\"SewerLamp3\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(480, 320)\ncolor = Color(0.45, 0.85, 0.55, 1)\nenergy = 0.95\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.2\n"
			+ "\n[node name=\"SewerLamp4\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(480, 520)\ncolor = Color(0.5, 0.88, 0.55, 1)\nenergy = 0.85\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.7\n"
		),
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [str(_tile_pos(Vector2i(cx, H - 7)).x), str(_tile_pos(Vector2i(cx, H - 7)).y)]
		),
	})


func _write_map(cfg: Dictionary) -> void:
	var hostiles: Array = cfg.get("hostiles", [])
	var hostile_ext := ""
	var hostile_nodes := ""
	var id_map := ""
	var node_map := ""
	var i := 0
	for h in hostiles:
		var slug: String = h["type"]
		var path := "res://source/common/gameplay/characters/npc/types/trpg/%s.tres" % slug
		var ext_id := "h%d" % i
		hostile_ext += "[ext_resource type=\"Resource\" path=\"%s\" id=\"%s\"]\n" % [path, ext_id]
		var pos: Vector2 = h["pos"]
		var node_name: String = h.get("name", "Mob%d" % i)
		hostile_nodes += (
			"\n[node name=\"%s\" parent=\"ReplicatedPropsContainer\" instance=ExtResource(\"hostile\")]\n"
			+ "position = Vector2(%s, %s)\n"
			+ "enemy_data = ExtResource(\"%s\")\n"
			+ "weapon = null\n"
		) % [node_name, str(pos.x), str(pos.y), ext_id]
		if i > 0:
			id_map += ", "
			node_map += ", "
		id_map += "%d: NodePath(\"%s\")" % [i, node_name]
		node_map += "NodePath(\"%s\"): %d" % [node_name, i]
		i += 1

	var music_ext := ""
	var music_line := ""
	if cfg.has("music"):
		music_ext = "[ext_resource type=\"AudioStream\" path=\"%s\" id=\"music\"]\n" % cfg["music"]
		music_line = "music = ExtResource(\"music\")\n"

	var accent_ext := ""
	var accent_node := ""
	if cfg.has("accent_tileset") and cfg.has("accent_b64"):
		accent_ext = "[ext_resource type=\"TileSet\" path=\"%s\" id=\"3_accent\"]\n" % cfg["accent_tileset"]
		accent_node = (
			"\n[node name=\"Accent\" type=\"TileMapLayer\" parent=\"Tiles\"]\n"
			+ "y_sort_enabled = true\n"
			+ "tile_map_data = PackedByteArray(\"%s\")\n" % cfg["accent_b64"]
			+ "tile_set = ExtResource(\"3_accent\")\n"
		)

	var text := """[gd_scene format=3]

[ext_resource type=\"Script\" uid=\"uid://7mbux4mybta0\" path=\"%s\" id=\"1_map\"]
[ext_resource type=\"TileSet\" path=\"%s\" id=\"2_tiles\"]
%s%s[ext_resource type=\"Script\" uid=\"uid://wq8klpndipnu\" path=\"%s\" id=\"4_rp\"]
[ext_resource type=\"PackedScene\" uid=\"uid://b2ckixon7ryh6\" path=\"%s\" id=\"5_warper\"]
[ext_resource type=\"PackedScene\" uid=\"uid://0m5eq6iylq26\" path=\"%s\" id=\"6_portal\"]
[ext_resource type=\"Resource\" uid=\"uid://doc0umc2oovri\" path=\"%s\" id=\"7_hub\"]
[ext_resource type=\"PackedScene\" path=\"%s\" id=\"8_camp\"]
[ext_resource type=\"Texture2D\" path=\"%s\" id=\"9_glow\"]
[ext_resource type=\"PackedScene\" uid=\"uid://v32667qwpj2l\" path=\"%s\" id=\"hostile\"]
%s
[sub_resource type=\"RectangleShape2D\" id=\"WallN\"]
size = Vector2(944, 24)

[sub_resource type=\"RectangleShape2D\" id=\"WallS\"]
size = Vector2(392, 24)

[sub_resource type=\"RectangleShape2D\" id=\"WallE\"]
size = Vector2(24, 704)

[sub_resource type=\"RectangleShape2D\" id=\"WallW\"]
size = Vector2(24, 704)

[node name=\"%s\" type=\"Node2D\" node_paths=PackedStringArray(\"replicated_props_container\")]
y_sort_enabled = true
script = ExtResource(\"1_map\")
replicated_props_container = NodePath(\"ReplicatedPropsContainer\")
map_background_color = %s
%scamera_limit_left = -16
camera_limit_top = -16
camera_limit_right = 976
camera_limit_bottom = 736

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
%s
[node name=\"ArenaWalls\" type=\"StaticBody2D\" parent=\".\"]
collision_layer = 2
collision_mask = 0

[node name=\"North\" type=\"CollisionShape2D\" parent=\"ArenaWalls\"]
position = Vector2(480, 20)
shape = SubResource(\"WallN\")

[node name=\"SouthLeft\" type=\"CollisionShape2D\" parent=\"ArenaWalls\"]
position = Vector2(228, 700)
shape = SubResource(\"WallS\")

[node name=\"SouthRight\" type=\"CollisionShape2D\" parent=\"ArenaWalls\"]
position = Vector2(732, 700)
shape = SubResource(\"WallS\")

[node name=\"East\" type=\"CollisionShape2D\" parent=\"ArenaWalls\"]
position = Vector2(940, 360)
shape = SubResource(\"WallE\")

[node name=\"West\" type=\"CollisionShape2D\" parent=\"ArenaWalls\"]
position = Vector2(20, 360)
shape = SubResource(\"WallW\")

[node name=\"SceneProps\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true
%s%s
[node name=\"ReplicatedPropsContainer\" type=\"Node2D\" parent=\".\" node_paths=PackedStringArray(\"id_to_node\", \"node_to_id\")]
y_sort_enabled = true
script = ExtResource(\"4_rp\")
id_to_node = {
%s
}
node_to_id = {
%s
}
%s
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
		MAP_SCRIPT, cfg["tileset"], accent_ext, music_ext, RP_SCRIPT, WARPER, PORTAL, HUB, CAMP, GLOW, HOSTILE, hostile_ext,
		cfg["root"], cfg["bg"], music_line, cfg["modulate"],
		cfg["ground_b64"], cfg["walls_b64"], cfg["props_b64"], accent_node,
		cfg.get("lights", ""), cfg.get("camps", ""),
		id_map, node_map, hostile_nodes,
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
		" mobs=", hostiles.size()
	)
