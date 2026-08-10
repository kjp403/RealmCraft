extends SceneTree
## Paint Desert / Fire Forge / Sewers maps (replace stub polygons).
## Run after build_biome_tilesets.gd:
##   godot --headless --path . -s tools/build_stub_biomes.gd

const DESERT_TS := "res://source/common/gameplay/maps/tilesets/desert_tileset.tres"
const FORGE_TS := "res://source/common/gameplay/maps/tilesets/fire_forge_tileset.tres"
const SEWERS_TS := "res://source/common/gameplay/maps/tilesets/sewers_tileset.tres"

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
const INSET := 2


func _initialize() -> void:
	_build_desert()
	_build_fire_forge()
	_build_sewers()
	print("STUB_BIOMES_PASS")
	quit(0)


func _hash(cell: Vector2i) -> int:
	return absi((cell.x * 73856093) ^ (cell.y * 19349663))


func _paint_rect_floor(ground: TileMapLayer, walk: Dictionary, a: Vector2i, b: Vector2i, floors: Array, source: int = 0) -> void:
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var cell := Vector2i(x, y)
			if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
				continue
			var atlas: Vector2i = floors[_hash(cell) % floors.size()]
			ground.set_cell(cell, source, atlas)
			walk[cell] = true


func _paint_perimeter_walls(
	walls: TileMapLayer,
	walk: Dictionary,
	wall_fill: Vector2i,
	wall_rim: Vector2i,
	source: int = 0
) -> void:
	var cx := int(W / 2)
	for y in range(H):
		for x in range(W):
			var cell := Vector2i(x, y)
			var edge := x < INSET or x >= W - INSET or y < INSET or y >= H - INSET
			var portal_gap := y >= H - INSET and x >= cx - 3 and x <= cx + 3
			if edge and not portal_gap:
				var rim := (
					x == INSET - 1 or x == W - INSET or y == INSET - 1 or y == H - INSET
				)
				walls.set_cell(cell, source, wall_rim if rim else wall_fill)
			elif not walk.has(cell):
				# Fill non-walk exterior pockets as walls (for carved layouts)
				pass


func _carve_room(ground: TileMapLayer, walls: TileMapLayer, walk: Dictionary, origin: Vector2i, size: Vector2i, floors: Array, source: int = 0) -> void:
	_paint_rect_floor(ground, walk, origin, origin + size - Vector2i.ONE, floors, source)
	# Clear any walls that landed on walk
	for y in range(origin.y, origin.y + size.y):
		for x in range(origin.x, origin.x + size.x):
			var cell := Vector2i(x, y)
			if walls.get_cell_source_id(cell) >= 0:
				walls.erase_cell(cell)


func _carve_corridor(ground: TileMapLayer, walls: TileMapLayer, walk: Dictionary, a: Vector2i, b: Vector2i, floors: Array, source: int = 0) -> void:
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell := Vector2i(x, y)
			if cell.x < 0 or cell.y < 0 or cell.x >= W or cell.y >= H:
				continue
			if walls.get_cell_source_id(cell) >= 0:
				walls.erase_cell(cell)
			ground.set_cell(cell, source, floors[_hash(cell) % floors.size()])
			walk[cell] = true


func _scatter_props(props: TileMapLayer, walk: Dictionary, walls: TileMapLayer, spots: Array, atlases: Array, source: int) -> void:
	for spot in spots:
		var cell: Vector2i = spot
		if not walk.has(cell):
			continue
		if walls.get_cell_source_id(cell) >= 0:
			continue
		var atlas: Vector2i = atlases[_hash(cell) % atlases.size()]
		props.set_cell(cell, source, atlas)


func _fill_unwalked_walls(walls: TileMapLayer, walk: Dictionary, wall_fill: Vector2i, source: int = 0) -> void:
	## For dungeon layouts: solid fill everything that isn't walkable (except portal gap).
	var cx := int(W / 2)
	for y in range(H):
		for x in range(W):
			var cell := Vector2i(x, y)
			var portal_gap := y >= H - INSET and x >= cx - 3 and x <= cx + 3
			if portal_gap:
				continue
			if walk.has(cell):
				continue
			walls.set_cell(cell, source, wall_fill)


