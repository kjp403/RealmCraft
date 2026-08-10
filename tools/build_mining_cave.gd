extends SceneTree
## Rebuild Mining Cave with RPG Worlds Caves (32×32) for an organic AAA look.
## Ore veins stay wall-adjacent; warper IDs 30 / 131→130 unchanged.
##   godot --headless --path . -s tools/build_rpgw_cave_tileset.gd
##   godot --headless --path . -s tools/build_mining_cave.gd

const TILESET := "res://source/common/gameplay/maps/tilesets/rpgw_caves_tileset.tres"
const OUT_TSCN := "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"

const W := 52
const H := 36
const TILE := 32

## Flat purple-grey walkable floors only (no recessed "pit" lookalikes).
const FLOORS: Array[Vector2i] = [
	Vector2i(37, 4), Vector2i(36, 4), Vector2i(37, 2), Vector2i(36, 2),
	Vector2i(37, 3), Vector2i(36, 1), Vector2i(39, 2), Vector2i(39, 4),
	Vector2i(42, 1), Vector2i(43, 1), Vector2i(42, 2), Vector2i(43, 2),
]

const WALL_N: Array[Vector2i] = [
	Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0),
	Vector2i(31, 0), Vector2i(32, 0), Vector2i(33, 0),
]
const WALL_S: Array[Vector2i] = [
	Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6),
	Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7),
]
const WALL_W: Array[Vector2i] = [
	Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4),
	Vector2i(30, 2), Vector2i(30, 3), Vector2i(30, 4),
]
const WALL_E: Array[Vector2i] = [
	Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(9, 2), Vector2i(9, 3), Vector2i(9, 4),
	Vector2i(34, 2), Vector2i(34, 3), Vector2i(34, 4),
]
const WALL_FILL: Array[Vector2i] = [
	Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5),
	Vector2i(31, 3), Vector2i(32, 3), Vector2i(33, 3),
]
const WALL_NW := Vector2i(0, 0)
const WALL_NE := Vector2i(8, 0)
const WALL_SW := Vector2i(0, 6)
const WALL_SE := Vector2i(8, 6)

## Wood bridge planks (walkable).
const WOOD: Array[Vector2i] = [
	Vector2i(45, 32), Vector2i(46, 32), Vector2i(47, 32), Vector2i(48, 32), Vector2i(49, 32),
]

## Decorative source 1 — rocks / crystals / pebbles / fungi (see decorative.png).
const ROCK_DECO: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(5, 0), Vector2i(6, 0),
]
const CRYSTAL_BLUE: Array[Vector2i] = [
	Vector2i(0, 18), Vector2i(1, 18), Vector2i(2, 18), Vector2i(3, 18),
	Vector2i(0, 19), Vector2i(1, 19), Vector2i(2, 19),
]
const CRYSTAL_GREEN: Array[Vector2i] = [
	Vector2i(5, 18), Vector2i(6, 18), Vector2i(7, 18), Vector2i(8, 18),
	Vector2i(5, 19), Vector2i(6, 19), Vector2i(7, 19),
]
const PEBBLE: Array[Vector2i] = [
	Vector2i(0, 23), Vector2i(1, 23), Vector2i(2, 23), Vector2i(3, 23),
	Vector2i(4, 23), Vector2i(5, 23), Vector2i(0, 24), Vector2i(1, 24),
]
const MOSS: Array[Vector2i] = [
	Vector2i(0, 24), Vector2i(2, 24), Vector2i(5, 24), Vector2i(8, 24),
	Vector2i(1, 27), Vector2i(3, 27), Vector2i(4, 27),
]


