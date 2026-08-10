extends SceneTree
## Build Desert / Fire Forge / Sewers as full authored maps:
## dense tiles + decorative GIF props + ambient critters. NO attackable NPCs.
##   godot --headless --path . -s tools/build_stub_biomes.gd

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


func _fill_disk(walk: Dictionary, center: Vector2i, radius: float) -> void:
	var r2 := int(radius * radius)
	for y in range(center.y - int(radius) - 2, center.y + int(radius) + 3):
		for x in range(center.x - int(radius) - 2, center.x + int(radius) + 3):
			var cell := Vector2i(x, y)
			if not _in_bounds(cell):
				continue
			var dx := x - center.x
			var dy := y - center.y
			var n := (_hash(cell) % 7) - 3
			if dx * dx + dy * dy <= r2 + n:
				walk[cell] = true


func _carve_rect(walk: Dictionary, a: Vector2i, b: Vector2i) -> void:
	for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
		for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
			var cell := Vector2i(x, y)
			if _in_bounds(cell):
				walk[cell] = true


func _fill_enclosed_voids(walk: Dictionary) -> void:
	var add: Array = []
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			var cell := Vector2i(x, y)
			if walk.has(cell):
				continue
			var n := 0
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if walk.has(cell + d):
					n += 1
			if n >= 3:
				add.append(cell)
	for c in add:
		walk[c] = true


func _carve_corridor(walk: Dictionary, a: Vector2i, b: Vector2i, width: int) -> void:
	var half := int(width / 2)
	var x := a.x
	var y := a.y
	while true:
		for oy in range(-half, half + 1):
			for ox in range(-half, half + 1):
				var cell := Vector2i(x + ox, y + oy)
				if _in_bounds(cell):
					walk[cell] = true
		if x == b.x and y == b.y:
			break
		if x != b.x:
			x += 1 if b.x > x else -1
		elif y != b.y:
			y += 1 if b.y > y else -1


func _paint_floors(ground: TileMapLayer, walk: Dictionary, floors: Array, source: int = 0) -> void:
	for cell: Vector2i in walk.keys():
		ground.set_cell(cell, source, _pick(floors, cell))


func _paint_wall_shell(
	walls: TileMapLayer,
	walk: Dictionary,
	wall_n: Array,
	wall_s: Array,
	wall_w: Array,
	wall_e: Array,
	wall_fill: Array,
	wall_nw: Vector2i,
	wall_ne: Vector2i,
	wall_sw: Vector2i,
	wall_se: Vector2i,
	source: int = 0,
	thickness: int = 1
) -> void:
	var candidates: Dictionary = {}
	for cell: Vector2i in walk.keys():
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			for t in range(1, thickness + 1):
				var n: Vector2i = cell + d * t
				if _in_bounds(n) and not walk.has(n):
					candidates[n] = true
	for cell: Vector2i in candidates.keys():
		var floor_n := walk.has(cell + Vector2i.UP)
		var floor_s := walk.has(cell + Vector2i.DOWN)
		var floor_w := walk.has(cell + Vector2i.LEFT)
		var floor_e := walk.has(cell + Vector2i.RIGHT)
		if not floor_n:
			floor_n = walk.has(cell + Vector2i(0, -2))
		if not floor_s:
			floor_s = walk.has(cell + Vector2i(0, 2))
		if not floor_w:
			floor_w = walk.has(cell + Vector2i(-2, 0))
		if not floor_e:
			floor_e = walk.has(cell + Vector2i(2, 0))
		var atlas: Vector2i
		if floor_s and not floor_n and not floor_w and not floor_e:
			atlas = _pick(wall_n, cell)
		elif floor_n and not floor_s and not floor_w and not floor_e:
			atlas = _pick(wall_s, cell)
		elif floor_e and not floor_w and not floor_n and not floor_s:
			atlas = _pick(wall_w, cell)
		elif floor_w and not floor_e and not floor_n and not floor_s:
			atlas = _pick(wall_e, cell)
		elif floor_s and floor_e:
			atlas = wall_nw
		elif floor_s and floor_w:
			atlas = wall_ne
		elif floor_n and floor_e:
			atlas = wall_sw
		elif floor_n and floor_w:
			atlas = wall_se
		elif floor_s:
			atlas = _pick(wall_n, cell)
		elif floor_n:
			atlas = _pick(wall_s, cell)
		elif floor_e:
			atlas = _pick(wall_w, cell)
		elif floor_w:
			atlas = _pick(wall_e, cell)
		else:
			atlas = _pick(wall_fill, cell)
		walls.set_cell(cell, source, atlas)


