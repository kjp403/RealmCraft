extends SceneTree
## Rewrite Mining Cave Props rocks to wall-aligned spots, clear of portal keepout.
## Run: godot --headless --path . -s tools/reposition_mining_rocks.gd

const MAP_PATH := "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"

const ROCKS: Array = [
	{"tile": Vector2i(6, 16), "atlas": Vector2i(2, 1)},
	{"tile": Vector2i(12, 16), "atlas": Vector2i(2, 1)},
	{"tile": Vector2i(22, 6), "atlas": Vector2i(2, 1)},
	{"tile": Vector2i(24, 19), "atlas": Vector2i(6, 1)},
	{"tile": Vector2i(36, 27), "atlas": Vector2i(2, 7)},
	{"tile": Vector2i(40, 25), "atlas": Vector2i(8, 1)},
	{"tile": Vector2i(52, 13), "atlas": Vector2i(8, 1)},
	{"tile": Vector2i(48, 20), "atlas": Vector2i(0, 7)},
	{"tile": Vector2i(61, 15), "atlas": Vector2i(2, 1)},
]


func _initialize() -> void:
	var abs_path := ProjectSettings.globalize_path(MAP_PATH)
	var original := FileAccess.get_file_as_string(abs_path)
	if original.is_empty():
		push_error("failed to read mining_cave")
		quit(1)
		return

	var packed: PackedScene = load(MAP_PATH)
	var map: Node2D = packed.instantiate()
	var props: TileMapLayer = map.get_node("Tiles/Props")
	props.clear()
	for rock in ROCKS:
		props.set_cell(rock["tile"], 4, rock["atlas"])
		print("rock ", rock["tile"], " atlas=", rock["atlas"])

	var new_b64 := Marshalls.raw_to_base64(props.tile_map_data)
	var props_idx := original.find('[node name="Props"')
	if props_idx < 0:
		push_error("Props node missing")
		quit(1)
		return
	var data_key := "tile_map_data = PackedByteArray(\""
	var data_idx := original.find(data_key, props_idx)
	var start := data_idx + data_key.length()
	var end := original.find("\")", start)
	var updated := original.substr(0, start) + new_b64 + original.substr(end)
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(updated)
	f.close()
	print("wrote props rocks=", ROCKS.size())
	quit(0)
