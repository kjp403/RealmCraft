extends SceneTree
## Build Mining Cave by stamping authored Fungus wall ROOMS onto chambers.
## Floors are always mine dirt/stone (never fungus grass). Layout/ores/lighting
## stay mine-specific.
## Run: godot --headless --path . -s tools/build_mining_cave.gd

const TILESET := "res://source/common/gameplay/maps/tilesets/mining_cave_tileset.tres"
const OUT_TSCN := "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"
const STAMP_DIR := "res://tools/stamps/"

const W := 78
const H := 46

## Dirt / packed earth only. Never (11–14, 14–16) grass/moss from CaveTiles.
const DIRT_FLOORS: Array[Vector2i] = [
	Vector2i(8, 15), Vector2i(7, 15), Vector2i(9, 15), Vector2i(8, 14),
	Vector2i(10, 15), Vector2i(6, 15), Vector2i(10, 13), Vector2i(8, 13),
	Vector2i(7, 14), Vector2i(9, 14), Vector2i(7, 16), Vector2i(9, 16),
]

## Authored 2-tile north wall columns (atlas pairs) sampled from Fungus stamps.
const NORTH_WALL_COLS: Array = [
	[Vector2i(2, 6), Vector2i(2, 7)],
	[Vector2i(2, 15), Vector2i(2, 16)],
	[Vector2i(3, 15), Vector2i(3, 16)],
	[Vector2i(4, 5), Vector2i(4, 6)],
]


func _initialize() -> void:
	var ts: TileSet = load(TILESET)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts

	var walk: Dictionary = {} # Vector2i -> true (ground cells)
	var chambers: Array = [
		{"name": "staging", "origin": Vector2i(2, 14), "stamp": "fungus_square.txt"},
		{"name": "copper", "origin": Vector2i(22, 2), "stamp": "fungus_tall.txt"},
		{"name": "iron", "origin": Vector2i(36, 24), "stamp": "fungus_square.txt"},
		{"name": "coal", "origin": Vector2i(48, 12), "stamp": "fungus_wide.txt"},
	]
	for ch in chambers:
		_stamp_room(ground, walls, walk, ch["origin"], STAMP_DIR + String(ch["stamp"]))
		print("stamped ", ch["name"], " @ ", ch["origin"])

	# Haulage corridors between stamped rooms.
	_carve_corridor(ground, walls, walk, Vector2i(18, 20), Vector2i(24, 22))
	_carve_corridor(ground, walls, walk, Vector2i(24, 18), Vector2i(38, 22))
	_carve_corridor(ground, walls, walk, Vector2i(38, 20), Vector2i(50, 24))
	_carve_corridor(ground, walls, walk, Vector2i(28, 14), Vector2i(32, 18))
	_carve_corridor(ground, walls, walk, Vector2i(40, 22), Vector2i(44, 26))

	_repaint_all_dirt(ground, walk)
	_strip_walls_from_open_floor(walls, walk)
	_paint_rock_props(props, walls, walk)

	var grass_left := _count_grass(ground)
	if grass_left > 0:
		push_error("grass tiles remain after dirt repaint: %d" % grass_left)
		quit(1)
		return

	var open := _open_floor(walls, walk)
	var ores := _place_ores(open)
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
		" grass=", grass_left
	)
	quit(0)


func _load_stamp(path: String) -> Dictionary:
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
	var h: int = absi((cell.x * 73856093) ^ (cell.y * 19349663))
	return DIRT_FLOORS[h % DIRT_FLOORS.size()]


func _is_grass(atlas: Vector2i) -> bool:
	return atlas.x >= 11 and atlas.x <= 14 and atlas.y >= 14 and atlas.y <= 16


