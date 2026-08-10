extends SceneTree
## Cut a mid-ridge passage by rewriting ONLY the Walls tile_map_data blob
## in woodland_tiles.tscn (keeps format=4 + uids intact).
## Run: godot --headless --path . -s tools/cut_west_passage.gd

const MAP_PATH := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"

func _initialize() -> void:
	var abs_path := ProjectSettings.globalize_path(MAP_PATH)
	var original := FileAccess.get_file_as_string(abs_path)
	if original.is_empty():
		push_error("failed to read woodland")
		quit(1)
		return

	var packed: PackedScene = load(MAP_PATH)
	var map: Node2D = packed.instantiate()
	var walls: TileMapLayer = map.find_child("Walls", true, false) as TileMapLayer
	if walls == null:
		push_error("no Walls layer")
		quit(1)
		return

	var erased := 0
	# 4-tile-tall corridor through mid-ridge (tiles x=52..74, y=36..39)
	for y in range(36, 40):
		for x in range(52, 75):
			var c := Vector2i(x, y)
			if walls.get_cell_source_id(c) >= 0:
				walls.erase_cell(c)
				erased += 1
	print("erased=", erased)

	var new_b64 := Marshalls.raw_to_base64(walls.tile_map_data)
	# Replace Walls tile_map_data in original text. Format 4 stores it as
	# tile_map_data = PackedByteArray("...")
	var walls_idx := original.find('[node name="Walls"')
	if walls_idx < 0:
		push_error("Walls node not found")
		quit(1)
		return
	var data_key := "tile_map_data = PackedByteArray(\""
	var data_idx := original.find(data_key, walls_idx)
	if data_idx < 0:
		push_error("Walls tile_map_data not found")
		quit(1)
		return
	var start := data_idx + data_key.length()
	var end := original.find("\")", start)
	if end < 0:
		push_error("Walls tile_map_data end not found")
		quit(1)
		return
	var updated := original.substr(0, start) + new_b64 + original.substr(end)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(updated)
	f.close()
	print("wrote ", abs_path, " walls_b64_len=", new_b64.length())
	# Keep portal/camera from current file (already edited in text before this run)
	quit(0)
