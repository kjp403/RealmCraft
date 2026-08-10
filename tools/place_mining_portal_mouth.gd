extends SceneTree
## Commercial Mining Cave entrance on Goblin Woodland:
## intact cliff, portal at (978, 839), dirt path extended organically under
## the portal so it doesn't sit on a grass rectangle against the wall.
## Run: godot --headless --path . -s tools/place_mining_portal_mouth.gd

const MAP_PATH := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
const WALL_SOURCE := 1
const FLOOR_SOURCE := 0
const PORTAL_POS := Vector2(978, 839)


func _initialize() -> void:
	var abs_path := ProjectSettings.globalize_path(MAP_PATH)
	var original := FileAccess.get_file_as_string(abs_path)
	if original.is_empty():
		push_error("failed to read woodland")
		quit(1)
		return

	var map: Node2D = load(MAP_PATH).instantiate()
	var walls: TileMapLayer = map.get_node("Walls")
	var features: TileMapLayer = map.get_node("Features")
	var decor: TileMapLayer = map.get_node("Decor")
	var wall_decor: TileMapLayer = map.get_node("WallDecor")

	# Restore west-face wall column.
	var restore := {
		Vector2i(62, 50): Vector2i(0, 2),
		Vector2i(62, 51): Vector2i(0, 4),
		Vector2i(62, 52): Vector2i(0, 5),
		Vector2i(62, 53): Vector2i(0, 6),
		Vector2i(62, 54): Vector2i(0, 7),
	}
	for cell: Vector2i in restore:
		walls.set_cell(cell, WALL_SOURCE, restore[cell])

	# Strip any WallDecor we may have stamped on this face (baked grass lips).
	for c in [Vector2i(62, 50), Vector2i(61, 50), Vector2i(61, 51), Vector2i(62, 53), Vector2i(60, 51)]:
		if wall_decor.get_cell_source_id(c) >= 0:
			wall_decor.erase_cell(c)

	# Extend dirt path under the portal to the cliff with an irregular terminus —
	# fill 11,10; edges match existing woodland path language.
	# Shape is intentionally NOT a rectangle: staggered north/south lips.
	var path := {
		# continue fill east toward cliff
		Vector2i(58, 50): Vector2i(11, 10),
		Vector2i(58, 51): Vector2i(11, 10),
		Vector2i(58, 52): Vector2i(11, 10),
		Vector2i(58, 53): Vector2i(11, 10),
		Vector2i(59, 50): Vector2i(11, 6), # north lip
		Vector2i(59, 51): Vector2i(11, 10),
		Vector2i(59, 52): Vector2i(11, 10),
		Vector2i(59, 53): Vector2i(11, 10),
		Vector2i(59, 54): Vector2i(11, 8), # south lip
		Vector2i(60, 51): Vector2i(11, 6),
		Vector2i(60, 52): Vector2i(11, 10),
		Vector2i(60, 53): Vector2i(11, 8),
		Vector2i(61, 51): Vector2i(12, 5), # NE corner toward wall
		Vector2i(61, 52): Vector2i(11, 6), # under portal, east lip against wall
		Vector2i(61, 53): Vector2i(14, 7), # SE corner
	}
	for cell: Vector2i in path:
		features.set_cell(cell, FLOOR_SOURCE, path[cell])

	# Clear bushes under portal.
	for c in [Vector2i(61, 51), Vector2i(61, 54), Vector2i(60, 51), Vector2i(60, 54)]:
		if decor.get_cell_source_id(c) >= 0:
			decor.erase_cell(c)

	print("walls_restored=", restore.size())
	print("path_extended=", path.size())

	original = _replace_layer_blob(original, "Walls", walls.tile_map_data)
	original = _replace_layer_blob(original, "Features", features.tile_map_data)
	original = _replace_layer_blob(original, "Decor", decor.tile_map_data)
	original = _replace_layer_blob(original, "WallDecor", wall_decor.tile_map_data)

	var portal_block := (
		"[node name=\"MiningCavePortal\" parent=\".\" unique_id=766829581 instance=ExtResource(\"4_2dprc\")]\n"
		+ "position = Vector2(%d, %d)\n" % [int(PORTAL_POS.x), int(PORTAL_POS.y)]
		+ "portal_color = Color(0.55, 0.62, 0.72, 1)\n"
		+ "destination_label = \"Mining Cave\""
	)
	var portal_re := RegEx.new()
	portal_re.compile(
		"\\[node name=\"MiningCavePortal\"[\\s\\S]*?destination_label = \"Mining Cave\""
	)
	var m := portal_re.search(original)
	if m == null:
		push_error("MiningCavePortal block not found")
		quit(1)
		return
	original = original.substr(0, m.get_start()) + portal_block + original.substr(m.get_end())

	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(original)
	f.close()
	print("wrote ", abs_path, " portal=", PORTAL_POS)
	quit(0)


func _replace_layer_blob(original: String, layer_name: String, data: PackedByteArray) -> String:
	var idx := original.find('[node name="%s"' % layer_name)
	if idx < 0:
		push_error("%s node not found" % layer_name)
		quit(1)
		return original
	var data_key := "tile_map_data = PackedByteArray(\""
	var data_idx := original.find(data_key, idx)
	if data_idx < 0:
		push_error("%s tile_map_data not found" % layer_name)
		quit(1)
		return original
	var start := data_idx + data_key.length()
	var end := original.find("\")", start)
	if end < 0:
		push_error("%s tile_map_data end not found" % layer_name)
		quit(1)
		return original
	return original.substr(0, start) + Marshalls.raw_to_base64(data) + original.substr(end)
