extends SceneTree

## Rebuild Hollow Ground/Walls/Props tile_map_data.
## Run: godot --headless --path . -s tools/build_hollow_tiles.gd
## Then splice /tmp/hollow_{ground,walls,props}.b64 into the_hollow.tscn
## (or let this script rewrite the tscn directly).

const TILESET := "res://source/common/gameplay/maps/tilesets/mining_cave_tileset.tres"
const TSCN := "res://source/common/gameplay/maps/maps/the_hollow/the_hollow.tscn"

func _initialize() -> void:
	var ts: TileSet = load(TILESET)
	var ground := TileMapLayer.new()
	ground.tile_set = ts
	var walls := TileMapLayer.new()
	walls.tile_set = ts
	var props := TileMapLayer.new()
	props.tile_set = ts

	const X0 := 0
	const Y0 := 0
	const X1 := 59
	const Y1 := 44
	const INSET := 2
	var cx: int = int((X0 + X1) / 2)
	var cy: int = int((Y0 + Y1) / 2)

	var floors: Array[Vector2i] = [
		Vector2i(8, 15), Vector2i(7, 15), Vector2i(9, 15), Vector2i(8, 14),
		Vector2i(10, 15), Vector2i(6, 15), Vector2i(8, 16), Vector2i(7, 14),
		Vector2i(9, 14), Vector2i(10, 14)
	]
	# Boss-pad tint comes from BossPad Polygon2D — do NOT use atlas (11-14,15):
	# those cells are empty/black fragments and show as void holes in-game.
	var darks: Array[Vector2i] = [
		Vector2i(8, 15), Vector2i(7, 15), Vector2i(9, 15), Vector2i(8, 14), Vector2i(10, 15)
	]

	# Full multi-tile ORIGINS only — fragment atlas cells render as half-rocks.
	var rocks: Array[Dictionary] = [
		{"atlas": Vector2i(0, 1), "size": Vector2i(2, 3)},
		{"atlas": Vector2i(2, 1), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(6, 1), "size": Vector2i(2, 3)},
		{"atlas": Vector2i(8, 1), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(0, 7), "size": Vector2i(2, 3)},
		{"atlas": Vector2i(2, 7), "size": Vector2i(2, 2)},
	]
	var cave_props: Array[Dictionary] = [
		{"atlas": Vector2i(16, 0), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(18, 0), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(20, 0), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(22, 0), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(16, 2), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(18, 2), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(20, 2), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(22, 2), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(12, 0), "size": Vector2i(4, 3)},
		{"atlas": Vector2i(12, 3), "size": Vector2i(4, 3)},
	]
	var crystals: Array[Dictionary] = [
		{"atlas": Vector2i(10, 6), "size": Vector2i(4, 6)},
		{"atlas": Vector2i(14, 6), "size": Vector2i(4, 6)},
	]
	var formations: Array[Dictionary] = [
		{"atlas": Vector2i(12, 7), "size": Vector2i(3, 3)},
		{"atlas": Vector2i(9, 7), "size": Vector2i(3, 3)},
		{"atlas": Vector2i(6, 7), "size": Vector2i(3, 4)},
		{"atlas": Vector2i(11, 10), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(9, 10), "size": Vector2i(2, 2)},
		{"atlas": Vector2i(13, 10), "size": Vector2i(2, 2)},
	]

	for y in range(Y0, Y1 + 1):
		for x in range(X0, X1 + 1):
			var edge: bool = x < X0 + INSET or x > X1 - INSET or y < Y0 + INSET or y > Y1 - INSET
			var portal_gap: bool = y > Y1 - INSET and x >= cx - 3 and x <= cx + 3
			if edge and not portal_gap:
				var inner: bool = x == X0 + INSET - 1 or x == X1 - INSET + 1 or y == Y0 + INSET - 1 or y == Y1 - INSET + 1
				walls.set_cell(Vector2i(x, y), 0, Vector2i(1, 0) if inner else Vector2i(2, 0))
			else:
				var dx: int = x - cx
				var dy: int = y - (cy - 4)
				var dist2: int = dx * dx + dy * dy
				var h: int = (x * 73856093) ^ (y * 19349663)
				var atlas: Vector2i = darks[absi(h) % darks.size()] if dist2 <= 36 else floors[absi(h) % floors.size()]
				ground.set_cell(Vector2i(x, y), 0, atlas)

	var occupied: Dictionary = {}
	var min_x: int = X0 + INSET + 1
	var max_x: int = X1 - INSET - 1
	var min_y: int = Y0 + INSET + 1
	var max_y: int = Y1 - INSET - 1
	var boss := Vector2i(cx, cy - 4)

	var try_place := func(source: int, origin: Vector2i, atlas: Vector2i, size: Vector2i, pad: int) -> bool:
		if origin.x < min_x or origin.y < min_y:
			return false
		if origin.x + size.x - 1 > max_x or origin.y + size.y - 1 > max_y:
			return false
		for oy in range(size.y):
			for ox in range(size.x):
				var cell := origin + Vector2i(ox, oy)
				if absi(cell.x - boss.x) <= 5 and absi(cell.y - boss.y) <= 4:
					return false
		for oy2 in range(-pad, size.y + pad):
			for ox2 in range(-pad, size.x + pad):
				if occupied.has(origin + Vector2i(ox2, oy2)):
					return false
		for oy3 in range(-pad, size.y + pad):
			for ox3 in range(-pad, size.x + pad):
				occupied[origin + Vector2i(ox3, oy3)] = true
		props.set_cell(origin, source, atlas)
		return true

	# 1) Corner accents first (crystals / formations / cave props)
	var accent_spots: Array[Vector2i] = [
		Vector2i(X0 + 4, Y0 + 4), Vector2i(X1 - 10, Y0 + 4),
		Vector2i(X0 + 4, Y1 - 12), Vector2i(X1 - 10, Y1 - 12),
		Vector2i(X0 + 5, cy - 4), Vector2i(X1 - 11, cy - 4),
		Vector2i(cx - 18, Y0 + 5), Vector2i(cx + 12, Y0 + 5),
		Vector2i(cx - 20, cy + 2), Vector2i(cx + 14, cy + 2),
		Vector2i(X0 + 6, Y0 + 14), Vector2i(X1 - 12, Y0 + 14),
		Vector2i(X0 + 6, Y1 - 16), Vector2i(X1 - 12, Y1 - 16),
	]
	var accent_placed: int = 0
	for i in range(accent_spots.size()):
		var spot: Vector2i = accent_spots[i]
		var h2: int = (spot.x * 73856093) ^ (spot.y * 19349663)
		var placed := false
		if i % 5 == 0:
			var cry: Dictionary = crystals[absi(h2) % crystals.size()]
			placed = try_place.call(1, spot, cry["atlas"], cry["size"], 1)
		elif i % 3 == 0:
			var form: Dictionary = formations[absi(h2) % formations.size()]
			placed = try_place.call(0, spot, form["atlas"], form["size"], 1)
		else:
			var cp: Dictionary = cave_props[absi(h2) % cave_props.size()]
			placed = try_place.call(1, spot, cp["atlas"], cp["size"], 1)
		if placed:
			accent_placed += 1

	# 2) Boss ring — full rocks only, spaced
	var ring_placed: int = 0
	for i in range(14):
		var ang: float = float(i) * TAU / 14.0 + 0.15
		var rx: int = int(round(float(cx) + cos(ang) * 13.0))
		var ry: int = int(round(float(cy - 4) + sin(ang) * 10.0))
		var rock: Dictionary = rocks[i % rocks.size()]
		if try_place.call(4, Vector2i(rx, ry), rock["atlas"], rock["size"], 1):
			ring_placed += 1

	# 3) Mid-arena sparse full rocks
	var mid_placed: int = 0
	for y in range(min_y + 2, max_y - 1, 4):
		for x in range(min_x + 2, max_x - 1, 5):
			var h4: int = (x * 50331653) ^ (y * 100665521)
			if absi(h4) % 2 != 0:
				continue
			var rock3: Dictionary = rocks[absi(h4) % rocks.size()]
			if try_place.call(4, Vector2i(x, y), rock3["atlas"], rock3["size"], 1):
				mid_placed += 1

	# 4) Wall-hugging rubble last
	var wall_placed: int = 0
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var near_wall: bool = x <= X0 + 7 or x >= X1 - 8 or y <= Y0 + 7 or y >= Y1 - 9
			if not near_wall:
				continue
			var h3: int = (x * 83492791) ^ (y * 2971215073)
			if absi(h3) % 4 != 0:
				continue
			var rock2: Dictionary = rocks[absi(h3) % rocks.size()]
			if try_place.call(4, Vector2i(x, y), rock2["atlas"], rock2["size"], 1):
				wall_placed += 1

	print("props=", props.get_used_cells().size(),
		" accent=", accent_placed, " ring=", ring_placed,
		" mid=", mid_placed, " wall=", wall_placed)

	var bad: int = 0
	var allowed4: Array[Vector2i] = []
	for r in rocks:
		allowed4.append(r["atlas"])
	var allowed1: Array[Vector2i] = []
	for r in cave_props + crystals:
		allowed1.append(r["atlas"])
	var allowed0: Array[Vector2i] = []
	for r in formations:
		allowed0.append(r["atlas"])
	for cell in props.get_used_cells():
		var sid: int = props.get_cell_source_id(cell)
		var ac: Vector2i = props.get_cell_atlas_coords(cell)
		var ok := (sid == 4 and ac in allowed4) or (sid == 1 and ac in allowed1) or (sid == 0 and ac in allowed0)
		if not ok:
			bad += 1
			print("BAD ", cell, " ", sid, " ", ac)
	print("bad_props=", bad)

	# Splice into tscn
	var path := ProjectSettings.globalize_path(TSCN)
	var text := FileAccess.get_file_as_string(path)
	text = _replace_layer(text, "Ground", Marshalls.raw_to_base64(ground.tile_map_data))
	text = _replace_layer(text, "Walls", Marshalls.raw_to_base64(walls.tile_map_data))
	text = _replace_layer(text, "Props", Marshalls.raw_to_base64(props.tile_map_data))
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(text)
	out.close()

	# Also dump bins for preview tools
	for path_name in ["ground", "walls", "props"]:
		var layer: TileMapLayer = ground if path_name == "ground" else (walls if path_name == "walls" else props)
		var f: FileAccess = FileAccess.open("/tmp/hollow_%s.b64" % path_name, FileAccess.WRITE)
		f.store_string(Marshalls.raw_to_base64(layer.tile_map_data))
		f.close()
		f = FileAccess.open("/tmp/hollow_%s.bin" % path_name, FileAccess.WRITE)
		f.store_buffer(layer.tile_map_data)
		f.close()

	print("OK wrote ", path)
	quit(0)


func _replace_layer(text: String, node_name: String, b64: String) -> String:
	var key := '[node name="%s" type="TileMapLayer"' % node_name
	var start := text.find(key)
	if start < 0:
		push_error("missing layer " + node_name)
		return text
	var data_key := "tile_map_data = PackedByteArray(\""
	var data_start := text.find(data_key, start)
	if data_start < 0:
		push_error("missing tile_map_data for " + node_name)
		return text
	data_start += data_key.length()
	var data_end := text.find("\")", data_start)
	return text.substr(0, data_start) + b64 + text.substr(data_end)
