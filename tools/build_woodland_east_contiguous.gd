extends SceneTree
## Contiguous Goblin Woodlands East — authored ON woodland_tiles.
## Walk east through the opened seal. Woodland tileset only.
## Grass-first floors (match main woodland). Dirt = paths only.
## Coherent sand meadow / pond marsh / stone shelves / beach — no floor noise.
##
##   godot --headless --path . -s tools/build_woodland_east_contiguous.gd

const MapKit := preload("res://tools/lib/mapkit.gd")
const MAP_PATH := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"

const SRC_FLOOR := 0
const SRC_WALL := 1
const SRC_VEG := 2
const SRC_TREE_S := 3
const SRC_TREE_M := 4
const SRC_TREE_L := 5
const SRC_TREE_XL := 6
const SRC_WATER := 8

const GRASS: Array[Vector2i] = [Vector2i(1, 10), Vector2i(2, 10), Vector2i(3, 10)]
const DIRT: Array[Vector2i] = [Vector2i(5, 7), Vector2i(6, 6), Vector2i(6, 8), Vector2i(7, 5), Vector2i(8, 6)]
const SAND: Array[Vector2i] = [Vector2i(10, 7), Vector2i(11, 6), Vector2i(11, 8), Vector2i(12, 5), Vector2i(13, 6), Vector2i(14, 7)]
const STONE: Array[Vector2i] = [Vector2i(16, 1), Vector2i(16, 2), Vector2i(17, 2), Vector2i(18, 1), Vector2i(18, 3)]
const WALL: Array[Vector2i] = [Vector2i(2, 6), Vector2i(3, 6), Vector2i(2, 7), Vector2i(3, 7), Vector2i(5, 2)]
const VEG: Array[Vector2i] = [Vector2i(1, 9), Vector2i(5, 9), Vector2i(7, 10), Vector2i(12, 2), Vector2i(8, 9)]
const WATER: Array[Vector2i] = [
	Vector2i(2, 2), Vector2i(2, 5), Vector2i(1, 6), Vector2i(3, 6),
	Vector2i(0, 7), Vector2i(4, 7), Vector2i(1, 8), Vector2i(3, 8), Vector2i(2, 9),
]

const SEAL_X0 := 177
const EXP_X0 := 181
const EXP_X1 := 360 # inclusive — real outdoor wing, not a stripe to infinity
const Y0 := 6
const Y1 := 94