func _initialize() -> void:
	var ts: TileSet = load(TILESET)
	assert(ts != null, "missing rpgw tileset — run build_rpgw_cave_tileset.gd first")
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts

	var walk: Dictionary = {}
	var pits: Dictionary = {}

	# Staging chamber (SW) — entrance + portal
	_fill_disk(walk, Vector2i(8, 26), 8.5)
	_fill_disk(walk, Vector2i(10, 24), 6.0)
	_fill_disk(walk, Vector2i(12, 28), 4.5)
	# Copper spur (NW)
	_fill_disk(walk, Vector2i(18, 8), 7.5)
	_fill_disk(walk, Vector2i(22, 10), 6.0)
	_fill_disk(walk, Vector2i(16, 10), 4.5)
	# Iron hall (center-east)
	_fill_disk(walk, Vector2i(30, 22), 8.0)
	_fill_disk(walk, Vector2i(34, 20), 6.5)
	_fill_disk(walk, Vector2i(32, 26), 5.0)
	# Coal gallery (NE) with pit ring
	_fill_disk(walk, Vector2i(42, 10), 8.0)
	_fill_disk(walk, Vector2i(40, 14), 6.0)
	_fill_disk(walk, Vector2i(44, 8), 5.0)
	# Central junction
	_fill_disk(walk, Vector2i(24, 16), 7.0)
	_fill_disk(walk, Vector2i(26, 18), 5.0)

	# Haulage corridors
	_carve_corridor(walk, Vector2i(10, 22), Vector2i(18, 12), 3)
	_carve_corridor(walk, Vector2i(20, 12), Vector2i(26, 16), 3)
	_carve_corridor(walk, Vector2i(26, 18), Vector2i(30, 20), 3)
	_carve_corridor(walk, Vector2i(32, 16), Vector2i(40, 12), 3)
	_carve_corridor(walk, Vector2i(12, 26), Vector2i(28, 22), 3)
	_carve_corridor(walk, Vector2i(8, 28), Vector2i(8, 32), 2)

	# Bottomless pits (void) — offset from chamber centers, then bridge one
	_mark_pit(walk, pits, Vector2i(25, 15), 2)
	_mark_pit(walk, pits, Vector2i(44, 12), 1)
	_mark_pit(walk, pits, Vector2i(34, 24), 1)

	# Wooden bridge across central pit (walkable)
	for x in range(23, 28):
		var cell := Vector2i(x, 15)
		walk[cell] = true
		pits.erase(cell)

	_paint_floors(ground, walk, pits)
	_paint_bridge(ground, Vector2i(22, 16), Vector2i(26, 16))
	_paint_wall_shell(walls, walk, pits)

	# Rock pillar islands (authored mass inside chambers — Fungus-style depth)
	# Keep clear of entrance (8,26), bridge (23-27,15), and main corridors.
	for island2 in [
		Vector2i(14, 20), Vector2i(20, 8), Vector2i(34, 22), Vector2i(44, 10), Vector2i(28, 14),
	]:
		for d2 in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.UP]:
			var ic2: Vector2i = island2 + d2
			if _in_bounds(ic2) and not pits.has(ic2) and walk.has(ic2):
				walk.erase(ic2)
				walls.set_cell(ic2, 0, _pick(WALL_FILL, ic2))
				ground.erase_cell(ic2)
	_clear_walls_on_walk(walls, walk)

	var open := _open_floor(walls, walk)
	_paint_props(props, walls, open)
	var ores := _place_ores(open, walls)

	_assert_walkable(walk, [Vector2i(8, 26), Vector2i(6, 28), Vector2i(18, 8), Vector2i(30, 22), Vector2i(40, 10)])
	_assert_connected(walk, Vector2i(8, 26), [Vector2i(6, 28), Vector2i(18, 8), Vector2i(30, 22), Vector2i(40, 10), Vector2i(26, 18)])

	_write_tscn(
		Marshalls.raw_to_base64(ground.tile_map_data),
		Marshalls.raw_to_base64(walls.tile_map_data),
		Marshalls.raw_to_base64(props.tile_map_data),
		ores
	)
	print(
		"OK mining_cave walk=", walk.size(),
		" open=", open.size(),
		" ground=", ground.get_used_cells().size(),
		" walls=", walls.get_used_cells().size(),
		" props=", props.get_used_cells().size(),
		" ores=", ores.size(),
		" pits=", pits.size()
	)
	quit(0)


func _hash(cell: Vector2i) -> int:
	return absi((cell.x * 73856093) ^ (cell.y * 19349663))


func _pick(arr: Array, cell: Vector2i) -> Vector2i:
	return arr[_hash(cell) % arr.size()]


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < W and cell.y < H


func _tile_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)


