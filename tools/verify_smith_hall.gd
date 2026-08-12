extends SceneTree
## Headless checks for the Smith House move into the big hub hall.
## Run: godot --headless --path . -s tools/verify_smith_hall.gd
## Expect: VERIFY_PASS
##
## Reads the scenes as text (same approach as the other verify_* tools) so the
## check needs neither autoloads nor an import pass.

const CELL := 16
## Enlarged room, in cells: outer wall box and the walkable floor inside it.
const X0 := -21
const X1 := 21
const DOOR_X := 0
const FLOOR_Y0 := 8
const FLOOR_Y1 := 25
const BOTTOM_Y := 26

const STATIONS: PackedStringArray = [
	"FurnaceStation", "AnvilStation", "WorkBenchStation",
	"AscendedWorkBenchStation", "FletchingBenchStation",
]
## Crafting stations carry a 96x96 interaction box; keep them from overlapping.
const MIN_STATION_GAP := 96.0

var _failures: PackedStringArray = PackedStringArray()


func _init() -> void:
	_check_hub()
	_check_interior()

	if _failures.is_empty():
		print("VERIFY_PASS smith_hall")
		quit(0)
	else:
		print("VERIFY_FAIL")
		for line: String in _failures:
			print("  - ", line)
		quit(1)


func _check_hub() -> void:
	var text: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/hub.tscn"
	)
	var door_block: String = _block(text, "SmithHouse")
	if door_block.is_empty():
		_failures.append("hub is missing the SmithHouse warper")
		return

	# overworld.tscn uses warper_id 4 for its own smith door so the interior exit
	# (target_id 4) resolves from either map — this must not drift.
	if door_block.find("warper_id = 4") < 0:
		_failures.append("hub SmithHouse warper_id != 4 (interior exit would break)")

	var door: Vector2 = _position(door_block)
	var hall: Vector2 = _position(_block(text, "Guild_house"))
	if door.distance_to(hall) > 96.0:
		_failures.append("hub SmithHouse door %s is not on the big hall %s" % [door, hall])


func _check_interior() -> void:
	var text: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/smith_house/inside_map.tscn"
	)
	_check_room_shell(text)

	var floor_rect := Rect2(
		X0 * CELL + CELL, FLOOR_Y0 * CELL,
		(X1 - X0 - 1) * CELL, (FLOOR_Y1 - FLOOR_Y0 + 1) * CELL
	)

	var placed: Array[Vector2] = []
	for station_name: String in STATIONS:
		var block: String = _block(text, station_name)
		if block.is_empty():
			_failures.append("interior is missing %s" % station_name)
			continue
		var at: Vector2 = _position(block)
		if not floor_rect.has_point(at):
			_failures.append("%s at %s is outside the floor %s" % [station_name, at, floor_rect])
		for other: Vector2 in placed:
			if at.distance_to(other) < MIN_STATION_GAP:
				_failures.append("%s at %s crowds a station at %s" % [station_name, at, other])
		placed.append(at)

	var entrance: String = _block(text, "Entrance")
	if entrance.find("target_id = 4") < 0:
		_failures.append("interior Entrance target_id != 4")
	var spawn: Vector2 = _position(entrance)
	if absf(spawn.x - (DOOR_X * CELL + CELL / 2.0)) > 8.0:
		_failures.append("interior Entrance %s is not under the doorway" % spawn)

	for npc_name: String in ["ForgeSmith", "TheTailor"]:
		var at: Vector2 = _position(_block(text, npc_name))
		if not floor_rect.has_point(at):
			_failures.append("%s at %s is outside the floor" % [npc_name, at])


## Decodes the Walls layer and proves the room is a sealed box with exactly one
## doorway — the cheap way to catch a mis-generated tilemap.
func _check_room_shell(text: String) -> void:
	var data: PackedByteArray = _tile_map_data(_block(text, "Walls"))
	if data.is_empty():
		_failures.append("interior Walls layer has no tile data")
		return

	var walls: Dictionary = {}
	var offset: int = 2
	while offset + 12 <= data.size():
		walls[Vector2i(data.decode_s16(offset), data.decode_s16(offset + 2))] = true
		offset += 12

	for y: int in range(FLOOR_Y0, FLOOR_Y1 + 1):
		for x: int in range(X0 + 1, X1):
			if walls.has(Vector2i(x, y)):
				_failures.append("wall tile at (%d, %d) blocks the floor" % [x, y])
				return

	var gaps: PackedInt32Array = PackedInt32Array()
	for x: int in range(X0, X1 + 1):
		if not walls.has(Vector2i(x, BOTTOM_Y)):
			gaps.append(x)
	if gaps.size() != 1 or gaps[0] != DOOR_X:
		_failures.append("bottom wall should have one doorway at x=%d, found %s"
			% [DOOR_X, gaps])

	for y: int in range(FLOOR_Y0, BOTTOM_Y):
		for x: int in [X0, X1]:
			if not walls.has(Vector2i(x, y)):
				_failures.append("side wall has a hole at (%d, %d)" % [x, y])
				return


func _block(text: String, node_name: String) -> String:
	var start: int = text.find('[node name="%s"' % node_name)
	if start < 0:
		return ""
	var end: int = text.find("\n[node ", start + 1)
	return text.substr(start, -1 if end < 0 else end - start)


func _position(block: String) -> Vector2:
	const KEY := "position = Vector2("
	var start: int = block.find(KEY)
	if start < 0:
		return Vector2.ZERO
	start += KEY.length()
	var parts: PackedStringArray = block.substr(
		start, block.find(")", start) - start
	).split(",")
	return Vector2(parts[0].to_float(), parts[1].to_float())


func _tile_map_data(block: String) -> PackedByteArray:
	const KEY := 'tile_map_data = PackedByteArray("'
	var start: int = block.find(KEY)
	if start < 0:
		return PackedByteArray()
	start += KEY.length()
	return Marshalls.base64_to_raw(block.substr(start, block.find('"', start) - start))
