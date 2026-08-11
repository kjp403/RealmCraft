extends SceneTree
## Expand Goblin Woodland eastward into desert / swamp / volcano stub biomes.
## APPEND-ONLY: never rewrites tiles west of the east seal (x < 177).
##
##   godot --headless --path . -s tools/expand_woodland_east.gd
##
## EAST_MULT=5 → new east width ≈ 5× current woodland width (~885 tiles).
## (8× was declined as too large for a single instance; 5× keeps room to grow.)

const MAP_PATH := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
const EAST_MULT := 5
const CUR_W := 177
const SEAL_X0 := 177
const SEAL_X1 := 180 # inclusive
const EXP_X0 := 181
const TILE := 16

# Floor atlas (source 0) — from woodland floor_tiles.png
const GRASS := [Vector2i(1, 10), Vector2i(2, 10), Vector2i(3, 10)]
const SAND := [Vector2i(10, 7), Vector2i(11, 6), Vector2i(11, 8), Vector2i(12, 5), Vector2i(13, 6), Vector2i(14, 7)]
const STONE := [Vector2i(16, 1), Vector2i(16, 2), Vector2i(17, 2), Vector2i(18, 1), Vector2i(18, 3)]
const DIRT := [Vector2i(5, 7), Vector2i(6, 6), Vector2i(6, 8), Vector2i(7, 5), Vector2i(8, 6)]

# Walls source 1 — fill with a solid brick used on the east seal
const WALL_ATLAS := Vector2i(5, 2)
const WALL_SOURCE := 1
const GROUND_SOURCE := 0
const WATER_SOURCE := 8
const WATER_ATLAS := Vector2i(2, 2)


