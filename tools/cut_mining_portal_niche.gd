extends SceneTree
## Carve a shallow standable doorway at the Mining Cave portal face
## (world 978,839). Rewrites Walls tile_map_data only.
## Run: godot --headless --path . -s tools/cut_mining_portal_niche.gd

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

	# Portal 40x40 at (978,839) east-overlaps wall column x=62.
	# Clear one column (plus 1 tile padding N/S) so players can stand in it.
	var erased := 0
	for y in range(50, 55):
		var c := Vector2i(62, y)
		if walls.get_cell_source_id(c) >= 0:
			walls.erase_cell(c)
			erased += 1
	print("erased=", erased)

	var new_b64 := Marshalls.raw_to_base64(walls.tile_map_data)
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
	quit(0)