func _initialize() -> void:
	var abs_path := ProjectSettings.globalize_path(MAP_PATH)
	var original := FileAccess.get_file_as_string(abs_path)
	var map: Node2D = (load(MAP_PATH) as PackedScene).instantiate()
	var ground: TileMapLayer = map.find_child("Ground", true, false) as TileMapLayer
	var walls: TileMapLayer = map.find_child("Walls", true, false) as TileMapLayer
	var decor: TileMapLayer = map.find_child("Decor", true, false) as TileMapLayer
	var features: TileMapLayer = map.find_child("Features", true, false) as TileMapLayer

	# --- 1) Wipe EVERYTHING east of the seal (kills any stripe leftover) ------
	for y in range(0, 120):
		for x in range(EXP_X0, 1600):
			var c := Vector2i(x, y)
			ground.erase_cell(c)
			walls.erase_cell(c)
			decor.erase_cell(c)
			if features:
				features.erase_cell(c)

	# --- 2) Open the east gate band -----------------------------------------
	for y in range(34, 46):
		for x in range(SEAL_X0, EXP_X0):
			walls.erase_cell(Vector2i(x, y))
			ground.set_cell(Vector2i(x, y), SRC_FLOOR, MapKit._pick(DIRT, Vector2i(x, y), 1))
	# Re-seal fungus pocket outside the gate band
	for y in range(20, 70):
		if y >= 34 and y <= 45:
			continue
		for x in range(SEAL_X0, EXP_X0):
			walls.set_cell(Vector2i(x, y), SRC_WALL, MapKit._pick(WALL, Vector2i(x, y), 2))

	var bounds := Rect2i(EXP_X0, Y0, EXP_X1 - EXP_X0 + 1, Y1 - Y0 + 1)

	# Landmarks (tile coords)
	var gate := Vector2i(182, 40)
	var cross := Vector2i(212, 42) # closer — no long highway
	var meadow := Vector2i(230, 16)
	var marsh := Vector2i(300, 42)
	var shelves := Vector2i(235, 72)
	var shore := Vector2i(290, 86)

	# --- 3) Organic contiguous floor (one connected forest wing) ------------
	var floor_mask: Dictionary = {}
	var chambers: Array = [
		# Immediate fat forest past the seal — no void-bridge
		[gate, 18.0, 0.18, 101],
		[Vector2i(195, 40), 18.0, 0.16, 102],
		[Vector2i(205, 26), 14.0, 0.20, 103],
		[Vector2i(205, 54), 14.0, 0.20, 104],
		[cross, 16.0, 0.16, 105],
		[Vector2i(235, 42), 13.0, 0.20, 106],
		[Vector2i(250, 42), 12.0, 0.20, 107],
		# North open meadow
		[meadow, 15.0, 0.18, 108],
		[Vector2i(215, 14), 11.0, 0.22, 109],
		[Vector2i(250, 14), 11.0, 0.22, 110],
		[Vector2i(230, 6), 9.0, 0.24, 111],
		[Vector2i(220, 26), 9.0, 0.24, 112],
		[Vector2i(245, 26), 9.0, 0.24, 113],
		# East marsh ponds
		[marsh, 15.0, 0.18, 114],
		[Vector2i(280, 28), 11.0, 0.22, 115],
		[Vector2i(280, 56), 11.0, 0.22, 116],
		[Vector2i(320, 28), 10.0, 0.24, 117],
		[Vector2i(320, 56), 10.0, 0.24, 118],
		[Vector2i(300, 18), 9.0, 0.26, 119],
		[Vector2i(300, 64), 9.0, 0.26, 120],
		# South rises
		[shelves, 14.0, 0.18, 121],
		[Vector2i(215, 72), 10.0, 0.22, 122],
		[Vector2i(260, 72), 10.0, 0.22, 123],
		[Vector2i(235, 84), 10.0, 0.22, 124],
		[Vector2i(250, 58), 9.0, 0.24, 125],
		# Beach apron
		[shore, 12.0, 0.20, 126],
		[Vector2i(315, 86), 10.0, 0.22, 127],
		[Vector2i(270, 88), 9.0, 0.24, 128],
	]
	for ch in chambers:
		MapKit.blob(floor_mask, ch[0], float(ch[1]), float(ch[2]), int(ch[3]), bounds)

	var links: Array = [
		[gate, cross, 7.0, 2.0, 201],
		[cross, meadow, 3.6, 2.0, 202],
		[cross, marsh, 3.8, 2.2, 203],
		[cross, shelves, 3.6, 2.0, 204],
		[shelves, shore, 3.0, 2.0, 205],
		[meadow, Vector2i(215, 14), 2.8, 2.2, 206],
		[meadow, Vector2i(250, 14), 2.8, 2.2, 207],
		[marsh, Vector2i(280, 28), 2.8, 2.2, 208],
		[marsh, Vector2i(280, 56), 2.8, 2.2, 209],
		[marsh, Vector2i(320, 28), 2.8, 2.2, 210],
		[marsh, Vector2i(320, 56), 2.8, 2.2, 211],
		[shelves, Vector2i(215, 72), 2.8, 2.2, 212],
		[shelves, Vector2i(260, 72), 2.8, 2.2, 213],
		[shore, Vector2i(315, 86), 2.8, 2.0, 214],
		[marsh, shore, 2.6, 2.5, 215],
		[Vector2i(205, 26), meadow, 2.6, 2.2, 216],
		[Vector2i(205, 54), shelves, 2.6, 2.2, 217],
	]
	for link in links:
		MapKit.tunnel(floor_mask, link[0], link[1], float(link[2]), float(link[3]), int(link[4]), bounds)

	floor_mask = MapKit.smooth(floor_mask, bounds, 2, 5, 4)
	floor_mask = MapKit.largest_region(floor_mask, gate)
	assert(floor_mask.size() > 5000, "east wing too small")

	# Rock outcrops (holes) for readable outdoor topography — sparse, intentional
	for spot in [
		[Vector2i(235, 18), 3.2, 301], [Vector2i(255, 14), 2.8, 302],
		[Vector2i(300, 36), 2.6, 303], [Vector2i(320, 48), 2.8, 304],
		[Vector2i(240, 68), 2.8, 305],
	]:
		var mesa: Dictionary = {}
		MapKit.blob(mesa, spot[0], float(spot[1]), 0.28, int(spot[2]), bounds)
		mesa = MapKit.smooth(mesa, bounds, 1, 5, 4)
		for cell: Vector2i in mesa.keys():
			floor_mask.erase(cell)
	floor_mask = MapKit.largest_region(floor_mask, gate)

	# --- 4) Path network (DIRT only — continuous ribbons) -------------------
	var path: Dictionary = {}
	var path_links: Array = [
		[gate, cross, 1.8, 1.2, 321],
		[cross, meadow, 1.6, 1.2, 322],
		[cross, marsh, 1.7, 1.3, 323],
		[cross, shelves, 1.6, 1.2, 324],
		[shelves, shore, 1.5, 1.2, 325],
		[meadow, Vector2i(215, 14), 1.4, 1.3, 326],
		[meadow, Vector2i(250, 14), 1.4, 1.3, 327],
		[marsh, Vector2i(320, 42), 1.4, 1.3, 328],
	]
	for link in path_links:
		MapKit.tunnel(path, link[0], link[1], float(link[2]), float(link[3]), int(link[4]), bounds)
	# Keep path only on floor
	var path_clean: Dictionary = {}
	for cell: Vector2i in path.keys():
		if floor_mask.has(cell):
			path_clean[cell] = true
	path = path_clean

	# --- 5) Region masks (coherent fills, not noise ownership) --------------
	var meadow_mask: Dictionary = {}
	MapKit.blob(meadow_mask, meadow, 15.0, 0.20, 401, bounds)
	MapKit.blob(meadow_mask, Vector2i(215, 14), 9.0, 0.24, 402, bounds)
	MapKit.blob(meadow_mask, Vector2i(250, 14), 9.0, 0.24, 403, bounds)
	meadow_mask = MapKit.smooth(meadow_mask, bounds, 1, 5, 4)

	var marsh_mask: Dictionary = {}
	MapKit.blob(marsh_mask, marsh, 15.0, 0.20, 411, bounds)
	MapKit.blob(marsh_mask, Vector2i(280, 28), 9.0, 0.24, 412, bounds)
	MapKit.blob(marsh_mask, Vector2i(280, 56), 9.0, 0.24, 413, bounds)
	MapKit.blob(marsh_mask, Vector2i(320, 28), 8.5, 0.26, 414, bounds)
	MapKit.blob(marsh_mask, Vector2i(320, 56), 8.5, 0.26, 415, bounds)
	marsh_mask = MapKit.smooth(marsh_mask, bounds, 1, 5, 4)

	# Meadow = OPEN GRASS clearing (matches main woodland language).
	# Dry dirt patches only as small intentional islands — NOT sand atlas noise.
	var dry_patches: Dictionary = {}
	for spot in [
		[Vector2i(230, 12), 3.5, 451], [Vector2i(218, 18), 2.8, 452], [Vector2i(245, 16), 3.0, 453],
	]:
		MapKit.blob(dry_patches, spot[0], float(spot[1]), 0.22, int(spot[2]), bounds)
	dry_patches = MapKit.smooth(dry_patches, bounds, 1, 5, 4)

	# Stone = small accent platforms on grass, not paved districts
	var stone_plats: Dictionary = {}
	for spot in [
		[shelves, 4.0, 421], [Vector2i(220, 70), 3.2, 422], [Vector2i(250, 74), 3.4, 423],
		[Vector2i(235, 80), 3.0, 424], [Vector2i(260, 68), 2.8, 425],
	]:
		MapKit.blob(stone_plats, spot[0], float(spot[1]), 0.22, int(spot[2]), bounds)
	stone_plats = MapKit.smooth(stone_plats, bounds, 1, 5, 4)

	var beach_mask: Dictionary = {}
	MapKit.blob(beach_mask, shore, 11.0, 0.22, 431, bounds)
	MapKit.blob(beach_mask, Vector2i(325, 86), 8.0, 0.24, 432, bounds)
	MapKit.blob(beach_mask, Vector2i(280, 88), 7.0, 0.26, 433, bounds)
	beach_mask = MapKit.smooth(beach_mask, bounds, 1, 5, 4)

	# Water ponds — only inside marsh ∩ floor, not on path
	var water_cells: Dictionary = {}
	for spot in [
		[Vector2i(300, 42), 6.0, 441], [Vector2i(285, 50), 5.0, 442],
		[Vector2i(315, 32), 5.2, 443], [Vector2i(310, 54), 4.8, 444],
		[Vector2i(290, 26), 4.4, 445], [Vector2i(325, 46), 4.6, 446],
	]:
		var pool: Dictionary = {}
		MapKit.blob(pool, spot[0], float(spot[1]), 0.30, int(spot[2]), bounds)
		pool = MapKit.smooth(pool, bounds, 1, 5, 4)
		for cell: Vector2i in pool.keys():
			if floor_mask.has(cell) and marsh_mask.has(cell) and not path.has(cell):
				water_cells[cell] = true

	# Dirt shore ring around water (1 cell)
	var shore_dirt: Dictionary = {}
	for cell: Vector2i in water_cells.keys():
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]:
			var n: Vector2i = cell + d
			if floor_mask.has(n) and not water_cells.has(n):
				shore_dirt[n] = true

	# --- 6) Paint floors: GRASS FIRST like main woodland --------------------
	for cell: Vector2i in floor_mask.keys():
		if water_cells.has(cell):
			ground.set_cell(cell, SRC_WATER, MapKit._pick(WATER, cell, 501))
			continue
		if path.has(cell):
			ground.set_cell(cell, SRC_FLOOR, MapKit._pick(DIRT, cell, 502))
			continue
		if shore_dirt.has(cell):
			ground.set_cell(cell, SRC_FLOOR, MapKit._pick(DIRT, cell, 503))
			continue
		if beach_mask.has(cell) and floor_mask.has(cell):
			ground.set_cell(cell, SRC_FLOOR, MapKit._pick(SAND, cell, 504))
			continue
		if dry_patches.has(cell) and floor_mask.has(cell) and cell.y < 34 and not path.has(cell):
			# Small dry dirt islands in the open meadow
			ground.set_cell(cell, SRC_FLOOR, MapKit._pick(DIRT, cell, 505))
			continue
		if stone_plats.has(cell) and floor_mask.has(cell) and cell.y > 58 and not path.has(cell):
			# Small stone accent platforms — not district paving
			ground.set_cell(cell, SRC_FLOOR, MapKit._pick(STONE, cell, 506))
			continue
		# Default: solid woodland grass (same as main map)
		ground.set_cell(cell, SRC_FLOOR, MapKit._pick(GRASS, cell, 507))

	# (no sand-meadow fringe — meadow stays grass-first)

	# --- 7) Rim walls -------------------------------------------------------
	var blocked: Dictionary = {}
	for cell: Vector2i in water_cells.keys():
		blocked[cell] = true

	for y in range(Y0 - 2, Y1 + 3):
		for x in range(EXP_X0 - 1, EXP_X1 + 3):
			var cell := Vector2i(x, y)
			if floor_mask.has(cell):
				continue
			if x < EXP_X0 and y >= 34 and y <= 45:
				continue # keep gate open
			var touch := false
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if floor_mask.has(cell + d):
					touch = true
					break
			if not touch:
				continue
			walls.set_cell(cell, SRC_WALL, MapKit._pick(WALL, cell, 511))
			blocked[cell] = true

	# --- 8) Trees: forest masses on edges + grove interiors; KEEP PATHS CLEAR
	var path_keepout: Dictionary = {}
	for cell: Vector2i in path.keys():
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				path_keepout[cell + Vector2i(ox, oy)] = true
	# Clear plaza at cross / gate / landmarks — meadow gets a REAL open clearing
	for spot in [gate, cross, marsh, shelves, shore]:
		for oy in range(-4, 5):
			for ox in range(-4, 5):
				path_keepout[spot + Vector2i(ox, oy)] = true
	for oy in range(-10, 11):
		for ox in range(-10, 11):
			if ox * ox + oy * oy <= 100:
				path_keepout[meadow + Vector2i(ox, oy)] = true
	# Pond shores stay walkable / visible
	for cell: Vector2i in water_cells.keys():
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				path_keepout[cell + Vector2i(ox, oy)] = true

	var tree_count := 0
	for cell: Vector2i in floor_mask.keys():
		if blocked.has(cell) or path_keepout.has(cell) or water_cells.has(cell):
			continue
		if shore_dirt.has(cell):
			continue
		# Near void = dense tree wall
		var near_void := false
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not floor_mask.has(cell + d):
				near_void = true
				break
		var chance := 0.0
		# Keep the gate approach OPEN — no tree pipe / void-bridge look
		if cell.x < 208:
			chance = 0.02 if near_void else 0.01
		elif near_void:
			chance = 0.38
		elif beach_mask.has(cell) and cell.y > 80:
			chance = 0.02
		elif meadow_mask.has(cell) and cell.y < 34:
			chance = 0.015 # open sunlit meadow — almost no trees in the clearing
		elif stone_plats.has(cell) and cell.y > 58:
			chance = 0.02
		elif marsh_mask.has(cell):
			chance = 0.09
		else:
			chance = 0.13 # general forest
		if MapKit.rand01(cell.x, cell.y, 521) >= chance:
			# veg instead sometimes
			if not near_void and MapKit.rand01(cell.x, cell.y, 522) < 0.08:
				features.set_cell(cell, SRC_VEG, MapKit._pick(VEG, cell, 523))
			continue
		var roll := MapKit.rand01(cell.x, cell.y, 524)
		var src := SRC_TREE_M
		if roll < 0.12:
			src = SRC_TREE_S
		elif roll < 0.50:
			src = SRC_TREE_M
		elif roll < 0.82:
			src = SRC_TREE_L
		else:
			src = SRC_TREE_XL
		decor.set_cell(cell, src, Vector2i(0, 0))
		tree_count += 1

	# Marsh reeds near water (veg only)
	for cell: Vector2i in shore_dirt.keys():
		if MapKit.rand01(cell.x, cell.y, 525) < 0.35:
			features.set_cell(cell, SRC_VEG, MapKit._pick(VEG, cell, 526))

	# --- 9) Write layers back into tscn -------------------------------------
	original = _replace_layer_blob(original, "Ground", ground.tile_map_data)
	original = _replace_layer_blob(original, "Walls", walls.tile_map_data)
	original = _replace_layer_blob(original, "Decor", decor.tile_map_data)
	if features:
		original = _replace_layer_blob(original, "Features", features.tile_map_data)

	# Camera covers contiguous east wing
	var cam_right := (EXP_X1 + 4) * 16
	original = _replace_prop(original, "camera_limit_right", str(cam_right))
	if not original.contains("\naoi_mode ="):
		var cam_i := original.find("camera_limit_left = 0")
		if cam_i >= 0:
			original = (
				original.substr(0, cam_i)
				+ "aoi_mode = 1\naoi_cell_size = Vector2i(250, 250)\naoi_visible_radius_cells = 2\n"
				+ original.substr(cam_i)
			)

	# Remove portal-hub / separate-map travel — this wing is walkable.
	for node_name in [
		"BiomeLandmarks", "EastWildsPortal", "EastWildsLanding", "EastWildsLabel",
		"WoodlandEastPortal", "WoodlandEastLanding", "WoodlandEastLabel",
	]:
		original = _strip_node_block(original, node_name)

	# Landmark labels (authored, not portals)
	original = _strip_node_block(original, "EastWingLandmarks")
	if not original.contains("woodland_east_shore.tscn"):
		var deep := original.find("path=\"res://source/common/gameplay/maps/maps/woodland/woodland_deep_cove.tscn\"")
		if deep >= 0:
			var le := original.find("\n", deep)
			original = (
				original.substr(0, le + 1)
				+ '[ext_resource type="PackedScene" path="res://source/common/gameplay/maps/maps/woodland/woodland_east_shore.tscn" id="30_eastshore"]\n'
				+ original.substr(le + 1)
			)

	original = _strip_node_block(original, "WoodlandEastShore")
	var insert_at := original.find("[node name=\"BeachVoidBounds\"")
	if insert_at < 0:
		insert_at = original.length()
	var labels := """[node name="EastWingLandmarks" type="Node2D" parent="."]

[node name="LabelCross" type="Label" parent="EastWingLandmarks"]
offset_left = %d.0
offset_top = %d.0
offset_right = %d.0
offset_bottom = %d.0
theme_override_colors/font_color = Color(0.9, 0.95, 0.7, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 15
text = "East Crossroads"
horizontal_alignment = 1

[node name="LabelMeadow" type="Label" parent="EastWingLandmarks"]
offset_left = %d.0
offset_top = %d.0
offset_right = %d.0
offset_bottom = %d.0
theme_override_colors/font_color = Color(0.95, 0.9, 0.65, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 15
text = "Sunlit Meadow"
horizontal_alignment = 1

[node name="LabelMarsh" type="Label" parent="EastWingLandmarks"]
offset_left = %d.0
offset_top = %d.0
offset_right = %d.0
offset_bottom = %d.0
theme_override_colors/font_color = Color(0.75, 0.95, 0.8, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 15
text = "Murkwood Ponds"
horizontal_alignment = 1

[node name="LabelShelves" type="Label" parent="EastWingLandmarks"]
offset_left = %d.0
offset_top = %d.0
offset_right = %d.0
offset_bottom = %d.0
theme_override_colors/font_color = Color(0.85, 0.85, 0.9, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 15
text = "Stone Shelves"
horizontal_alignment = 1

[node name="LabelShore" type="Label" parent="EastWingLandmarks"]
offset_left = %d.0
offset_top = %d.0
offset_right = %d.0
offset_bottom = %d.0
theme_override_colors/font_color = Color(0.95, 0.88, 0.6, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 15
text = "East Shore"
horizontal_alignment = 1

[node name="WoodlandEastShore" parent="." instance=ExtResource("30_eastshore")]
position = Vector2(3200, 1540)

""" % [
		cross.x * 16 - 70, cross.y * 16 - 48, cross.x * 16 + 70, cross.y * 16 - 24,
		meadow.x * 16 - 70, meadow.y * 16 - 40, meadow.x * 16 + 70, meadow.y * 16 - 16,
		marsh.x * 16 - 70, marsh.y * 16 - 40, marsh.x * 16 + 70, marsh.y * 16 - 16,
		shelves.x * 16 - 70, shelves.y * 16 - 40, shelves.x * 16 + 70, shelves.y * 16 - 16,
		shore.x * 16 - 60, shore.y * 16 - 40, shore.x * 16 + 60, shore.y * 16 - 16,
	]
	original = original.substr(0, insert_at) + labels + original.substr(insert_at)

	# Beach void push for longer east
	original = original.replace(
		"position = Vector2(3140, 1780)\nshape = SubResource(\"BeachVoidEast\")",
		"position = Vector2(4200, 1780)\nshape = SubResource(\"BeachVoidEast\")"
	)
	original = original.replace(
		"position = Vector2(2460, 1780)\nshape = SubResource(\"BeachVoidEast\")",
		"position = Vector2(4200, 1780)\nshape = SubResource(\"BeachVoidEast\")"
	)

	# Drop ext_resource to woodland_east if present (no longer used for travel)
	var ext_line := '[ext_resource type="Resource" path="res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland_east.tres" id="60_eastwilds"]\n'
	original = original.replace(ext_line, "")
	original = original.replace(
		'[ext_resource type="Resource" path="res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland_east_wilds.tres" id="60_eastwilds"]\n',
		""
	)

	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(original)
	f.close()

	# Count floor mix for QA
	var grass_n := 0
	var dirt_n := 0
	var sand_n := 0
	var stone_n := 0
	var water_n := 0
	for cell: Vector2i in floor_mask.keys():
		var sid := ground.get_cell_source_id(cell)
		var a := ground.get_cell_atlas_coords(cell)
		if sid == SRC_WATER:
			water_n += 1
		elif a.y == 10 and a.x >= 1 and a.x <= 3:
			grass_n += 1
		elif a.x >= 10 and a.x <= 14:
			sand_n += 1
		elif a.x >= 16:
			stone_n += 1
		else:
			dirt_n += 1

	print(
		"WOODLAND_EAST_CONTIGUOUS_PASS floor=", floor_mask.size(),
		" grass=", grass_n, " dirt=", dirt_n, " sand=", sand_n, " stone=", stone_n,
		" water=", water_n, " trees=", tree_count,
		" cam_right=", cam_right
	)
	assert(grass_n > dirt_n * 2, "grass must dominate like main woodland")
	assert(water_n > 80, "need real ponds")
	assert(sand_n > 200, "need beach sand")
	map.free()
	quit(0)