func _stamp_room(
	ground: TileMapLayer,
	walls: TileMapLayer,
	walk: Dictionary,
	origin: Vector2i,
	stamp_path: String
) -> void:
	var stamp := _load_stamp(stamp_path)
	# Floors: keep stamp footprint, force dirt atlases (no fungus grass).
	for g in stamp["ground"]:
		var cell: Vector2i = origin + g["pos"]
		if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
			continue
		ground.set_cell(cell, 0, _dirt_at(cell))
		walk[cell] = true
	# Walls: exact authored Fungus clusters — this is what makes them look right.
	for wcell in stamp["walls"]:
		var cell2: Vector2i = origin + wcell["pos"]
		if cell2.x < 0 or cell2.y < 0 or cell2.x >= W or cell2.y >= H:
			continue
		walls.set_cell(cell2, 0, wcell["atlas"])


func _carve_corridor(
	ground: TileMapLayer,
	walls: TileMapLayer,
	walk: Dictionary,
	a: Vector2i,
	b: Vector2i
) -> void:
	var x0: int = mini(a.x, b.x)
	var x1: int = maxi(a.x, b.x)
	var y0: int = mini(a.y, b.y)
	var y1: int = maxi(a.y, b.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell := Vector2i(x, y)
			if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
				continue
			if walls.get_cell_source_id(cell) >= 0:
				walls.erase_cell(cell)
			ground.set_cell(cell, 0, _dirt_at(cell))
			walk[cell] = true

	# Corridor edge lips OUTSIDE the walk rect only (never stamp walls onto floor).
	var horiz := (x1 - x0) >= (y1 - y0)
	if horiz:
		var i := 0
		for x in range(x0, x1 + 1):
			var col: Array = NORTH_WALL_COLS[i % NORTH_WALL_COLS.size()]
			i += 1
			var above := Vector2i(x, y0 - 1)
			var above2 := Vector2i(x, y0 - 2)
			if _in_bounds(above) and not walk.has(above):
				walls.set_cell(above, 0, col[1] if col.size() > 1 else col[0])
			if _in_bounds(above2) and not walk.has(above2):
				walls.set_cell(above2, 0, col[0])
			var below := Vector2i(x, y1 + 1)
			if _in_bounds(below) and not walk.has(below):
				# South lip: short face tile from Fungus south edges.
				walls.set_cell(below, 0, Vector2i(1, 1))
	else:
		for y in range(y0, y1 + 1):
			var left := Vector2i(x0 - 1, y)
			var right := Vector2i(x1 + 1, y)
			if _in_bounds(left) and not walk.has(left):
				walls.set_cell(left, 0, Vector2i(4, 5))
			if _in_bounds(right) and not walk.has(right):
				walls.set_cell(right, 0, Vector2i(0, 3))


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < W and cell.y < H


func _repaint_all_dirt(ground: TileMapLayer, walk: Dictionary) -> void:
	for cell: Vector2i in walk.keys():
		ground.set_cell(cell, 0, _dirt_at(cell))


func _strip_walls_from_open_floor(walls: TileMapLayer, walk: Dictionary) -> void:
	## Corridor carve already clears path cells. Do not strip perimeter wall/floor
	## overlaps — CaveTiles rely on that for depth. Only clear accidental lips
	## that landed on interior cells with 4-walk neighbors.
	var to_clear: Array[Vector2i] = []
	for cell: Vector2i in walk.keys():
		if walls.get_cell_source_id(cell) < 0:
			continue
		var n := 0
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if walk.has(cell + d):
				n += 1
		if n >= 4:
			to_clear.append(cell)
	for c in to_clear:
		walls.erase_cell(c)


func _count_grass(ground: TileMapLayer) -> int:
	var n := 0
	for cell in ground.get_used_cells():
		if _is_grass(ground.get_cell_atlas_coords(cell)):
			n += 1
	return n


func _open_floor(walls: TileMapLayer, walk: Dictionary) -> Dictionary:
	var open: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if walls.get_cell_source_id(cell) < 0:
			open[cell] = true
	return open


func _paint_rock_props(props: TileMapLayer, walls: TileMapLayer, walk: Dictionary) -> void:
	# Source 4 = rocks.png (never CaveProps mushrooms).
	# Wall-aligned decorative rocks only — never surround the staging portal.
	var rocks: Array[Dictionary] = [
		{"atlas": Vector2i(0, 1), "size": Vector2i(2, 3)},
		{"atlas": Vector2i(2, 1), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(6, 1), "size": Vector2i(2, 3)},
		{"atlas": Vector2i(8, 1), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(0, 7), "size": Vector2i(2, 3)},
		{"atlas": Vector2i(2, 7), "size": Vector2i(2, 2)},
	]
	var occupied: Dictionary = {}
	var spots: Array[Vector2i] = [
		# staging — north lip only (portal keepout clear)
		Vector2i(6, 16), Vector2i(12, 16),
		# copper spur
		Vector2i(22, 6), Vector2i(24, 19),
		# iron
		Vector2i(36, 27), Vector2i(40, 25),
		# coal
		Vector2i(52, 13), Vector2i(48, 20), Vector2i(61, 15),
	]
	for spot in spots:
		if not walk.has(spot) or walls.get_cell_source_id(spot) >= 0:
			continue
		var rock: Dictionary = rocks[absi(spot.x * 31 + spot.y) % rocks.size()]
		var size: Vector2i = rock["size"]
		var ok := true
		for oy in range(size.y):
			for ox in range(size.x):
				var c := spot + Vector2i(ox, oy)
				if not walk.has(c) or walls.get_cell_source_id(c) >= 0 or occupied.has(c):
					ok = false
		if not ok:
			continue
		for oy2 in range(size.y):
			for ox2 in range(size.x):
				occupied[spot + Vector2i(ox2, oy2)] = true
		props.set_cell(spot, 4, rock["atlas"])


func _place_ores(open: Dictionary) -> Array:
	## Wall-aligned ore layout: clusters sit against chamber walls, entrance clear.
	## Prefer the authored tile when open; otherwise snap to a nearby wall-adjacent cell.
	var plan: Array = [
		# staging — east/north lips only (portal/campfire keepout stays open)
		{"kind": "copper", "tile": Vector2i(15, 16)},
		{"kind": "copper", "tile": Vector2i(18, 18)},
		{"kind": "tin", "tile": Vector2i(18, 23)},
		# copper spur — neat north-wall seam + east/west pockets
		{"kind": "copper", "tile": Vector2i(25, 5)},
		{"kind": "copper", "tile": Vector2i(29, 5)},
		{"kind": "copper", "tile": Vector2i(32, 5)},
		{"kind": "tin", "tile": Vector2i(36, 7)},
		{"kind": "tin", "tile": Vector2i(23, 17)},
		{"kind": "tin", "tile": Vector2i(37, 18)},
		# iron chamber — north + east walls
		{"kind": "iron", "tile": Vector2i(38, 24)},
		{"kind": "iron", "tile": Vector2i(50, 25)},
		{"kind": "iron", "tile": Vector2i(52, 28)},
		{"kind": "iron", "tile": Vector2i(52, 33)},
		# coal gallery — north gallery then east wall
		{"kind": "coal", "tile": Vector2i(55, 13)},
		{"kind": "coal", "tile": Vector2i(64, 15)},
		{"kind": "coal", "tile": Vector2i(68, 17)},
		{"kind": "coal", "tile": Vector2i(69, 24)},
		{"kind": "coal", "tile": Vector2i(74, 23)},
	]
	var used: Dictionary = {}
	var out: Array = []
	for entry in plan:
		var tile: Vector2i = entry["tile"]
		var placed := _find_wall_ore_near(open, used, tile, 5)
		if placed == Vector2i(-999, -999):
			push_warning("no wall-adjacent floor for ore %s near %s" % [entry["kind"], tile])
			continue
		used[placed] = true
		# Keep neighbors free so veins aren't stacked.
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			used[placed + d] = true
		out.append({
			"kind": entry["kind"],
			"pos": Vector2(placed.x * 16 + 8, placed.y * 16 + 8),
		})
	return out


func _find_wall_ore_near(open: Dictionary, used: Dictionary, origin: Vector2i, radius: int) -> Vector2i:
	## Prefer the exact tile when open+unused; otherwise nearest open cell.
	## Callers author wall-adjacent tiles; this is a rebuild safety net only.
	if open.has(origin) and not used.has(origin):
		return origin
	for r in range(1, radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := origin + Vector2i(dx, dy)
				if open.has(c) and not used.has(c):
					return c
	return Vector2i(-999, -999)


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

	var text := """[gd_scene format=3 uid=\"uid://cminingcave001\"]

[ext_resource type=\"Script\" uid=\"uid://7mbux4mybta0\" path=\"res://source/common/gameplay/maps/map.gd\" id=\"1_map\"]
[ext_resource type=\"TileSet\" uid=\"uid://hrdxga40fogr\" path=\"res://source/common/gameplay/maps/tilesets/mining_cave_tileset.tres\" id=\"2_tiles\"]
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
map_background_color = Color(0.04, 0.035, 0.03, 1)
music = ExtResource(\"3_music\")
camera_limit_left = -16
camera_limit_top = -16
camera_limit_right = 1264
camera_limit_bottom = 752

[node name=\"CanvasModulate\" type=\"CanvasModulate\" parent=\".\"]
color = Color(0.58, 0.6, 0.64, 1)

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
position = Vector2(176, 336)
color = Color(0.85, 0.9, 1, 1)
energy = 1.0
texture = ExtResource(\"9_glow\")
texture_scale = 2.0

[node name=\"LampCopper\" type=\"PointLight2D\" parent=\"SceneProps\"]
position = Vector2(480, 176)
color = Color(1, 0.85, 0.55, 1)
energy = 0.8
texture = ExtResource(\"9_glow\")
texture_scale = 1.7

[node name=\"LampIron\" type=\"PointLight2D\" parent=\"SceneProps\"]
position = Vector2(720, 496)
color = Color(1, 0.85, 0.55, 1)
energy = 0.8
texture = ExtResource(\"9_glow\")
texture_scale = 1.7

[node name=\"LampCoal\" type=\"PointLight2D\" parent=\"SceneProps\"]
position = Vector2(992, 304)
color = Color(0.75, 0.82, 0.95, 1)
energy = 0.95
texture = ExtResource(\"9_glow\")
texture_scale = 1.9

[node name=\"CampfireStaging\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]
position = Vector2(144, 352)

[node name=\"CampfireCoal\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]
position = Vector2(1008, 336)

[node name=\"ReplicatedPropsContainer\" type=\"Node2D\" parent=\".\" node_paths=PackedStringArray(\"id_to_node\", \"node_to_id\")]
y_sort_enabled = true
script = ExtResource(\"4_rp\")
id_to_node = {}
node_to_id = {}

[node name=\"MineableNodes\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true
%s
[node name=\"RespawnPoint\" parent=\".\" instance=ExtResource(\"5_warper\")]
position = Vector2(176, 336)

[node name=\"Entrance\" parent=\".\" instance=ExtResource(\"5_warper\")]
position = Vector2(176, 336)
warper_id = 30

[node name=\"WoodlandPortal\" parent=\".\" instance=ExtResource(\"6_portal\")]
position = Vector2(112, 352)
portal_color = Color(0.35, 0.55, 0.28, 1)
destination_label = \"Goblin Woodland\"
target_instance = ExtResource(\"7_woodland\")
warper_id = 131
target_id = 130
""" % [ground_b64, walls_b64, props_b64, ore_nodes]

	var path := ProjectSettings.globalize_path(OUT_TSCN)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", path)