func _fill_disk(walk: Dictionary, center: Vector2i, radius: float) -> void:
	var r2 := int(radius * radius)
	for y in range(center.y - int(radius) - 2, center.y + int(radius) + 3):
		for x in range(center.x - int(radius) - 2, center.x + int(radius) + 3):
			var cell := Vector2i(x, y)
			if not _in_bounds(cell):
				continue
			var dx := x - center.x
			var dy := y - center.y
			var n := (_hash(cell) % 5) - 2
			if dx * dx + dy * dy <= r2 + n:
				walk[cell] = true


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


func _mark_pit(walk: Dictionary, pits: Dictionary, center: Vector2i, radius: int) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var cell := Vector2i(x, y)
			if not _in_bounds(cell):
				continue
			if absi(x - center.x) + absi(y - center.y) <= radius + 1:
				walk.erase(cell)
				pits[cell] = true


func _paint_floors(ground: TileMapLayer, walk: Dictionary, pits: Dictionary) -> void:
	for cell: Vector2i in walk.keys():
		if pits.has(cell):
			continue
		ground.set_cell(cell, 0, _pick(FLOORS, cell))


func _paint_bridge(ground: TileMapLayer, a: Vector2i, b: Vector2i) -> void:
	for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			var cell := Vector2i(x, y)
			ground.set_cell(cell, 0, _pick(WOOD, cell))


func _paint_wall_shell(walls: TileMapLayer, walk: Dictionary, pits: Dictionary) -> void:
	for y in range(H):
		for x in range(W):
			var cell := Vector2i(x, y)
			if walk.has(cell):
				continue
			var n := walk.has(cell + Vector2i.UP)
			var s := walk.has(cell + Vector2i.DOWN)
			var w := walk.has(cell + Vector2i.LEFT)
			var e := walk.has(cell + Vector2i.RIGHT)
			var pn := pits.has(cell + Vector2i.UP)
			var ps := pits.has(cell + Vector2i.DOWN)
			var pw := pits.has(cell + Vector2i.LEFT)
			var pe := pits.has(cell + Vector2i.RIGHT)
			# Also treat pit edges as needing wall lips
			n = n or pn
			s = s or ps
			w = w or pw
			e = e or pe
			if not (n or s or w or e):
				# Deep fill halo (3 cells) — thick rock mass like Fungus / reference caves
				var near := false
				for dy in range(-3, 4):
					for dx in range(-3, 4):
						if walk.has(cell + Vector2i(dx, dy)):
							near = true
							break
					if near:
						break
				if near:
					walls.set_cell(cell, 0, _pick(WALL_FILL, cell))
				continue
			if n and w and not s and not e:
				walls.set_cell(cell, 0, WALL_NW)
			elif n and e and not s and not w:
				walls.set_cell(cell, 0, WALL_NE)
			elif s and w and not n and not e:
				walls.set_cell(cell, 0, WALL_SW)
			elif s and e and not n and not w:
				walls.set_cell(cell, 0, WALL_SE)
			elif n and not s:
				walls.set_cell(cell, 0, _pick(WALL_N, cell))
			elif s and not n:
				walls.set_cell(cell, 0, _pick(WALL_S, cell))
			elif w and not e:
				walls.set_cell(cell, 0, _pick(WALL_W, cell))
			elif e and not w:
				walls.set_cell(cell, 0, _pick(WALL_E, cell))
			else:
				walls.set_cell(cell, 0, _pick(WALL_FILL, cell))

	# Second-tier north lip — stacked glowing ledge for depth (reference look).
	for cell: Vector2i in walk.keys():
		var above := cell + Vector2i.UP
		var above2 := cell + Vector2i(0, -2)
		if walk.has(above):
			continue
		if walls.get_cell_source_id(above) >= 0 and _in_bounds(above2) and not walk.has(above2):
			if walls.get_cell_source_id(above2) < 0:
				walls.set_cell(above2, 0, _pick(WALL_N, above2))


func _clear_walls_on_walk(walls: TileMapLayer, walk: Dictionary) -> void:
	for cell: Vector2i in walk.keys():
		if walls.get_cell_source_id(cell) >= 0:
			walls.erase_cell(cell)