func _strip_node_block(text: String, node_name: String) -> String:
	var marker := '[node name="%s"' % node_name
	var start := text.find(marker)
	if start < 0:
		return text
	var i := start
	var end := text.find("\n[node name=\"", start + marker.length())
	while true:
		var next := text.find("\n[node name=\"", i + 1)
		if next < 0:
			end = text.length()
			break
		var line_end := text.find("\n", next + 1)
		var header := text.substr(next, line_end - next)
		if header.contains('parent="%s"' % node_name) or header.contains('parent="%s/' % node_name):
			i = next
			end = text.find("\n[node name=\"", next + 1)
			continue
		end = next
		break
	return text.substr(0, start) + text.substr(end if end >= 0 else text.length())


func _replace_layer_blob(text: String, layer_name: String, data: PackedByteArray) -> String:
	var marker := '[node name="%s"' % layer_name
	var start := text.find(marker)
	if start < 0:
		return text
	var data_key := "tile_map_data = PackedByteArray(\""
	var data_i := text.find(data_key, start)
	if data_i < 0:
		return text
	var q0 := data_i + data_key.length()
	var q1 := text.find("\")", q0)
	return text.substr(0, q0) + Marshalls.raw_to_base64(data) + text.substr(q1)


func _replace_prop(text: String, key: String, value: String) -> String:
	var re := RegEx.new()
	re.compile("%s = .*" % key)
	return re.sub(text, "%s = %s" % [key, value], false)