func _clear_walls_on_walk(walls: TileMapLayer, walk: Dictionary) -> void:
	for cell: Vector2i in walk.keys():
		if walls.get_cell_source_id(cell) >= 0:
			walls.erase_cell(cell)


func _place_prop(
	props: TileMapLayer,
	walk: Dictionary,
	walls: TileMapLayer,
	cell: Vector2i,
	atlas: Vector2i,
	source: int,
	keepout: Array,
	near_wall_only: bool = true
) -> bool:
	if not walk.has(cell) or props.get_cell_source_id(cell) >= 0:
		return false
	for k in keepout:
		if cell.distance_squared_to(k) < 16:
			return false
	if near_wall_only:
		var near := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if walls.get_cell_source_id(cell + d) >= 0:
				near = true
				break
		if not near:
			return false
	props.set_cell(cell, source, atlas)
	return true


func _stamp_prop_block(props: TileMapLayer, origin: Vector2i, atlas0: Vector2i, size: Vector2i, source: int) -> void:
	for y in range(size.y):
		for x in range(size.x):
			var cell := origin + Vector2i(x, y)
			if _in_bounds(cell):
				props.set_cell(cell, source, atlas0 + Vector2i(x, y))


func _assert_walkable(walk: Dictionary, cells: Array, label: String) -> void:
	for c in cells:
		assert(walk.has(c), "%s missing walk at %s" % [label, str(c)])


func _assert_connected(walk: Dictionary, start: Vector2i, goals: Array, label: String) -> void:
	var seen: Dictionary = {}
	var q: Array = [start]
	seen[start] = true
	var qi := 0
	while qi < q.size():
		var cur: Vector2i = q[qi]
		qi += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cur + d
			if walk.has(n) and not seen.has(n):
				seen[n] = true
				q.append(n)
	for g in goals:
		assert(seen.has(g), "%s not connected to %s from %s" % [label, str(g), str(start)])


func _carve_spine(walk: Dictionary, ground: TileMapLayer, walls: TileMapLayer, cx: int, y_start: int, y_end: int, floors: Array) -> void:
	for y in range(mini(y_start, y_end), maxi(y_start, y_end) + 1):
		for x in range(cx - 3, cx + 4):
			var cell := Vector2i(x, y)
			if not _in_bounds(cell):
				continue
			walk[cell] = true
			if walls.get_cell_source_id(cell) >= 0:
				walls.erase_cell(cell)
			ground.set_cell(cell, 0, _pick(floors, cell))


# --- Desert -----------------------------------------------------------------

const MESA_ROWS: Array[String] = [
	".WWWW.",
	"WGGGGW",
	"WGGGGW",
	"WGGGGW",
	"WGGGGW",
	".WWWW.",
]


func _stamp_mesa(ground: TileMapLayer, walls: TileMapLayer, walk: Dictionary, origin: Vector2i, sand: Array) -> void:
	for y in range(6):
		var row: String = MESA_ROWS[y]
		for x in range(6):
			var ch := row[x]
			var cell := origin + Vector2i(x, y)
			if not _in_bounds(cell) or ch == ".":
				continue
			var atlas := Vector2i(x, y)
			if ch == "G":
				ground.set_cell(cell, 0, _pick(sand, cell))
				walk[cell] = true
				if walls.get_cell_source_id(cell) >= 0:
					walls.erase_cell(cell)
			else:
				walls.set_cell(cell, 0, atlas)
				walk.erase(cell)
				if ground.get_cell_source_id(cell) >= 0:
					ground.erase_cell(cell)


func _stamp_temple(ground: TileMapLayer, walls: TileMapLayer, props: TileMapLayer, walk: Dictionary, origin: Vector2i, sand: Array) -> void:
	for ty in range(8):
		for tx in range(6):
			var cell := origin + Vector2i(tx, ty)
			if not _in_bounds(cell):
				continue
			var atlas := Vector2i(tx, 7 + ty)
			var is_shell := tx == 0 or tx == 5 or ty <= 1 or ty == 7
			var is_inner := (ty >= 2 and ty <= 5) and (tx == 1 or tx == 4)
			var is_door := ty >= 5 and tx >= 2 and tx <= 3
			if is_door:
				ground.set_cell(cell, 0, Vector2i(2, 2))
				walk[cell] = true
				if walls.get_cell_source_id(cell) >= 0:
					walls.erase_cell(cell)
			elif is_shell or is_inner:
				walls.set_cell(cell, 0, atlas)
				walk.erase(cell)
				if ground.get_cell_source_id(cell) >= 0:
					ground.erase_cell(cell)
			else:
				ground.set_cell(cell, 0, _pick(sand, cell))
				walk[cell] = true
				if walls.get_cell_source_id(cell) >= 0:
					walls.erase_cell(cell)
	var stair := origin + Vector2i(1, 6)
	for sy in range(3):
		for sx in range(3):
			var sc := stair + Vector2i(sx, sy)
			if walk.has(sc):
				props.set_cell(sc, 0, Vector2i(6 + sx, 8 + sy))