func _open_floor(walls: TileMapLayer, walk: Dictionary) -> Dictionary:
	var open: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if walls.get_cell_source_id(cell) < 0:
			open[cell] = true
	return open


func _is_wall_adjacent(walls: TileMapLayer, cell: Vector2i) -> bool:
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if walls.get_cell_source_id(cell + d) >= 0:
			return true
	return false


func _paint_props(props: TileMapLayer, walls: TileMapLayer, open: Dictionary) -> void:
	var occupied: Dictionary = {}
	# Dense wall-adjacent rocks / stalagmites (authored clusters)
	var rock_spots: Array[Vector2i] = [
		Vector2i(6, 22), Vector2i(12, 22), Vector2i(14, 28), Vector2i(8, 20), Vector2i(14, 24),
		Vector2i(16, 6), Vector2i(22, 6), Vector2i(20, 12), Vector2i(18, 6), Vector2i(24, 12),
		Vector2i(28, 18), Vector2i(34, 18), Vector2i(36, 24), Vector2i(30, 18), Vector2i(34, 26),
		Vector2i(40, 8), Vector2i(46, 10), Vector2i(44, 16), Vector2i(42, 6), Vector2i(46, 14),
		Vector2i(26, 14), Vector2i(22, 18), Vector2i(24, 20), Vector2i(28, 14),
		Vector2i(12, 26), Vector2i(16, 28), Vector2i(36, 22), Vector2i(40, 14),
	]
	for spot in rock_spots:
		if not open.has(spot) or occupied.has(spot):
			continue
		if not _is_wall_adjacent(walls, spot) and _hash(spot) % 2 == 0:
			continue
		props.set_cell(spot, 1, _pick(ROCK_DECO, spot))
		occupied[spot] = true

	# Crystal clusters tucked into corners
	var crystal_spots: Array[Vector2i] = [
		Vector2i(14, 6), Vector2i(20, 6), Vector2i(24, 8), Vector2i(16, 8),
		Vector2i(28, 20), Vector2i(36, 18), Vector2i(38, 24), Vector2i(32, 24),
		Vector2i(40, 6), Vector2i(46, 8), Vector2i(44, 14), Vector2i(42, 8),
		Vector2i(6, 24), Vector2i(12, 24), Vector2i(8, 28), Vector2i(26, 12),
	]
	var ci := 0
	for spot in crystal_spots:
		if not open.has(spot) or occupied.has(spot):
			continue
		if not _is_wall_adjacent(walls, spot):
			continue
		var atlas: Vector2i = _pick(CRYSTAL_BLUE if ci % 2 == 0 else CRYSTAL_GREEN, spot)
		props.set_cell(spot, 1, atlas)
		occupied[spot] = true
		ci += 1

	# Moss / pebbles along walls — denser but still readable
	var placed := 0
	var cells: Array = open.keys()
	cells.sort_custom(func(a, b): return _hash(a) < _hash(b))
	for cell: Vector2i in cells:
		if placed >= 90:
			break
		if occupied.has(cell):
			continue
		if _hash(cell) % 4 != 0:
			continue
		if _is_wall_adjacent(walls, cell):
			props.set_cell(cell, 1, _pick(MOSS if _hash(cell) % 3 == 0 else PEBBLE, cell))
		elif _hash(cell) % 13 == 0:
			props.set_cell(cell, 1, _pick(PEBBLE, cell))
		else:
			continue
		occupied[cell] = true
		placed += 1