func _initialize() -> void:
	var abs_path := ProjectSettings.globalize_path(MAP_PATH)
	var original := FileAccess.get_file_as_string(abs_path)
	if original.is_empty():
		push_error("failed to read woodland")
		quit(1)
		return

	var packed: PackedScene = load(MAP_PATH)
	var map: Node2D = packed.instantiate()
	var ground: TileMapLayer = map.find_child("Ground", true, false) as TileMapLayer
	var walls: TileMapLayer = map.find_child("Walls", true, false) as TileMapLayer
	var features: TileMapLayer = map.find_child("Features", true, false) as TileMapLayer
	if ground == null or walls == null or features == null:
		push_error("missing tile layers")
		quit(1)
		return

	var new_w: int = CUR_W * EAST_MULT
	var exp_x1: int = EXP_X0 + new_w - 1 # inclusive
	print("expand east: x=", EXP_X0, "..", exp_x1, " (width=", new_w, " tiles)")

	# --- 1) Open east seal gates (corridor bands) — keep fungus pocket walls elsewhere ---
	var gates: Array[Vector2i] = [
		Vector2i(8, 18), # desert gate y0..y1
		Vector2i(34, 45), # main / swamp approach (existing corridor)
		Vector2i(70, 82), # volcano / beach approach
	]
	var erased_walls := 0
	for gate: Vector2i in gates:
		for y: int in range(gate.x, gate.y + 1):
			for x: int in range(SEAL_X0, SEAL_X1 + 1):
				var c := Vector2i(x, y)
				if walls.get_cell_source_id(c) >= 0:
					walls.erase_cell(c)
					erased_walls += 1
	print("opened_gate_walls=", erased_walls)

	# --- 2) Paint expansion ground + sparse features + outer rim walls ---
	var painted_ground := 0
	var painted_water := 0
	var painted_walls := 0
	var h: int = 100 # match current woodland height

	for y: int in range(0, h):
		for x: int in range(EXP_X0, exp_x1 + 1):
			var cell := Vector2i(x, y)
			var biome: StringName = _biome_at(y)
			var atlas: Vector2i = _pick_floor(biome, x, y)
			ground.set_cell(cell, GROUND_SOURCE, atlas)
			painted_ground += 1

			# Swamp water puddles
			if biome == &"swamp" and _hash01(x, y, 91) < 0.085:
				features.set_cell(cell, WATER_SOURCE, WATER_ATLAS)
				painted_water += 1
			# Volcano "lava cracks" — darker stone speckles already via atlas; add dirt scars
			elif biome == &"volcano" and _hash01(x, y, 77) < 0.04:
				ground.set_cell(cell, GROUND_SOURCE, DIRT[_hash_i(x, y, 3) % DIRT.size()])

	# Transition grass strip just past the seal so the grove doesn't hard-cut into sand
	for y: int in range(0, h):
		for x: int in range(EXP_X0, EXP_X0 + 6):
			if _biome_at(y) == &"desert" or _biome_at(y) == &"volcano":
				if _hash01(x, y, 11) < 0.55:
					ground.set_cell(Vector2i(x, y), GROUND_SOURCE, GRASS[_hash_i(x, y, 5) % GRASS.size()])

	# Outer rim walls (north/south/east). Leave gate y-bands open on the west join.
	for x: int in range(EXP_X0, exp_x1 + 1):
		for y: int in [0, 1, h - 2, h - 1]:
			walls.set_cell(Vector2i(x, y), WALL_SOURCE, WALL_ATLAS)
			painted_walls += 1
	for y: int in range(0, h):
		for x: int in range(exp_x1 - 1, exp_x1 + 1):
			walls.set_cell(Vector2i(x, y), WALL_SOURCE, WALL_ATLAS)
			painted_walls += 1

	# Soft biome divider hedges (thin wall nubs, with gaps so you can cross)
	for div_y: int in [32, 66]:
		for x: int in range(EXP_X0 + 8, exp_x1 - 2):
			if (x % 14) < 10: # gaps every 14 tiles
				walls.set_cell(Vector2i(x, div_y), WALL_SOURCE, WALL_ATLAS)
				walls.set_cell(Vector2i(x, div_y + 1), WALL_SOURCE, WALL_ATLAS)
				painted_walls += 2

	print("painted_ground=", painted_ground, " water=", painted_water, " walls=", painted_walls)

	# --- 3) Rewrite tile_map_data blobs in the .tscn text ---
	original = _replace_layer_blob(original, "Ground", ground.tile_map_data)
	original = _replace_layer_blob(original, "Walls", walls.tile_map_data)
	original = _replace_layer_blob(original, "Features", features.tile_map_data)

	# --- 4) Camera limits (px) ---
	var cam_r: int = (exp_x1 + 2) * TILE
	var cam_b: int = 2048 # beach hangs below tiles; keep headroom
	original = _replace_prop(original, "camera_limit_right", str(cam_r))
	original = _replace_prop(original, "camera_limit_bottom", str(cam_b))

	# Enable AOI GRID (forest-style) so a huge east wing stays net-friendly.
	if "aoi_mode =" not in original.split("\n")[0] and not original.contains("\naoi_mode ="):
		# Insert after map script props near camera limits
		var cam_i := original.find("camera_limit_left = 0")
		if cam_i >= 0:
			original = (
				original.substr(0, cam_i)
				+ "aoi_mode = 1\naoi_cell_size = Vector2i(250, 250)\naoi_visible_radius_cells = 2\n"
				+ original.substr(cam_i)
			)

	# --- 5) Beach void: push east wall out; widen south barrier ---
	# Deep cove ends ~2436; new shore strip starts there (704px wide) → ~3140.
	var east_void_x: int = 3140
	original = original.replace(
		"position = Vector2(2460, 1780)\nshape = SubResource(\"BeachVoidEast\")",
		"position = Vector2(%d, 1780)\nshape = SubResource(\"BeachVoidEast\")" % east_void_x
	)
	# Widen south void so it spans beach+cove+east shore (~900..3140)
	original = original.replace(
		"[sub_resource type=\"RectangleShape2D\" id=\"BeachVoidSouth\"]\nsize = Vector2(1700, 64)",
		"[sub_resource type=\"RectangleShape2D\" id=\"BeachVoidSouth\"]\nsize = Vector2(2400, 64)"
	)
	original = original.replace(
		"position = Vector2(1668, 2064)\nshape = SubResource(\"BeachVoidSouth\")",
		"position = Vector2(2000, 2064)\nshape = SubResource(\"BeachVoidSouth\")"
	)

	# --- 6) Instance east shore strip (after DeepCove) ---
	if not original.contains("WoodlandEastShore"):
		var insert_at := original.find("[node name=\"BeachVoidBounds\"")
		if insert_at < 0:
			push_error("BeachVoidBounds missing")
			quit(1)
			return
		# Ensure ext_resource for east shore exists
		if not original.contains("woodland_east_shore.tscn"):
			var ext_anchor := original.find("[ext_resource type=\"PackedScene\" uid=\"uid://cdeepcove00001\"")
			if ext_anchor < 0:
				ext_anchor = original.find("path=\"res://source/common/gameplay/maps/maps/woodland/woodland_deep_cove.tscn\"")
			var line_end := original.find("\n", ext_anchor)
			var ext_line := (
				'[ext_resource type="PackedScene" path="res://source/common/gameplay/maps/maps/woodland/woodland_east_shore.tscn" id="30_eastshore"]\n'
			)
			original = original.substr(0, line_end + 1) + ext_line + original.substr(line_end + 1)
			# re-find BeachVoid after insertion
			insert_at = original.find("[node name=\"BeachVoidBounds\"")
		var shore_node := (
			"[node name=\"WoodlandEastShore\" parent=\".\" instance=ExtResource(\"30_eastshore\")]\n"
			+ "position = Vector2(2436, 1540)\n\n"
		)
		original = original.substr(0, insert_at) + shore_node + original.substr(insert_at)

	# Open DeepCove east rim so the new shore joins (rim_east currently default true).
	# The deep cove scene itself is edited separately.

	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(original)
	f.close()
	print("wrote ", abs_path)
	print("camera_limit_right=", cam_r)
	print("WOODLAND_EAST_EXPAND_PASS")
	quit(0)