func _build_desert() -> void:
	W = 72
	H = 54
	var cx := 36

	var ts: TileSet = load(DESERT_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts
	var walk: Dictionary = {}

	# Clean sand ONLY — low-variance ripple tiles (no rock/rubble atlases).
	var sand: Array = [
		Vector2i(7, 1), Vector2i(2, 3), Vector2i(1, 2), Vector2i(4, 2),
		Vector2i(3, 1), Vector2i(2, 1), Vector2i(3, 2), Vector2i(2, 2),
		Vector2i(3, 3), Vector2i(7, 3), Vector2i(7, 2), Vector2i(8, 3),
	]

	# Organic dune basin
	_fill_disk(walk, Vector2i(cx, 26), 20.0)
	_fill_disk(walk, Vector2i(18, 18), 11.0)
	_fill_disk(walk, Vector2i(54, 18), 11.0)
	_fill_disk(walk, Vector2i(16, 36), 10.0)
	_fill_disk(walk, Vector2i(56, 36), 10.0)
	_fill_disk(walk, Vector2i(cx, 12), 9.0)
	_fill_disk(walk, Vector2i(cx, 42), 9.0)
	_carve_rect(walk, Vector2i(cx - 5, 44), Vector2i(cx + 5, 51))
	_carve_corridor(walk, Vector2i(cx, 42), Vector2i(cx, 49), 4)

	_paint_floors(ground, walk, sand, 0)

	var cliff_n: Array = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	var cliff_s: Array = [Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(1, 5)]
	var cliff_w: Array = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4)]
	var cliff_e: Array = [Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4)]
	var cliff_fill: Array = [Vector2i(7, 5), Vector2i(8, 5), Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 6)]
	_paint_wall_shell(
		walls, walk, cliff_n, cliff_s, cliff_w, cliff_e, cliff_fill,
		Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 5), Vector2i(5, 5), 0, 1
	)
	_clear_walls_on_walk(walls, walk)

	# Two mesas only — keep open sand readable
	for origin in [Vector2i(12, 14), Vector2i(50, 14)]:
		_stamp_mesa(ground, walls, walk, origin, sand)
	_paint_floors(ground, walk, sand, 0)
	_clear_walls_on_walk(walls, walk)

	_stamp_temple(ground, walls, props, walk, Vector2i(33, 8), sand)
	_paint_floors(ground, walk, sand, 0)
	_clear_walls_on_walk(walls, walk)

	# Sparse landmark multi-tile props (Props source 1): obelisks, dead trees, urns, bones
	_stamp_prop_block(props, Vector2i(24, 9), Vector2i(0, 0), Vector2i(2, 7), 1)
	_stamp_prop_block(props, Vector2i(44, 9), Vector2i(2, 0), Vector2i(2, 7), 1)
	_stamp_prop_block(props, Vector2i(10, 20), Vector2i(4, 4), Vector2i(2, 4), 1)
	_stamp_prop_block(props, Vector2i(58, 20), Vector2i(6, 4), Vector2i(2, 3), 1)
	_stamp_prop_block(props, Vector2i(8, 32), Vector2i(0, 16), Vector2i(4, 4), 1)
	_stamp_prop_block(props, Vector2i(58, 32), Vector2i(4, 16), Vector2i(3, 4), 1)
	_stamp_prop_block(props, Vector2i(20, 38), Vector2i(0, 12), Vector2i(5, 3), 1)
	_stamp_prop_block(props, Vector2i(48, 38), Vector2i(6, 12), Vector2i(3, 3), 1)

	# Oasis lanterns only (single-column roofs — 2×2 stamped red+blue checkerboard)
	for spot in [Vector2i(14, 40), Vector2i(58, 40), Vector2i(cx - 8, 42), Vector2i(cx + 8, 42)]:
		if walk.has(spot):
			props.set_cell(spot, 3, Vector2i(1, 4))  # stone lantern
	# Single-column roof accents away from bone props
	_stamp_prop_block(props, Vector2i(14, 38), Vector2i(2, 1), Vector2i(1, 2), 3)  # red only
	_stamp_prop_block(props, Vector2i(58, 38), Vector2i(3, 1), Vector2i(1, 2), 3)  # blue only

	var entrance := Vector2i(cx, 47)
	var portal := Vector2i(cx, 50)
	var keepout: Array = [entrance, portal, Vector2i(cx, 46), Vector2i(cx, 48)]

	# MAX 18 authored cacti near walls only (atlas 10-12, 14)
	var cactus_spots: Array = [
		Vector2i(14, 22), Vector2i(16, 24), Vector2i(12, 26), Vector2i(18, 28),
		Vector2i(58, 22), Vector2i(56, 24), Vector2i(60, 26), Vector2i(54, 28),
		Vector2i(22, 38), Vector2i(50, 38), Vector2i(26, 32), Vector2i(46, 32),
		Vector2i(20, 16), Vector2i(52, 16), Vector2i(28, 20), Vector2i(44, 20),
		Vector2i(24, 42), Vector2i(48, 42),
	]
	var cactus_placed := 0
	for spot in cactus_spots:
		if cactus_placed >= 18:
			break
		var atlas_y := 14
		var atlas_x := 10 + _hash(spot) % 3
		if _place_prop(props, walk, walls, spot, Vector2i(atlas_x, atlas_y), 0, keepout, true):
			cactus_placed += 1

	_assert_walkable(walk, [entrance, portal, Vector2i(cx, 46)], "desert spawn")
	_assert_connected(walk, entrance, [portal, Vector2i(cx, 14), Vector2i(18, 24), Vector2i(54, 24)], "desert")

	# Critters on open sand only — away from mesas, cacti, and temple props.
	var critters := [
		{"name": "Stag1", "frames": "critter_stag", "pos": _tile_pos(Vector2i(28, 28)), "scale": 0.85, "wander_radius": 36.0},
		{"name": "Boar1", "frames": "critter_boar", "pos": _tile_pos(Vector2i(44, 30)), "scale": 1.0, "wander_radius": 36.0},
		{"name": "Badger1", "frames": "critter_badger", "pos": _tile_pos(Vector2i(24, 36)), "scale": 0.95, "wander_radius": 32.0},
		{"name": "Wolf1", "frames": "critter_wolf", "pos": _tile_pos(Vector2i(48, 34)), "scale": 0.75, "wander_radius": 36.0},
	]
	var decos := [
		{"name": "TempleCandleL", "frames": "deco_candle_b", "pos": _tile_pos(Vector2i(32, 14)), "scale": 1.4, "light": 0.7, "color": "Color(0.55, 0.75, 1, 1)"},
		{"name": "TempleCandleR", "frames": "deco_candle_b", "pos": _tile_pos(Vector2i(39, 14)), "scale": 1.4, "light": 0.7, "color": "Color(0.55, 0.75, 1, 1)"},
		{"name": "OasisTorchL", "frames": "deco_torch", "pos": _tile_pos(Vector2i(22, 42)), "scale": 1.35, "light": 0.85, "color": "Color(1, 0.75, 0.35, 1)"},
		{"name": "OasisTorchR", "frames": "deco_torch", "pos": _tile_pos(Vector2i(50, 42)), "scale": 1.35, "light": 0.85, "color": "Color(1, 0.75, 0.35, 1)"},
	]

	_write_map({
		"root": "desert",
		"out": "res://source/common/gameplay/maps/maps/desert/desert.tscn",
		"tileset": DESERT_TS,
		"bg": "Color(0.1, 0.07, 0.05, 1)",
		"modulate": "Color(0.96, 0.9, 0.78, 1)",
		"music": "res://assets/audio/music/lost_woods.ogg",
		"ground_b64": _b64(ground),
		"walls_b64": _b64(walls),
		"props_b64": _b64(props),
		"critters": critters,
		"decos": decos,
		"entrance": _tile_pos(entrance),
		"portal": _tile_pos(portal),
		"entrance_id": 25,
		"portal_id": 125,
		"portal_color": "Color(0.53, 0.43, 0, 1)",
		"walk_count": walk.size(),
		"wall_count": walls.get_used_cells().size(),
		"prop_count": props.get_used_cells().size(),
		"cam_right": W * 16 + 16,
		"cam_bottom": int(_tile_pos(portal).y) + 320,
		"lights": (
			"\n[node name=\"SunGlow\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(576, 300)\ncolor = Color(1, 0.92, 0.62, 1)\nenergy = 0.4\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 3.6\n"
			+ "\n[node name=\"TempleGlow\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(576, 240)\ncolor = Color(0.45, 0.75, 1, 1)\nenergy = 0.5\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.6\n"
		),
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [str(_tile_pos(Vector2i(cx, 46)).x), str(_tile_pos(Vector2i(cx, 46)).y)]
		),
	})