func _place_ores(open: Dictionary, walls: TileMapLayer) -> Array:
	## Wall-adjacent veins in each chamber — never on bridge / entrance keepout.
	var plan: Array = [
		# staging
		{"kind": "copper", "tile": Vector2i(12, 22)},
		{"kind": "copper", "tile": Vector2i(14, 28)},
		{"kind": "tin", "tile": Vector2i(6, 24)},
		# copper spur
		{"kind": "copper", "tile": Vector2i(16, 6)},
		{"kind": "copper", "tile": Vector2i(20, 6)},
		{"kind": "copper", "tile": Vector2i(22, 10)},
		{"kind": "tin", "tile": Vector2i(18, 12)},
		{"kind": "tin", "tile": Vector2i(24, 8)},
		# iron
		{"kind": "iron", "tile": Vector2i(28, 20)},
		{"kind": "iron", "tile": Vector2i(34, 18)},
		{"kind": "iron", "tile": Vector2i(36, 24)},
		{"kind": "iron", "tile": Vector2i(32, 26)},
		# coal
		{"kind": "coal", "tile": Vector2i(40, 6)},
		{"kind": "coal", "tile": Vector2i(46, 8)},
		{"kind": "coal", "tile": Vector2i(44, 14)},
		{"kind": "coal", "tile": Vector2i(40, 16)},
		{"kind": "coal", "tile": Vector2i(46, 12)},
	]
	var keepout: Dictionary = {
		Vector2i(8, 26): true, Vector2i(6, 28): true, Vector2i(7, 27): true,
		Vector2i(8, 27): true, Vector2i(9, 27): true, Vector2i(8, 28): true,
	}
	for x in range(23, 28):
		keepout[Vector2i(x, 15)] = true

	var used: Dictionary = {}
	var out: Array = []
	for entry in plan:
		var tile: Vector2i = entry["tile"]
		var placed := _find_wall_ore_near(open, walls, used, keepout, tile, 6)
		if placed == Vector2i(-999, -999):
			push_warning("no wall-adjacent floor for ore %s near %s" % [entry["kind"], tile])
			continue
		used[placed] = true
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			used[placed + d] = true
		out.append({
			"kind": entry["kind"],
			"pos": _tile_pos(placed),
		})
	return out


