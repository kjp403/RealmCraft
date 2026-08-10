extends SceneTree
const MAP_PATH := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
func _initialize() -> void:
	var abs_path := ProjectSettings.globalize_path(MAP_PATH)
	var original := FileAccess.get_file_as_string(abs_path)
	var packed: PackedScene = load(MAP_PATH)
	var map: Node2D = packed.instantiate()
	var walls: TileMapLayer = map.find_child("Walls", true, false) as TileMapLayer
	var erased := 0
	# Wide corridor through mid-ridge so east bowl can walk west freely
	for y in range(34, 42):
		for x in range(50, 76):
			var c := Vector2i(x, y)
			if walls.get_cell_source_id(c) >= 0:
				walls.erase_cell(c)
				erased += 1
	print("erased=", erased)
	var new_b64 := Marshalls.raw_to_base64(walls.tile_map_data)
	var walls_idx := original.find('[node name="Walls"')
	var data_key := "tile_map_data = PackedByteArray(\""
	var data_idx := original.find(data_key, walls_idx)
	var start := data_idx + data_key.length()
	var end := original.find("\")", start)
	var updated := original.substr(0, start) + new_b64 + original.substr(end)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(updated)
	f.close()
	print("saved")
	quit(0)