# --- Fire Forge -------------------------------------------------------------
# AAA authored halls: discrete rooms + short links (scaled from 64×48 polish).
# Do NOT merge everything into one plaza — solid rock between chambers is the look.

func _paint_lava_rect(
	ground: TileMapLayer,
	walk: Dictionary,
	walls: TileMapLayer,
	a: Vector2i,
	b: Vector2i,
	lavas: Array,
	source: int = 0
) -> void:
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell := Vector2i(x, y)
			if not _in_bounds(cell):
				continue
			walk.erase(cell)
			var on_rim := x == x0 or x == x1 or y == y0 or y == y1
			var atlas: Vector2i = _pick(lavas, cell)
			# Prefer a slightly textured neighbor for rim so pools aren't a flat stamp.
			if on_rim and lavas.size() > 0:
				atlas = Vector2i(atlas.x + 1, atlas.y) if atlas.x < 6 else atlas
			ground.set_cell(cell, source, atlas)
			if walls.get_cell_source_id(cell) >= 0:
				walls.erase_cell(cell)


func _build_fire_forge() -> void:
	W = 128
	H = 96
	var cx := 64

	var ts: TileSet = load(FORGE_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts
	var walk: Dictionary = {}

	# ONE solid floor tile from lava pack — mixing platform variants stripes the halls.
	var floors: Array = [Vector2i(5, 5)]
	# Solid lava FILL (1,11) — not edge-banded surface tiles (those stack into fake sheet strips).
	var lavas: Array = [Vector2i(1, 11)]
	# DG Fire (source 3) — proper 16×16 wall shell, not lava-pack cliff props.
	var wall_n: Array = [Vector2i(1, 0), Vector2i(2, 0)]
	var wall_s: Array = [Vector2i(1, 2), Vector2i(2, 2)]
	var wall_w: Array = [Vector2i(0, 1)]
	var wall_e: Array = [Vector2i(3, 1)]
	var wall_fill: Array = [Vector2i(1, 1), Vector2i(2, 1)]

	# Discrete chambers (2× of the polished 64×48 layout) — leave rock between.
	_carve_rect(walk, Vector2i(44, 68), Vector2i(82, 88))  # staging
	_carve_rect(walk, Vector2i(48, 56), Vector2i(78, 72))
	_carve_rect(walk, Vector2i(12, 16), Vector2i(44, 48))  # west foundry
	_carve_rect(walk, Vector2i(16, 20), Vector2i(40, 44))
	_carve_rect(walk, Vector2i(82, 16), Vector2i(114, 48))  # east foundry
	_carve_rect(walk, Vector2i(86, 20), Vector2i(110, 44))
	_carve_rect(walk, Vector2i(44, 12), Vector2i(82, 44))  # anvil / machine hall
	_carve_rect(walk, Vector2i(52, 16), Vector2i(74, 40))
	_carve_rect(walk, Vector2i(28, 40), Vector2i(44, 56))  # west link
	_carve_rect(walk, Vector2i(82, 40), Vector2i(98, 56))  # east link
	_carve_corridor(walk, Vector2i(cx, 68), Vector2i(cx, 44), 5)
	_carve_corridor(walk, Vector2i(40, 32), Vector2i(56, 32), 4)
	_carve_corridor(walk, Vector2i(70, 32), Vector2i(88, 32), 4)
	_carve_corridor(walk, Vector2i(cx, 88), Vector2i(cx, 92), 4)
	_fill_enclosed_voids(walk)

	_paint_floors(ground, walk, floors, 0)

	_paint_wall_shell(
		walls, walk, wall_n, wall_s, wall_w, wall_e, wall_fill,
		Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 2), Vector2i(3, 2), 3, 2
	)
	_clear_walls_on_walk(walls, walk)

	# Lava AFTER walls so pits don't get brick shells (that looked like sheet stamps).
	_paint_lava_rect(ground, walk, walls, Vector2i(18, 28), Vector2i(26, 34), lavas, 0)
	_paint_lava_rect(ground, walk, walls, Vector2i(100, 28), Vector2i(108, 34), lavas, 0)
	_paint_lava_rect(ground, walk, walls, Vector2i(56, 20), Vector2i(70, 24), lavas, 0)
	# Stone bridges restore connectivity (same solid floor tile).
	for x in range(20, 25):
		var cell := Vector2i(x, 31)
		walk[cell] = true
		ground.set_cell(cell, 0, Vector2i(5, 5))
		if walls.get_cell_source_id(cell) >= 0:
			walls.erase_cell(cell)
	for x in range(102, 107):
		var cell2 := Vector2i(x, 31)
		walk[cell2] = true
		ground.set_cell(cell2, 0, Vector2i(5, 5))
		if walls.get_cell_source_id(cell2) >= 0:
			walls.erase_cell(cell2)
	for x in range(56, 71):
		var cell3 := Vector2i(x, 22)
		if x == cx or x == cx - 1 or x == cx + 1:
			walk[cell3] = true
			ground.set_cell(cell3, 0, Vector2i(5, 5))
			if walls.get_cell_source_id(cell3) >= 0:
				walls.erase_cell(cell3)

	var entrance := Vector2i(cx, 84)
	var portal := Vector2i(cx, 90)
	var keepout: Array = [entrance, portal, Vector2i(cx, 83), Vector2i(cx, 86)]

	# Sparse 16×16 transparent rocks / chests only (source 2 — never opaque sheet cells).
	var decor: Array = [Vector2i(1, 0), Vector2i(2, 0)]
	var placed := 0
	var cells: Array = walk.keys()
	cells.sort_custom(func(a, b): return _hash(a) < _hash(b))
	for cell: Vector2i in cells:
		if placed >= 28:
			break
		if _hash(cell) % 7 != 0:
			continue
		if _place_prop(props, walk, walls, cell, _pick(decor, cell), 2, keepout, true):
			placed += 1
	# Landmark chests (single 16×16 tile)
	for spot in [Vector2i(24, 24), Vector2i(100, 24), Vector2i(cx, 28), Vector2i(56, 70), Vector2i(72, 70)]:
		_place_prop(props, walk, walls, spot, Vector2i(0, 0), 2, keepout, false)

	_assert_walkable(walk, [entrance, portal, Vector2i(cx, 83)], "forge spawn")
	_assert_connected(walk, entrance, [portal, Vector2i(28, 28), Vector2i(96, 28), Vector2i(cx, 28), Vector2i(36, 48), Vector2i(90, 48)], "forge")

	var decos: Array = []
	var torch_spots: Array = [
		Vector2i(20, 20), Vector2i(36, 20), Vector2i(20, 40), Vector2i(36, 40),
		Vector2i(90, 20), Vector2i(106, 20), Vector2i(90, 40), Vector2i(106, 40),
		Vector2i(52, 16), Vector2i(72, 16), Vector2i(52, 40), Vector2i(72, 40),
		Vector2i(48, 72), Vector2i(76, 72), Vector2i(56, 56), Vector2i(72, 56),
		Vector2i(cx - 6, 80), Vector2i(cx + 6, 80),
	]
	var ti := 0
	for spot in torch_spots:
		if not walk.has(spot):
			continue
		ti += 1
		decos.append({
			"name": "ForgeTorch%d" % ti,
			"frames": "deco_forge_torch",
			"pos": _tile_pos(spot),
			"scale": 1.5,
			"light": 1.2,
			"color": "Color(1, 0.45, 0.12, 1)",
		})

	_write_map({
		"root": "fire_forge",
		"out": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
		"tileset": FORGE_TS,
		"bg": "Color(0.03, 0.01, 0.015, 1)",
		"modulate": "Color(0.95, 0.62, 0.48, 1)",
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
		"cam_bottom": int(_tile_pos(portal).y) + 320,
		"lights": (
			"\n[node name=\"ForgeCore\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(1024, 400)\ncolor = Color(1, 0.42, 0.1, 1)\nenergy = 1.45\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.8\n"
			+ "\n[node name=\"WestFoundry\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(448, 512)\ncolor = Color(1, 0.38, 0.08, 1)\nenergy = 1.35\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.4\n"
			+ "\n[node name=\"EastFoundry\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(1600, 512)\ncolor = Color(1, 0.38, 0.08, 1)\nenergy = 1.35\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.4\n"
			+ "\n[node name=\"StagingGlow\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(1024, 1200)\ncolor = Color(1, 0.5, 0.18, 1)\nenergy = 1.0\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.0\n"
			+ "\n[node name=\"LavaWest\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(320, 496)\ncolor = Color(1, 0.3, 0.05, 1)\nenergy = 1.25\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.8\n"
			+ "\n[node name=\"LavaEast\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(1696, 496)\ncolor = Color(1, 0.3, 0.05, 1)\nenergy = 1.25\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.8\n"
		),
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [str(_tile_pos(Vector2i(cx, 83)).x), str(_tile_pos(Vector2i(cx, 83)).y)]
		),
	})