func _find_wall_ore_near(
	open: Dictionary,
	walls: TileMapLayer,
	used: Dictionary,
	keepout: Dictionary,
	origin: Vector2i,
	radius: int
) -> Vector2i:
	if (
		open.has(origin)
		and not used.has(origin)
		and not keepout.has(origin)
		and _is_wall_adjacent(walls, origin)
	):
		return origin
	var best := Vector2i(-999, -999)
	var best_d := 999999
	for r in range(0, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := origin + Vector2i(dx, dy)
				if not open.has(c) or used.has(c) or keepout.has(c):
					continue
				if not _is_wall_adjacent(walls, c):
					continue
				var d: int = absi(dx) + absi(dy)
				if d < best_d:
					best_d = d
					best = c
		if best != Vector2i(-999, -999):
			return best
	return best


func _assert_walkable(walk: Dictionary, cells: Array) -> void:
	for c in cells:
		assert(walk.has(c), "missing walk at %s" % str(c))


func _assert_connected(walk: Dictionary, start: Vector2i, goals: Array) -> void:
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
		assert(seen.has(g), "not connected to %s from %s" % [str(g), str(start)])


func _write_tscn(ground_b64: String, walls_b64: String, props_b64: String, ores: Array) -> void:
	var ore_nodes := ""
	var counts := {"copper": 0, "tin": 0, "iron": 0, "coal": 0}
	var res_ids := {
		"copper": "11_copper",
		"tin": "12_tin",
		"iron": "13_iron",
		"coal": "14_coal",
	}
	for ore in ores:
		var kind: String = ore["kind"]
		counts[kind] = int(counts[kind]) + 1
		var n: int = counts[kind]
		var pos: Vector2 = ore["pos"]
		ore_nodes += (
			"\n[node name=\"%sVein%d\" parent=\"MineableNodes\" instance=ExtResource(\"10_mine\")]\n"
			+ "y_sort_enabled = true\n"
			+ "position = Vector2(%s, %s)\n"
			+ "data = ExtResource(\"%s\")\n"
		) % [
			kind.capitalize() if kind != "tin" else "Tin",
			n,
			str(pos.x),
			str(pos.y),
			res_ids[kind],
		]

	var entrance := _tile_pos(Vector2i(8, 26))
	var portal := _tile_pos(Vector2i(6, 28))
	var camp := _tile_pos(Vector2i(9, 25))
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
[ext_resource type=\"Resource\" uid=\"uid://d08wf1j2mhlc5\" path=\"res://source/common/gameplay/maps/components/mineable_nodes/copper_vein.tres\" id=\"11_copper\"]
[ext_resource type=\"Resource\" uid=\"uid://ctinvein001xx\" path=\"res://source/common/gameplay/maps/components/mineable_nodes/tin_vein.tres\" id=\"12_tin\"]
[ext_resource type=\"Resource\" uid=\"uid://cutpirmfqwx8b\" path=\"res://source/common/gameplay/maps/components/mineable_nodes/iron_vein.tres\" id=\"13_iron\"]
[ext_resource type=\"Resource\" uid=\"uid://dtpviov364y0b\" path=\"res://source/common/gameplay/maps/components/mineable_nodes/coal_vein.tres\" id=\"14_coal\"]

[node name=\"mining_cave\" type=\"Node2D\" node_paths=PackedStringArray(\"replicated_props_container\")]
y_sort_enabled = true
script = ExtResource(\"1_map\")
replicated_props_container = NodePath(\"ReplicatedPropsContainer\")
map_background_color = Color(0.02, 0.015, 0.02, 1)
music = ExtResource(\"3_music\")
camera_limit_left = -16
camera_limit_top = -16
camera_limit_right = %d
camera_limit_bottom = %d

[node name=\"CanvasModulate\" type=\"CanvasModulate\" parent=\".\"]
color = Color(0.55, 0.5, 0.52, 1)

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

[node name=\"LampStaging\" type=\"PointLight2D\" parent=\"SceneProps\"]
position = Vector2(%s, %s)
color = Color(1, 0.75, 0.45, 1)
energy = 1.15
texture = ExtResource(\"9_glow\")
texture_scale = 2.4

[node name=\"LampCopper\" type=\"PointLight2D\" parent=\"SceneProps\"]
position = Vector2(%s, %s)
color = Color(1, 0.7, 0.4, 1)
energy = 1.0
texture = ExtResource(\"9_glow\")
texture_scale = 2.0

[node name=\"LampIron\" type=\"PointLight2D\" parent=\"SceneProps\"]
position = Vector2(%s, %s)
color = Color(1, 0.65, 0.35, 1)
energy = 1.0
texture = ExtResource(\"9_glow\")
texture_scale = 2.0

[node name=\"LampCoal\" type=\"PointLight2D\" parent=\"SceneProps\"]
position = Vector2(%s, %s)
color = Color(0.55, 0.85, 1, 1)
energy = 1.05
texture = ExtResource(\"9_glow\")
texture_scale = 2.2

[node name=\"LampJunction\" type=\"PointLight2D\" parent=\"SceneProps\"]
position = Vector2(%s, %s)
color = Color(1, 0.7, 0.4, 1)
energy = 0.85
texture = ExtResource(\"9_glow\")
texture_scale = 1.8

[node name=\"CampfireStaging\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]
position = Vector2(%s, %s)

[node name=\"CampfireCoal\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]
position = Vector2(%s, %s)

[node name=\"ReplicatedPropsContainer\" type=\"Node2D\" parent=\".\" node_paths=PackedStringArray(\"id_to_node\", \"node_to_id\")]
y_sort_enabled = true
script = ExtResource(\"4_rp\")
id_to_node = {}
node_to_id = {}

[node name=\"MineableNodes\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true
%s
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
		ground_b64, walls_b64, props_b64,
		str(entrance.x), str(entrance.y),
		str(_tile_pos(Vector2i(18, 8)).x), str(_tile_pos(Vector2i(18, 8)).y),
		str(_tile_pos(Vector2i(30, 22)).x), str(_tile_pos(Vector2i(30, 22)).y),
		str(_tile_pos(Vector2i(42, 10)).x), str(_tile_pos(Vector2i(42, 10)).y),
		str(_tile_pos(Vector2i(24, 16)).x), str(_tile_pos(Vector2i(24, 16)).y),
		str(camp.x), str(camp.y),
		str(_tile_pos(Vector2i(42, 14)).x), str(_tile_pos(Vector2i(42, 14)).y),
		ore_nodes,
		str(entrance.x), str(entrance.y),
		str(entrance.x), str(entrance.y),
		str(portal.x), str(portal.y),
	]

	var path := ProjectSettings.globalize_path(OUT_TSCN)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", path)
