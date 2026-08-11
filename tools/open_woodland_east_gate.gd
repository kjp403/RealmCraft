extends SceneTree
## Open Goblin Woodland's east seal into a short transition grove + portal plaza
## that leads to the East Wilds (real biome maps). Does NOT stripe-fill the map.
##
##   godot --headless --path . -s tools/open_woodland_east_gate.gd

const MapKit := preload("res://tools/lib/mapkit.gd")
const MAP_PATH := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"

const SRC_FLOOR := 0
const SRC_WALL := 1
const SRC_VEG := 2
const SRC_TREE_M := 4
const SRC_TREE_L := 5

const GRASS: Array[Vector2i] = [Vector2i(1, 10), Vector2i(2, 10), Vector2i(3, 10)]
const DIRT: Array[Vector2i] = [Vector2i(5, 7), Vector2i(6, 6), Vector2i(6, 8), Vector2i(7, 5), Vector2i(8, 6)]
const WALL: Array[Vector2i] = [Vector2i(2, 6), Vector2i(3, 6), Vector2i(2, 7), Vector2i(3, 7)]
const VEG: Array[Vector2i] = [Vector2i(1, 9), Vector2i(5, 9), Vector2i(7, 10), Vector2i(12, 2)]


func _initialize() -> void:
	var abs_path := ProjectSettings.globalize_path(MAP_PATH)
	var original := FileAccess.get_file_as_string(abs_path)
	var map: Node2D = (load(MAP_PATH) as PackedScene).instantiate()
	var ground: TileMapLayer = map.find_child("Ground", true, false) as TileMapLayer
	var walls: TileMapLayer = map.find_child("Walls", true, false) as TileMapLayer
	var decor: TileMapLayer = map.find_child("Decor", true, false) as TileMapLayer

	# Clear any prior mega-expansion east of the seal.
	for y in range(0, 100):
		for x in range(177, 1600):
			ground.erase_cell(Vector2i(x, y))
			walls.erase_cell(Vector2i(x, y))
			decor.erase_cell(Vector2i(x, y))
			var features: TileMapLayer = map.find_child("Features", true, false) as TileMapLayer
			if features:
				features.erase_cell(Vector2i(x, y))

	# Open main approach gate (y=34..45) through seal x=177..180
	for y in range(34, 46):
		for x in range(177, 181):
			walls.erase_cell(Vector2i(x, y))
			ground.set_cell(Vector2i(x, y), SRC_FLOOR, MapKit._pick(DIRT, Vector2i(x, y), 1))

	# Transition grove: organic blob just east of the seal
	var bounds := Rect2i(181, 20, 55, 55)
	var grove := {}
	MapKit.blob(grove, Vector2i(205, 40), 18.0, 0.28, 11, bounds)
	MapKit.blob(grove, Vector2i(225, 38), 14.0, 0.32, 12, bounds)
	MapKit.blob(grove, Vector2i(215, 52), 12.0, 0.30, 13, bounds)
	MapKit.tunnel(grove, Vector2i(181, 40), Vector2i(205, 40), 3.5, 2.5, 14, bounds)
	grove = MapKit.smooth(grove, bounds, 2, 5, 4)

	for cell: Vector2i in grove.keys():
		var atlas: Vector2i = MapKit._pick(DIRT, cell, 20) if MapKit.rand01(cell.x, cell.y, 21) < 0.35 else MapKit._pick(GRASS, cell, 22)
		ground.set_cell(cell, SRC_FLOOR, atlas)
		if MapKit.rand01(cell.x, cell.y, 23) < 0.08:
			decor.set_cell(cell, SRC_VEG, MapKit._pick(VEG, cell, 24))
		elif MapKit.rand01(cell.x, cell.y, 25) < 0.035:
			decor.set_cell(cell, SRC_TREE_M if MapKit.hash2(cell.x, cell.y, 26) % 2 == 0 else SRC_TREE_L, Vector2i(0, 0))

	# Plaza clearing around portal spot
	var plaza := Vector2i(228, 40)
	for oy in range(-5, 6):
		for ox in range(-5, 6):
			var c := plaza + Vector2i(ox, oy)
			if not bounds.has_point(c):
				continue
			decor.erase_cell(c)
			ground.set_cell(c, SRC_FLOOR, MapKit._pick(DIRT, c, 30))

	# Soft rim walls around grove (not a full rectangle fill)
	for cell: Vector2i in grove.keys():
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cell + d
			if grove.has(n):
				continue
			if n.x < 181:
				continue
			walls.set_cell(n, SRC_WALL, MapKit._pick(WALL, n, 40))

	# Keep fungus pocket sealed except the main gate band
	for y in range(28, 52):
		if y >= 34 and y <= 45:
			continue
		for x in range(177, 181):
			walls.set_cell(Vector2i(x, y), SRC_WALL, MapKit._pick(WALL, Vector2i(x, y), 41))

	var features: TileMapLayer = map.find_child("Features", true, false) as TileMapLayer
	original = _replace_layer_blob(original, "Ground", ground.tile_map_data)
	original = _replace_layer_blob(original, "Walls", walls.tile_map_data)
	original = _replace_layer_blob(original, "Decor", decor.tile_map_data)
	if features:
		original = _replace_layer_blob(original, "Features", features.tile_map_data)

	# Camera: cover grove + a little margin (not 17k px)
	original = _replace_prop(original, "camera_limit_right", "4200")
	if not original.contains("\naoi_mode ="):
		var cam_i := original.find("camera_limit_left = 0")
		if cam_i >= 0:
			original = original.substr(0, cam_i) + "aoi_mode = 1\naoi_cell_size = Vector2i(250, 250)\naoi_visible_radius_cells = 2\n" + original.substr(cam_i)

	# Ext resources for portal target + east shore
	if not original.contains("woodland_east_wilds.tres"):
		var anchor := original.find("[ext_resource type=\"Resource\" uid=\"uid://iuqxmo63ipnn\"")
		var line_end := original.find("\n", anchor)
		original = original.substr(0, line_end + 1) + '[ext_resource type="Resource" path="res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland_east_wilds.tres" id="60_eastwilds"]\n' + original.substr(line_end + 1)
	if not original.contains("woodland_east_shore.tscn"):
		var deep := original.find("path=\"res://source/common/gameplay/maps/maps/woodland/woodland_deep_cove.tscn\"")
		var le := original.find("\n", deep)
		original = original.substr(0, le + 1) + '[ext_resource type="PackedScene" path="res://source/common/gameplay/maps/maps/woodland/woodland_east_shore.tscn" id="30_eastshore"]\n' + original.substr(le + 1)

	# Remove old mega-expansion nodes / stub labels if present
	original = _strip_node_block(original, "BiomeLandmarks")
	original = _strip_node_block(original, "WoodlandEastShore")
	original = _strip_node_block(original, "EastWildsPortal")
	original = _strip_node_block(original, "EastWildsLanding")
	original = _strip_node_block(original, "EastWildsLabel")

	# Insert portal + invisible return landing + shore + label before BeachVoidBounds.
	# Landing warper_id=60 is the return pad for East Wilds hub/biomes; the portal
	# itself uses 59 so returns do not stack on the outbound trigger.
	var insert_at := original.find("[node name=\"BeachVoidBounds\"")
	var nodes := """[node name="EastWildsPortal" parent="." instance=ExtResource("4_2dprc")]
position = Vector2(3648, 640)
portal_color = Color(0.55, 0.42, 0.18, 1)
destination_label = "East Wilds"
target_instance = ExtResource("60_eastwilds")
warper_id = 59
target_id = 60

[node name="EastWildsLanding" parent="." instance=ExtResource("5_jiw8u")]
position = Vector2(3616, 672)
warper_id = 60

[node name="EastWildsLabel" type="Label" parent="."]
offset_left = 3520.0
offset_top = 560.0
offset_right = 3780.0
offset_bottom = 592.0
theme_override_colors/font_color = Color(1, 0.9, 0.55, 1)
theme_override_colors/font_outline_color = Color(0, 0, 0, 0.9)
theme_override_constants/outline_size = 4
theme_override_font_sizes/font_size = 16
text = "East Wilds"
horizontal_alignment = 1

[node name="WoodlandEastShore" parent="." instance=ExtResource("30_eastshore")]
position = Vector2(2436, 1540)

"""
	original = original.substr(0, insert_at) + nodes + original.substr(insert_at)

	# Beach void push
	original = original.replace(
		"position = Vector2(2460, 1780)\nshape = SubResource(\"BeachVoidEast\")",
		"position = Vector2(3140, 1780)\nshape = SubResource(\"BeachVoidEast\")"
	)
	original = original.replace(
		"[sub_resource type=\"RectangleShape2D\" id=\"BeachVoidSouth\"]\nsize = Vector2(1700, 64)",
		"[sub_resource type=\"RectangleShape2D\" id=\"BeachVoidSouth\"]\nsize = Vector2(2400, 64)"
	)
	original = original.replace(
		"position = Vector2(1668, 2064)\nshape = SubResource(\"BeachVoidSouth\")",
		"position = Vector2(2000, 2064)\nshape = SubResource(\"BeachVoidSouth\")"
	)

	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(original)
	f.close()
	print("WOODLAND_EAST_GATE_PASS plaza=", plaza, " portal_px=", Vector2(plaza) * 16.0)
	quit(0)


func _strip_node_block(text: String, node_name: String) -> String:
	var marker := '[node name="%s"' % node_name
	var start := text.find(marker)
	if start < 0:
		return text
	# Include child nodes until next top-level [node name= that isn't a child path
	var i := start
	var end := text.find("\n[node name=\"", start + marker.length())
	# Also catch nested children: keep eating while parent="NodeName or parent="NodeName/
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
	var b64 := Marshalls.raw_to_base64(data)
	var node_idx := text.find('[node name="%s"' % layer_name)
	var data_key := "tile_map_data = PackedByteArray(\""
	var data_idx := text.find(data_key, node_idx)
	var start := data_idx + data_key.length()
	var end := text.find("\")", start)
	return text.substr(0, start) + b64 + text.substr(end)


func _replace_prop(text: String, prop: String, value: String) -> String:
	var key := prop + " = "
	var idx := text.find(key)
	if idx < 0:
		return text
	var start := idx + key.length()
	var end := text.find("\n", start)
	return text.substr(0, start) + value + text.substr(end)