func _biome_at(y: int) -> StringName:
	if y < 33:
		return &"desert"
	if y < 67:
		return &"swamp"
	return &"volcano"


func _pick_floor(biome: StringName, x: int, y: int) -> Vector2i:
	var bag: Array = GRASS
	match biome:
		&"desert":
			bag = SAND
		&"swamp":
			bag = GRASS
		&"volcano":
			bag = STONE
	return bag[_hash_i(x, y, 19) % bag.size()]


func _hash_i(x: int, y: int, seed_v: int) -> int:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (seed_v * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


func _hash01(x: int, y: int, seed_v: int) -> float:
	return float(_hash_i(x, y, seed_v) % 100000) / 100000.0


func _replace_layer_blob(text: String, layer_name: String, data: PackedByteArray) -> String:
	var b64 := Marshalls.raw_to_base64(data)
	var node_idx := text.find('[node name="%s"' % layer_name)
	if node_idx < 0:
		push_error("layer node missing: " + layer_name)
		return text
	var data_key := "tile_map_data = PackedByteArray(\""
	var data_idx := text.find(data_key, node_idx)
	if data_idx < 0:
		push_error("tile_map_data missing: " + layer_name)
		return text
	var start := data_idx + data_key.length()
	var end := text.find("\")", start)
	if end < 0:
		push_error("tile_map_data end missing: " + layer_name)
		return text
	return text.substr(0, start) + b64 + text.substr(end)


func _replace_prop(text: String, prop: String, value: String) -> String:
	var key := prop + " = "
	var idx := text.find(key)
	if idx < 0:
		return text
	var start := idx + key.length()
	var end := text.find("\n", start)
	return text.substr(0, start) + value + text.substr(end)