# --- Sewers -----------------------------------------------------------------
# Hand-crafted cisterns + channel — NOT a wall-noise field.

func _build_sewers() -> void:
	W = 128
	H = 96
	var cx := 64

	var ts: TileSet = load(SEWERS_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts
	var walk: Dictionary = {}

	var floors: Array = [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
	]
	var wall_n: Array = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
	var wall_s: Array = [Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4)]
	var wall_w: Array = [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3)]
	var wall_e: Array = [Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3)]
	var wall_fill: Array = [Vector2i(6, 0), Vector2i(7, 0), Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 0), Vector2i(8, 1)]

	# Staging + west/east cisterns + north junction + alcoves (2× polished layout)
	_carve_rect(walk, Vector2i(44, 68), Vector2i(82, 86))
	_carve_rect(walk, Vector2i(48, 60), Vector2i(78, 76))
	_carve_rect(walk, Vector2i(8, 12), Vector2i(44, 44))
	_carve_rect(walk, Vector2i(12, 16), Vector2i(40, 40))
	_carve_rect(walk, Vector2i(84, 12), Vector2i(118, 40))
	_carve_rect(walk, Vector2i(88, 16), Vector2i(114, 36))
	_carve_rect(walk, Vector2i(36, 12), Vector2i(90, 36))
	_carve_rect(walk, Vector2i(32, 32), Vector2i(94, 60))
	_carve_rect(walk, Vector2i(40, 36), Vector2i(56, 52))  # west alcove
	_carve_rect(walk, Vector2i(72, 40), Vector2i(88, 56))  # east alcove
	_carve_corridor(walk, Vector2i(cx, 68), Vector2i(cx, 56), 4)
	_carve_corridor(walk, Vector2i(44, 28), Vector2i(36, 28), 4)
	_carve_corridor(walk, Vector2i(84, 28), Vector2i(90, 28), 4)
	_carve_corridor(walk, Vector2i(cx, 86), Vector2i(cx, 92), 4)
	_fill_disk(walk, Vector2i(24, 28), 10.0)
	_fill_disk(walk, Vector2i(104, 28), 10.0)
	_fill_disk(walk, Vector2i(cx, 48), 12.0)
	_fill_enclosed_voids(walk)

	_paint_floors(ground, walk, floors, 0)
	# Drainage channel through mid hall — visual ONLY.
	# Never paint wall-fill atlas (6,1)/(7,1) on Ground: those tiles have collision and
	# created the invisible horizontal walls across the cistern.
	for x in range(36, 92):
		for y in [44, 45]:
			var cell := Vector2i(x, y)
			if walk.has(cell):
				ground.set_cell(cell, 0, Vector2i(2 + ((x + y) % 3), 2))

	_paint_wall_shell(
		walls, walk, wall_n, wall_s, wall_w, wall_e, wall_fill,
		Vector2i(0, 0), Vector2i(5, 0), Vector2i(0, 4), Vector2i(5, 4), 0, 2
	)
	_clear_walls_on_walk(walls, walk)
	_carve_spine(walk, ground, walls, cx, 84, 8, floors)

	var entrance := Vector2i(cx, 84)
	var portal := Vector2i(cx, 90)
	var keepout: Array = [entrance, portal, Vector2i(cx, 83), Vector2i(cx, 86)]

	# Sparse wall décor only — bones/skulls/slime (never door or hatch tiles).
	var decor: Array = [
		Vector2i(4, 6), Vector2i(5, 6), Vector2i(7, 7), Vector2i(8, 6),
		Vector2i(5, 7), Vector2i(9, 6), Vector2i(9, 7),
	]
	var placed := 0
	var cells: Array = walk.keys()
	cells.sort_custom(func(a, b): return _hash(a) < _hash(b))
	for cell: Vector2i in cells:
		if placed >= 85:
			break
		if _hash(cell) % 4 != 0:
			continue
		if _place_prop(props, walk, walls, cell, _pick(decor, cell), 0, keepout, true):
			placed += 1

	# DarkCastle landmarks — banners / gargoyles only (no tiny doors / manholes on floor).
	for spot in [Vector2i(48, 20), Vector2i(76, 20)]:
		if walk.has(spot):
			props.set_cell(spot, 2, Vector2i(3, 0))
			if walk.has(spot + Vector2i.DOWN):
				props.set_cell(spot + Vector2i.DOWN, 2, Vector2i(3, 1))
	for spot in [Vector2i(28, 36), Vector2i(100, 36)]:
		if walk.has(spot):
			props.set_cell(spot, 2, Vector2i(1, 1))
	for spot in [Vector2i(24, 20), Vector2i(104, 20)]:
		if walk.has(spot):
			props.set_cell(spot, 2, Vector2i(3, 3))  # gargoyle
	# DG pillars (source 3) — support colonnade through mid hall
	for spot in [
		Vector2i(52, 32), Vector2i(76, 32), Vector2i(cx, 52),
		Vector2i(48, 48), Vector2i(80, 48), Vector2i(56, 28), Vector2i(72, 28),
		Vector2i(40, 40), Vector2i(88, 40), Vector2i(52, 56), Vector2i(76, 56),
	]:
		if walk.has(spot):
			props.set_cell(spot, 3, Vector2i(10 + _hash(spot) % 4, 10))
	_place_prop(props, walk, walls, Vector2i(16, 32), Vector2i(8, 6), 0, keepout, true)
	_place_prop(props, walk, walls, Vector2i(108, 28), Vector2i(7, 7), 0, keepout, true)

	_assert_walkable(walk, [entrance, portal, Vector2i(cx, 83), Vector2i(31, 24)], "sewers spawn")
	_assert_connected(walk, entrance, [portal, Vector2i(24, 24), Vector2i(31, 24), Vector2i(104, 24), Vector2i(cx, 28)], "sewers")

	var decos: Array = []
	var ti := 0
	for spot in [
		Vector2i(18, 18), Vector2i(32, 18), Vector2i(18, 36), Vector2i(32, 36),
		Vector2i(94, 18), Vector2i(108, 18), Vector2i(94, 36), Vector2i(108, 36),
		Vector2i(48, 18), Vector2i(76, 18), Vector2i(48, 52), Vector2i(76, 52),
		Vector2i(56, 36), Vector2i(72, 36), Vector2i(52, 72), Vector2i(76, 72),
		Vector2i(cx - 8, 60), Vector2i(cx + 8, 60),
	]:
		if not walk.has(spot):
			continue
		ti += 1
		var frames := "deco_torch" if ti % 3 != 0 else "deco_candle_a"
		decos.append({
			"name": "SewerLight%d" % ti,
			"frames": frames,
			"pos": _tile_pos(spot),
			"scale": 1.5 if frames == "deco_torch" else 1.8,
			"light": 0.95,
			"color": "Color(0.55, 0.95, 0.55, 1)" if frames != "deco_torch" else "Color(1, 0.7, 0.35, 1)",
		})
	var si := 0
	for spot in [Vector2i(40, 48), Vector2i(84, 48), Vector2i(60, 52), Vector2i(68, 52), Vector2i(24, 28), Vector2i(104, 28)]:
		if not walk.has(spot):
			continue
		si += 1
		decos.append({
			"name": "SewerSpike%d" % si,
			"frames": "deco_spike",
			"pos": _tile_pos(spot),
			"scale": 1.25,
			"light": 0.0,
			"color": "Color(1, 1, 1, 1)",
		})

	_write_map({
		"root": "sewers",
		"out": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
		"tileset": SEWERS_TS,
		"bg": "Color(0.015, 0.025, 0.02, 1)",
		"modulate": "Color(0.58, 0.76, 0.64, 1)",
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
		"cam_bottom": int(_tile_pos(portal).y) + 320,
		"lights": (
			"\n[node name=\"SewerGlow1\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(384, 448)\ncolor = Color(0.5, 0.95, 0.55, 1)\nenergy = 1.05\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.2\n"
			+ "\n[node name=\"SewerGlow2\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(1664, 448)\ncolor = Color(0.5, 0.95, 0.55, 1)\nenergy = 1.05\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.2\n"
			+ "\n[node name=\"SewerGlow3\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(1024, 640)\ncolor = Color(0.45, 0.85, 0.55, 1)\nenergy = 1.0\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.5\n"
			+ "\n[node name=\"SewerGlow4\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(1024, 1160)\ncolor = Color(0.5, 0.88, 0.55, 1)\nenergy = 0.9\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.0\n"
		),
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [str(_tile_pos(Vector2i(cx, 83)).x), str(_tile_pos(Vector2i(cx, 83)).y)]
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