func _b64(layer: TileMapLayer) -> String:
	return Marshalls.raw_to_base64(layer.tile_map_data)


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
		if not FileAccess.file_exists(path):
			# allow non-trpg fallbacks
			path = str(h.get("path", path))
		var ext_id := "h%d" % i
		hostile_ext += (
			"[ext_resource type=\"Resource\" path=\"%s\" id=\"%s\"]\n" % [path, ext_id]
		)
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

	var lights: String = cfg.get("lights", "")
	var camps: String = cfg.get("camps", "")
	var extras: String = cfg.get("extras", "")
	var music_line: String = ""
	if cfg.has("music"):
		music_line = "music = ExtResource(\"music\")\n"

	var music_ext := ""
	if cfg.has("music"):
		music_ext = (
			"[ext_resource type=\"AudioStream\" path=\"%s\" id=\"music\"]\n" % cfg["music"]
		)

	var text := """[gd_scene format=3]

[ext_resource type=\"Script\" uid=\"uid://7mbux4mybta0\" path=\"%s\" id=\"1_map\"]
[ext_resource type=\"TileSet\" path=\"%s\" id=\"2_tiles\"]
%s[ext_resource type=\"Script\" uid=\"uid://wq8klpndipnu\" path=\"%s\" id=\"4_rp\"]
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
		MAP_SCRIPT,
		cfg["tileset"],
		music_ext,
		RP_SCRIPT,
		WARPER,
		PORTAL,
		HUB,
		CAMP,
		GLOW,
		HOSTILE,
		hostile_ext,
		cfg["root"],
		cfg["bg"],
		music_line,
		cfg["modulate"],
		cfg["ground_b64"],
		cfg["walls_b64"],
		cfg["props_b64"],
		lights,
		camps,
		id_map,
		node_map,
		hostile_nodes,
		str(cfg["entrance"].x),
		str(cfg["entrance"].y),
		str(cfg["entrance"].x),
		str(cfg["entrance"].y),
		int(cfg["entrance_id"]),
		str(cfg["portal"].x),
		str(cfg["portal"].y),
		cfg["portal_color"],
		int(cfg["portal_id"]),
		int(cfg["entrance_id"]),
	]

	var path: String = cfg["out"]
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", path, " walk=", cfg.get("walk_count", 0), " mobs=", hostiles.size())


func _tile_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 16 + 8, cell.y * 16 + 8)


func _build_desert() -> void:
	var ts: TileSet = load(DESERT_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts
	var walk: Dictionary = {}

	var floors: Array = [
		Vector2i(2, 1), Vector2i(3, 1), Vector2i(7, 1), Vector2i(1, 2), Vector2i(2, 2),
		Vector2i(3, 2), Vector2i(4, 2), Vector2i(7, 2), Vector2i(1, 3), Vector2i(4, 1),
		Vector2i(6, 0), Vector2i(9, 0), Vector2i(6, 1), Vector2i(8, 1),
	]
	# Open desert floor
	_paint_rect_floor(ground, walk, Vector2i(INSET, INSET), Vector2i(W - INSET - 1, H - INSET - 1), floors, 0)
	# Canyon rim — darker rock blocks
	_paint_perimeter_walls(walls, walk, Vector2i(8, 12), Vector2i(7, 12), 0)

	# Ruin plaza north (stone / path mix)
	var ruin_floors: Array = [Vector2i(8, 1), Vector2i(9, 1), Vector2i(6, 1), Vector2i(8, 2), Vector2i(9, 0)]
	_carve_room(ground, walls, walk, Vector2i(20, 6), Vector2i(20, 12), ruin_floors, 0)

	# Oasis pocket west
	_carve_room(ground, walls, walk, Vector2i(6, 16), Vector2i(12, 10), floors, 0)
	# Dune bowl east
	_carve_room(ground, walls, walk, Vector2i(40, 18), Vector2i(14, 12), floors, 0)

	_scatter_props(props, walk, walls, [
		Vector2i(10, 10), Vector2i(14, 20), Vector2i(48, 12), Vector2i(44, 24),
		Vector2i(28, 10), Vector2i(32, 14), Vector2i(8, 28), Vector2i(50, 30),
		Vector2i(18, 32), Vector2i(36, 8),
	], [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 2), Vector2i(1, 2)], 1)

	# Sand path accents (source 2)
	for cell in [Vector2i(30, 28), Vector2i(30, 30), Vector2i(30, 32), Vector2i(28, 34), Vector2i(32, 34)]:
		if walk.has(cell):
			props.set_cell(cell, 2, Vector2i(6, 0))

	var hostiles := [
		{"name": "CragYeti", "type": "trpg_crag_yeti", "pos": _tile_pos(Vector2i(12, 20))},
		{"name": "WerewolfStalker", "type": "trpg_werewolf_stalker", "pos": _tile_pos(Vector2i(46, 22))},
		{"name": "Cockatrice", "type": "trpg_lacerating_cockatrice", "pos": _tile_pos(Vector2i(28, 12))},
		{"name": "DesertOrc", "type": "trpg_orc", "pos": _tile_pos(Vector2i(22, 26))},
		{"name": "DesertArcher", "type": "trpg_archer", "pos": _tile_pos(Vector2i(40, 14))},
	]

	var cx := int(W / 2)
	_write_map({
		"root": "desert",
		"out": "res://source/common/gameplay/maps/maps/desert/desert.tscn",
		"tileset": DESERT_TS,
		"bg": "Color(0.45, 0.32, 0.16, 1)",
		"modulate": "Color(1.05, 0.95, 0.8, 1)",
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
		"lights": (
			"\n[node name=\"SunGlow\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(480, 200)\ncolor = Color(1, 0.85, 0.45, 1)\nenergy = 0.55\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 3.2\n"
		),
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [str(_tile_pos(Vector2i(cx, H - 7)).x), str(_tile_pos(Vector2i(cx, H - 7)).y)]
		),
	})


func _build_fire_forge() -> void:
	var ts: TileSet = load(FORGE_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts
	var walk: Dictionary = {}

	var floors: Array = [
		Vector2i(3, 14), Vector2i(4, 14), Vector2i(5, 14), Vector2i(2, 15),
		Vector2i(3, 15), Vector2i(1, 16), Vector2i(3, 16), Vector2i(5, 16),
	]
	var wall_tile := Vector2i(2, 2)
	var lava: Array = [Vector2i(20, 13), Vector2i(20, 15), Vector2i(23, 13), Vector2i(23, 15)]

	# Solid dungeon fill then carve chambers
	_fill_unwalked_walls(walls, {}, wall_tile, 0)
	_carve_room(ground, walls, walk, Vector2i(22, 28), Vector2i(16, 12), floors, 0) # staging
	_carve_room(ground, walls, walk, Vector2i(8, 10), Vector2i(16, 14), floors, 0) # west forge
	_carve_room(ground, walls, walk, Vector2i(36, 8), Vector2i(16, 14), floors, 0) # east forge
	_carve_room(ground, walls, walk, Vector2i(22, 8), Vector2i(14, 10), floors, 0) # north anvil hall
	_carve_corridor(ground, walls, walk, Vector2i(28, 28), Vector2i(32, 20), floors, 0)
	_carve_corridor(ground, walls, walk, Vector2i(22, 16), Vector2i(24, 24), floors, 0)
	_carve_corridor(ground, walls, walk, Vector2i(34, 16), Vector2i(38, 18), floors, 0)
	_carve_corridor(ground, walls, walk, Vector2i(28, 38), Vector2i(30, 42), floors, 0) # to portal

	# Lava pits (visual props, not walk-blocking via StaticBody — keep walkable around)
	for cell in [
		Vector2i(12, 14), Vector2i(14, 14), Vector2i(40, 12), Vector2i(42, 12),
		Vector2i(26, 10), Vector2i(28, 10),
	]:
		if walk.has(cell):
			props.set_cell(cell, 0, lava[_hash(cell) % lava.size()])

	_scatter_props(props, walk, walls, [
		Vector2i(10, 12), Vector2i(18, 18), Vector2i(40, 16), Vector2i(46, 14),
		Vector2i(26, 12), Vector2i(30, 32), Vector2i(24, 34),
	], [Vector2i(3, 14), Vector2i(5, 14), Vector2i(1, 16)], 0)

	var hostiles := [
		{"name": "DemonA", "type": "trpg_demon_a", "pos": _tile_pos(Vector2i(14, 16))},
		{"name": "BloodMonster", "type": "trpg_blood_monster_a", "pos": _tile_pos(Vector2i(42, 14))},
		{"name": "EliteOrc", "type": "trpg_elite_orc", "pos": _tile_pos(Vector2i(28, 12))},
		{"name": "ConjuringOni", "type": "trpg_conjuring_oni", "pos": _tile_pos(Vector2i(30, 18))},
		{"name": "UmberHulk", "type": "trpg_umber_hulk", "pos": _tile_pos(Vector2i(24, 32))},
	]

	var cx := int(W / 2)
	_write_map({
		"root": "fire_forge",
		"out": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
		"tileset": FORGE_TS,
		"bg": "Color(0.08, 0.03, 0.03, 1)",
		"modulate": "Color(0.85, 0.55, 0.45, 1)",
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
		"lights": (
			"\n[node name=\"ForgeGlowW\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(224, 240)\ncolor = Color(1, 0.45, 0.15, 1)\nenergy = 1.2\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.2\n"
			+ "\n[node name=\"ForgeGlowE\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(704, 224)\ncolor = Color(1, 0.4, 0.12, 1)\nenergy = 1.2\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.2\n"
			+ "\n[node name=\"StagingGlow\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(480, 540)\ncolor = Color(1, 0.55, 0.25, 1)\nenergy = 0.9\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.8\n"
		),
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [str(_tile_pos(Vector2i(cx, H - 7)).x), str(_tile_pos(Vector2i(cx, H - 7)).y)]
		),
	})


func _build_sewers() -> void:
	var ts: TileSet = load(SEWERS_TS)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts
	var walk: Dictionary = {}

	var floors: Array = [
		Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(6, 3), Vector2i(7, 3),
		Vector2i(8, 3), Vector2i(6, 6), Vector2i(7, 6), Vector2i(9, 6), Vector2i(0, 5),
	]
	var wall_tile := Vector2i(1, 1)

	_fill_unwalked_walls(walls, {}, wall_tile, 0)
	_carve_room(ground, walls, walk, Vector2i(24, 30), Vector2i(14, 10), floors, 0) # entrance hall
	_carve_room(ground, walls, walk, Vector2i(6, 8), Vector2i(14, 12), floors, 0) # west cistern
	_carve_room(ground, walls, walk, Vector2i(40, 8), Vector2i(14, 12), floors, 0) # east cistern
	_carve_room(ground, walls, walk, Vector2i(22, 8), Vector2i(16, 10), floors, 0) # north junction
	_carve_room(ground, walls, walk, Vector2i(20, 18), Vector2i(20, 8), floors, 0) # central channel
	_carve_corridor(ground, walls, walk, Vector2i(28, 30), Vector2i(30, 24), floors, 0)
	_carve_corridor(ground, walls, walk, Vector2i(12, 18), Vector2i(22, 20), floors, 0)
	_carve_corridor(ground, walls, walk, Vector2i(36, 18), Vector2i(42, 16), floors, 0)
	_carve_corridor(ground, walls, walk, Vector2i(28, 16), Vector2i(30, 12), floors, 0)
	_carve_corridor(ground, walls, walk, Vector2i(28, 38), Vector2i(30, 42), floors, 0)

	# Torch / banner-ish pixel props
	_scatter_props(props, walk, walls, [
		Vector2i(8, 10), Vector2i(16, 14), Vector2i(44, 10), Vector2i(50, 14),
		Vector2i(26, 10), Vector2i(34, 12), Vector2i(28, 20), Vector2i(22, 22),
		Vector2i(30, 34), Vector2i(26, 32),
	], [Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8), Vector2i(9, 8), Vector2i(0, 7)], 0)

	# RF grate accents (32px source 1) on a few cells — visual only
	for cell in [Vector2i(28, 22), Vector2i(12, 12), Vector2i(46, 12)]:
		if walk.has(cell):
			props.set_cell(cell, 1, Vector2i(22, 5))

	var hostiles := [
		{"name": "AcidOoze", "type": "trpg_acid_ooze", "pos": _tile_pos(Vector2i(12, 12))},
		{"name": "CarrionCrawler", "type": "trpg_carrion_crawler", "pos": _tile_pos(Vector2i(46, 12))},
		{"name": "SewerSlime", "type": "trpg_slime", "pos": _tile_pos(Vector2i(28, 20))},
		{"name": "SewerBat", "type": "trpg_bat", "pos": _tile_pos(Vector2i(26, 10))},
		{"name": "SewerSkeleton", "type": "trpg_skeleton", "pos": _tile_pos(Vector2i(34, 22))},
		{"name": "PoisonGorgon", "type": "trpg_poisonous_gorgon", "pos": _tile_pos(Vector2i(30, 34))},
	]

	var cx := int(W / 2)
	_write_map({
		"root": "sewers",
		"out": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
		"tileset": SEWERS_TS,
		"bg": "Color(0.04, 0.06, 0.05, 1)",
		"modulate": "Color(0.55, 0.7, 0.58, 1)",
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
		"lights": (
			"\n[node name=\"SewerLamp1\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(224, 208)\ncolor = Color(0.55, 0.85, 0.55, 1)\nenergy = 0.85\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.8\n"
			+ "\n[node name=\"SewerLamp2\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(736, 208)\ncolor = Color(0.55, 0.85, 0.55, 1)\nenergy = 0.85\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 1.8\n"
			+ "\n[node name=\"SewerLamp3\" type=\"PointLight2D\" parent=\"SceneProps\"]\n"
			+ "position = Vector2(480, 360)\ncolor = Color(0.45, 0.75, 0.55, 1)\nenergy = 0.75\n"
			+ "texture = ExtResource(\"9_glow\")\ntexture_scale = 2.0\n"
		),
		"camps": (
			"\n[node name=\"Campfire\" parent=\"SceneProps\" instance=ExtResource(\"8_camp\")]\n"
			+ "position = Vector2(%s, %s)\n" % [str(_tile_pos(Vector2i(cx, H - 7)).x), str(_tile_pos(Vector2i(cx, H - 7)).y)]
		),
	})
