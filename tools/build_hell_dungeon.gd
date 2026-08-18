extends SceneTree
## Paint The Brimstone Vault — 5 combat rooms + boss, 32×32 hell tiles.
##   godot --headless --path . -s tools/build_hell_tileset.gd
##   godot --headless --path . -s tools/build_hell_dungeon.gd

const MapKit := preload("res://tools/lib/mapkit.gd")

const OUT := "res://source/common/gameplay/maps/maps/hell_dungeon/hell_dungeon.tscn"
const TILESET := "res://source/common/gameplay/maps/tilesets/hell_tileset.tres"

## True walkable fills: the 3×3 room 'interiors' on this sheet are transparent,
## and the cells beside them carry wall fringe. Only the oval-bank fills are
## actually floor.
const FLOOR_DARK: Array[Vector2i] = [
	Vector2i(8, 8), Vector2i(2, 7), Vector2i(7, 8),
]
const FLOOR_WORN: Array[Vector2i] = [
	Vector2i(1, 6), Vector2i(3, 6), Vector2i(1, 8), Vector2i(3, 8),
]
## Hollow 3×3 centre — transparent, colliding. The well is a hole, not a floor.
const VOID_PIT := Vector2i(1, 1)
## 3×3 room rims, four variants. Index: NW N NE / W · E / SW S SE.
const RIM_NW: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]
const RIM_N: Array[Vector2i] = [Vector2i(1, 0), Vector2i(4, 0), Vector2i(1, 3), Vector2i(4, 3)]
const RIM_NE: Array[Vector2i] = [Vector2i(2, 0), Vector2i(5, 0), Vector2i(2, 3), Vector2i(5, 3)]
const RIM_W: Array[Vector2i] = [Vector2i(0, 1), Vector2i(3, 1), Vector2i(0, 4), Vector2i(3, 4)]
const RIM_E: Array[Vector2i] = [Vector2i(2, 1), Vector2i(5, 1), Vector2i(2, 4), Vector2i(5, 4)]
const RIM_SW: Array[Vector2i] = [Vector2i(0, 2), Vector2i(3, 2), Vector2i(0, 5), Vector2i(3, 5)]
const RIM_S: Array[Vector2i] = [Vector2i(1, 2), Vector2i(4, 2), Vector2i(1, 5), Vector2i(4, 5)]
const RIM_SE: Array[Vector2i] = [Vector2i(2, 2), Vector2i(5, 2), Vector2i(2, 5), Vector2i(5, 5)]

const DEBRIS: Array[Vector2i] = [
	Vector2i(9, 6), Vector2i(10, 6), Vector2i(11, 6),
	Vector2i(9, 7), Vector2i(10, 7), Vector2i(11, 7), Vector2i(12, 7),
	Vector2i(9, 8), Vector2i(12, 8),
]


func _initialize() -> void:
	var ts: TileSet = load(TILESET) as TileSet
	assert(ts != null, "run tools/build_hell_tileset.gd first")

	var ground := TileMapLayer.new()
	var detail := TileMapLayer.new()
	var walls := TileMapLayer.new()
	var props := TileMapLayer.new()
	ground.tile_set = ts
	detail.tile_set = ts
	walls.tile_set = ts
	props.tile_set = ts

	var walk: Dictionary = {}
	var pit: Dictionary = {}
	var keepout: Dictionary = {}
	_fill_rect(walk, 0, 0, 15, 12)           # lobby
	_fill_rect(walk, 0, -22, 17, -8)         # room 1
	_fill_rect(walk, 7, -7, 9, -1)           # corridor 1
	_fill_rect(walk, -2, -50, 20, -30)       # room 2
	_fill_rect(walk, 7, -29, 9, -23)         # corridor 2
	_fill_rect(walk, -4, -82, 24, -58)       # room 3
	_fill_rect(walk, 8, -57, 10, -51)        # corridor 3
	_fill_rect(walk, 0, -110, 19, -90)       # room 4
	_fill_rect(walk, 8, -89, 10, -83)        # corridor 4
	_fill_rect(walk, -2, -142, 22, -118)     # room 5
	_fill_rect(walk, 8, -117, 10, -111)      # corridor 5 (room 5 → room 4)
	_fill_rect(walk, 23, -134, 29, -126)     # east hall to the Queen
	_fill_rect(walk, 30, -146, 58, -116)     # final
	for rect in [
		[7, -7, 9, -1], [7, -29, 9, -23], [8, -57, 10, -51],
		[8, -89, 10, -83], [8, -117, 10, -111], [23, -134, 29, -126],
	]:
		_fill_rect(keepout, rect[0], rect[1], rect[2], rect[3])
	# One-cell mouths so pillars/spikes never sit on a door or corridor line.
	var mouths: Array[Vector2i] = []
	for cell: Vector2i in walk.keys():
		if keepout.has(cell):
			continue
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if keepout.has(cell + d):
				mouths.append(cell)
				break
	for cell: Vector2i in mouths:
		keepout[cell] = true

	# Brimstone well in room 3 — hole in the floor, rimmed with the same wall set.
	_fill_rect(pit, 4, -74, 16, -66)
	for cell: Vector2i in pit.keys():
		walk.erase(cell)

	var rooms: Array = [
		{"c": Vector2i(7, 6), "r": 4.0, "s": 51},
		{"c": Vector2i(8, -15), "r": 5.5, "s": 52},
		{"c": Vector2i(9, -40), "r": 7.0, "s": 53},
		{"c": Vector2i(10, -70), "r": 6.5, "s": 54},
		{"c": Vector2i(9, -100), "r": 6.0, "s": 55},
		{"c": Vector2i(10, -130), "r": 7.0, "s": 56},
		{"c": Vector2i(44, -131), "r": 9.0, "s": 57},
	]
	var min_c := Vector2i(999, 999)
	var max_c := Vector2i(-999, -999)
	for cell: Vector2i in walk.keys():
		min_c = Vector2i(mini(min_c.x, cell.x), mini(min_c.y, cell.y))
		max_c = Vector2i(maxi(max_c.x, cell.x), maxi(max_c.y, cell.y))
	for cell: Vector2i in pit.keys():
		min_c = Vector2i(mini(min_c.x, cell.x), mini(min_c.y, cell.y))
		max_c = Vector2i(maxi(max_c.x, cell.x), maxi(max_c.y, cell.y))
	var bounds := Rect2i(min_c.x - 2, min_c.y - 2, max_c.x - min_c.x + 5, max_c.y - min_c.y + 5)

	_paint_floors(ground, walk)
	_paint_worn_patches(ground, walk, rooms, bounds)
	_paint_well(ground, pit)
	_paint_walls(walls, walk)
	_paint_debris(detail, walk, pit, keepout, bounds)
	_paint_props(props, walk, pit, keepout, bounds)

	var ground_b64 := MapKit.to_base64(ground)
	var detail_b64 := MapKit.to_base64(detail)
	var walls_b64 := MapKit.to_base64(walls)
	var props_b64 := MapKit.to_base64(props)

	_write_tscn(ground_b64, detail_b64, walls_b64, props_b64, min_c, max_c)
	print("HELL_DUNGEON_PASS ", OUT)
	quit(0)


func _fill_rect(mask: Dictionary, x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			mask[Vector2i(x, y)] = true


func _paint_floors(layer: TileMapLayer, walk: Dictionary) -> void:
	for cell: Vector2i in walk.keys():
		# Low-frequency noise so neighbouring cells share a fill — not a hash
		# checkerboard of wall-edge tiles.
		var n: float = MapKit.value_noise(float(cell.x), float(cell.y), 9.0, 41)
		var atlas: Vector2i
		if n < 0.50:
			atlas = FLOOR_DARK[0]
		elif n < 0.82:
			atlas = FLOOR_DARK[1]
		else:
			atlas = FLOOR_DARK[2]
		layer.set_cell(cell, 0, atlas)


func _paint_worn_patches(layer: TileMapLayer, walk: Dictionary, rooms: Array, bounds: Rect2i) -> void:
	for patch: Dictionary in rooms:
		var blob_mask: Dictionary = {}
		MapKit.blob(blob_mask, patch["c"], float(patch["r"]), 0.28, int(patch["s"]), bounds)
		blob_mask = MapKit.smooth(blob_mask, bounds, 2, 5, 4)
		for cell: Vector2i in blob_mask.keys():
			if not walk.has(cell):
				continue
			layer.set_cell(cell, 0, MapKit._pick(FLOOR_WORN, cell, int(patch["s"])))


func _paint_well(layer: TileMapLayer, pit: Dictionary) -> void:
	for cell: Vector2i in pit.keys():
		layer.set_cell(cell, 0, VOID_PIT)


func _paint_walls(layer: TileMapLayer, walk: Dictionary) -> void:
	var rim: Dictionary = {}
	for cell: Vector2i in walk.keys():
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cell + d
			if not walk.has(n):
				rim[n] = true
	for cell: Vector2i in rim.keys():
		var north := walk.has(cell + Vector2i.UP)
		var south := walk.has(cell + Vector2i.DOWN)
		var west := walk.has(cell + Vector2i.LEFT)
		var east := walk.has(cell + Vector2i.RIGHT)
		var atlas: Vector2i
		if south and east:
			atlas = MapKit._pick(RIM_NW, cell, 3)
		elif south and west:
			atlas = MapKit._pick(RIM_NE, cell, 3)
		elif north and east:
			atlas = MapKit._pick(RIM_SW, cell, 3)
		elif north and west:
			atlas = MapKit._pick(RIM_SE, cell, 3)
		elif south:
			var floor_sw := walk.has(cell + Vector2i(-1, 1))
			var floor_se := walk.has(cell + Vector2i(1, 1))
			if not floor_sw:
				atlas = MapKit._pick(RIM_NW, cell, 3)
			elif not floor_se:
				atlas = MapKit._pick(RIM_NE, cell, 3)
			else:
				atlas = MapKit._pick(RIM_N, cell, 3)
		elif north:
			var floor_nw := walk.has(cell + Vector2i(-1, -1))
			var floor_ne := walk.has(cell + Vector2i(1, -1))
			if not floor_nw:
				atlas = MapKit._pick(RIM_SW, cell, 3)
			elif not floor_ne:
				atlas = MapKit._pick(RIM_SE, cell, 3)
			else:
				atlas = MapKit._pick(RIM_S, cell, 3)
		elif east:
			var floor_ne := walk.has(cell + Vector2i(1, -1))
			var floor_se := walk.has(cell + Vector2i(1, 1))
			if not floor_ne:
				atlas = MapKit._pick(RIM_NW, cell, 3)
			elif not floor_se:
				atlas = MapKit._pick(RIM_SW, cell, 3)
			else:
				atlas = MapKit._pick(RIM_W, cell, 3)
		elif west:
			var floor_nw := walk.has(cell + Vector2i(-1, -1))
			var floor_sw := walk.has(cell + Vector2i(-1, 1))
			if not floor_nw:
				atlas = MapKit._pick(RIM_NE, cell, 3)
			elif not floor_sw:
				atlas = MapKit._pick(RIM_SE, cell, 3)
			else:
				atlas = MapKit._pick(RIM_E, cell, 3)
		else:
			continue
		layer.set_cell(cell, 0, atlas)


func _paint_debris(
	layer: TileMapLayer,
	walk: Dictionary,
	pit: Dictionary,
	keepout: Dictionary,
	bounds: Rect2i
) -> void:
	var blocked: Dictionary = {}
	for cell: Vector2i in pit.keys():
		blocked[cell] = true
	var inner: Array = MapKit.interior_cells(walk, blocked, 1)
	var spots: Array[Vector2i] = MapKit.scatter(inner, 0.22, 2, 90, func(cell: Vector2i) -> bool:
		return not keepout.has(cell)
	)
	for cell: Vector2i in spots:
		layer.set_cell(cell, 0, MapKit._pick(DEBRIS, cell, 12))


func _paint_props(
	layer: TileMapLayer,
	walk: Dictionary,
	pit: Dictionary,
	keepout: Dictionary,
	bounds: Rect2i
) -> void:
	var blocked: Dictionary = {}
	for cell: Vector2i in pit.keys():
		blocked[cell] = true
	var allowed: Dictionary = {}
	for cell: Vector2i in walk.keys():
		if keepout.has(cell):
			continue
		allowed[cell] = true
	var edges: Array = MapKit.edge_cells(walk, blocked)
	var edge_allowed: Dictionary = {}
	for cell: Vector2i in edges:
		if allowed.has(cell):
			edge_allowed[cell] = true

	var stumps: Array = [
		MapKit.rect_cluster(13, 4, 1, 1),
		MapKit.rect_cluster(14, 4, 1, 1),
		MapKit.rect_cluster(13, 2, 1, 1),
	]
	var spikes: Array = [
		MapKit.rect_cluster(15, 2, 1, 1),
		MapKit.rect_cluster(16, 2, 1, 1),
		MapKit.rect_cluster(15, 3, 2, 1),
	]
	var pillars: Array = [
		MapKit.rect_cluster(13, 3, 2, 3),
		MapKit.rect_cluster(13, 5, 2, 1),
	]
	var pools: Array = [
		MapKit.rect_cluster(13, 0, 2, 2),
	]

	var used: Dictionary = {}
	_stamp_scattered(layer, stumps, edge_allowed, used, bounds, 0.22, 5, 71)
	_stamp_scattered(layer, spikes, edge_allowed, used, bounds, 0.12, 6, 72)
	_stamp_scattered(layer, pillars, edge_allowed, used, bounds, 0.06, 8, 73)

	# Cyan wells on the walkable pit rim and in the queen arena.
	for origin in [Vector2i(2, -73), Vector2i(17, -66), Vector2i(38, -140), Vector2i(50, -122)]:
		if used.has(origin):
			continue
		var placed: Array[Vector2i] = MapKit.stamp_cluster(layer, 0, pools[0], origin, allowed, bounds)
		for cell: Vector2i in placed:
			used[cell] = true
			allowed.erase(cell)


func _stamp_scattered(
	layer: TileMapLayer,
	clusters: Array,
	allowed: Dictionary,
	used: Dictionary,
	bounds: Rect2i,
	density: float,
	spacing: int,
	seed_value: int
) -> void:
	var candidates: Array = allowed.keys()
	var spots: Array[Vector2i] = MapKit.scatter(candidates, density, spacing, seed_value)
	var i: int = 0
	for origin: Vector2i in spots:
		if used.has(origin) or not allowed.has(origin):
			continue
		var cluster: Dictionary = clusters[i % clusters.size()]
		i += 1
		var fit := true
		for atlas: Vector2i in cluster["cells"]:
			var target: Vector2i = origin + (atlas - cluster["origin"])
			if used.has(target) or not allowed.has(target):
				fit = false
				break
		if not fit:
			continue
		var placed: Array[Vector2i] = MapKit.stamp_cluster(layer, 0, cluster, origin, allowed, bounds)
		for cell: Vector2i in placed:
			used[cell] = true
			allowed.erase(cell)


func _px(x: float, y: float) -> Vector2:
	return Vector2(x * 32.0 + 16.0, y * 32.0 + 16.0)


func _room_center(x0: int, y0: int, x1: int, y1: int) -> Vector2:
	return _px(float(x0 + x1) / 2.0, float(y0 + y1) / 2.0)


func _room_poly(x0: int, y0: int, x1: int, y1: int, center: Vector2) -> PackedVector2Array:
	var tl := _px(float(x0), float(y0)) - center + Vector2(20, 20)
	var br := _px(float(x1), float(y1)) - center - Vector2(20, 20)
	return PackedVector2Array([
		Vector2(tl.x, tl.y), Vector2(br.x, tl.y), Vector2(br.x, br.y), Vector2(tl.x, br.y)
	])


func _poly_text(poly: PackedVector2Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for p: Vector2 in poly:
		parts.append("%s, %s" % [snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
	return "PackedVector2Array(" + ", ".join(parts) + ")"


func _doors_h(name_base: String, cx: float, cy: float) -> String:
	var text := ""
	var xs := [cx - 16.0, cx, cx + 16.0]
	for i in xs.size():
		var suffix := "" if i == 0 else str(i + 1)
		text += (
			"[node name=\"%s%s\" parent=\"ReplicatedPropsContainer\" instance=ExtResource(\"door\")]\n"
			+ "position = Vector2(%s, %s)\n\n"
		) % [name_base, suffix, str(xs[i]), str(cy)]
	return text


func _doors_v(name_base: String, cx: float, cy: float) -> String:
	var text := ""
	var ys := [cy - 16.0, cy, cy + 16.0]
	for i in ys.size():
		var suffix := "" if i == 0 else str(i + 1)
		text += (
			"[node name=\"%s%s\" parent=\"ReplicatedPropsContainer\" instance=ExtResource(\"door\")]\n"
			+ "position = Vector2(%s, %s)\n\n"
		) % [name_base, suffix, str(cx), str(ys[i])]
	return text


func _markers(parent: String, specs: Array) -> String:
	var text := ""
	var i := 0
	for spec: Dictionary in specs:
		i += 1
		var node_name: String = str(spec.get("name", "Mob")) + str(i)
		var extra := ""
		if int(spec.get("wave", 0)) > 0:
			extra += "wave = %d\n" % int(spec["wave"])
		if bool(spec.get("boss", false)):
			extra += "boss = true\n"
		text += (
			"[node name=\"%s\" parent=\"%s\" instance=ExtResource(\"marker\")]\n"
			+ "position = Vector2(%s, %s)\n"
			+ "enemy_type = ExtResource(\"%s\")\n%s\n"
		) % [node_name, parent, str(spec["x"]), str(spec["y"]), spec["type"], extra]
	return text


func _write_tscn(ground_b64: String, detail_b64: String, walls_b64: String, props_b64: String, min_c: Vector2i, max_c: Vector2i) -> void:
	var r1c := _room_center(0, -22, 17, -8)
	var r2c := _room_center(-2, -50, 20, -30)
	var r3c := _room_center(-4, -82, 24, -58)
	var r4c := _room_center(0, -110, 19, -90)
	var r5c := _room_center(-2, -142, 22, -118)
	var rfc := _room_center(30, -146, 58, -116)
	var lobby := _px(7.5, 10.0)
	var lost := _px(4.0, 9.0)

	var d1 := _px(8.0, -22.0)
	var d2 := _px(8.5, -50.0)
	var d3 := _px(9.0, -82.0)
	var d4 := _px(8.5, -110.0)
	var d5 := _px(22.0, -130.0)

	var tp1a := Vector2(d1.x, d1.y - 24.0)
	var tp1b := _px(8.0, -30.0)
	var tp2a := Vector2(d2.x, d2.y - 24.0)
	var tp2b := _px(9.0, -58.0)
	var tp3a := Vector2(d3.x, d3.y - 24.0)
	var tp3b := _px(9.5, -90.0)
	var tp4a := Vector2(d4.x, d4.y - 24.0)
	var tp4b := _px(10.0, -118.0)
	var tp5a := Vector2(d5.x + 24.0, d5.y)
	var tp5b := _px(30.0, -130.0)

	var cam_l := min_c.x * 32 - 32
	var cam_t := min_c.y * 32 - 32
	var cam_r := (max_c.x + 2) * 32
	var cam_b := (max_c.y + 2) * 32

	var id_map := (
		"0: NodePath(\"Room1Door\"),\n"
		+ "1: NodePath(\"Room1Door2\"),\n"
		+ "2: NodePath(\"Room1Door3\"),\n"
		+ "3: NodePath(\"Room2Door\"),\n"
		+ "4: NodePath(\"Room2Door2\"),\n"
		+ "5: NodePath(\"Room2Door3\"),\n"
		+ "6: NodePath(\"Room3Door\"),\n"
		+ "7: NodePath(\"Room3Door2\"),\n"
		+ "8: NodePath(\"Room3Door3\"),\n"
		+ "9: NodePath(\"Room4Door\"),\n"
		+ "10: NodePath(\"Room4Door2\"),\n"
		+ "11: NodePath(\"Room4Door3\"),\n"
		+ "12: NodePath(\"Room5Door\"),\n"
		+ "13: NodePath(\"Room5Door2\"),\n"
		+ "14: NodePath(\"Room5Door3\")"
	)
	var node_map := (
		"NodePath(\"Room1Door\"): 0,\n"
		+ "NodePath(\"Room1Door2\"): 1,\n"
		+ "NodePath(\"Room1Door3\"): 2,\n"
		+ "NodePath(\"Room2Door\"): 3,\n"
		+ "NodePath(\"Room2Door2\"): 4,\n"
		+ "NodePath(\"Room2Door3\"): 5,\n"
		+ "NodePath(\"Room3Door\"): 6,\n"
		+ "NodePath(\"Room3Door2\"): 7,\n"
		+ "NodePath(\"Room3Door3\"): 8,\n"
		+ "NodePath(\"Room4Door\"): 9,\n"
		+ "NodePath(\"Room4Door2\"): 10,\n"
		+ "NodePath(\"Room4Door3\"): 11,\n"
		+ "NodePath(\"Room5Door\"): 12,\n"
		+ "NodePath(\"Room5Door2\"): 13,\n"
		+ "NodePath(\"Room5Door3\"): 14"
	)

	var r1_doors := (
		"NodePath(\"../ReplicatedPropsContainer/Room1Door\"), "
		+ "NodePath(\"../ReplicatedPropsContainer/Room1Door2\"), "
		+ "NodePath(\"../ReplicatedPropsContainer/Room1Door3\")"
	)
	var r2_doors := (
		"NodePath(\"../ReplicatedPropsContainer/Room2Door\"), "
		+ "NodePath(\"../ReplicatedPropsContainer/Room2Door2\"), "
		+ "NodePath(\"../ReplicatedPropsContainer/Room2Door3\")"
	)
	var r3_doors := (
		"NodePath(\"../ReplicatedPropsContainer/Room3Door\"), "
		+ "NodePath(\"../ReplicatedPropsContainer/Room3Door2\"), "
		+ "NodePath(\"../ReplicatedPropsContainer/Room3Door3\")"
	)
	var r4_doors := (
		"NodePath(\"../ReplicatedPropsContainer/Room4Door\"), "
		+ "NodePath(\"../ReplicatedPropsContainer/Room4Door2\"), "
		+ "NodePath(\"../ReplicatedPropsContainer/Room4Door3\")"
	)
	var r5_doors := (
		"NodePath(\"../ReplicatedPropsContainer/Room5Door\"), "
		+ "NodePath(\"../ReplicatedPropsContainer/Room5Door2\"), "
		+ "NodePath(\"../ReplicatedPropsContainer/Room5Door3\")"
	)

	var text := """[gd_scene format=3 uid=\"uid://chelldungeon01\"]

[ext_resource type=\"Script\" uid=\"uid://7mbux4mybta0\" path=\"res://source/common/gameplay/maps/map.gd\" id=\"map\"]
[ext_resource type=\"TileSet\" path=\"res://source/common/gameplay/maps/tilesets/hell_tileset.tres\" id=\"tiles\"]
[ext_resource type=\"AudioStream\" uid=\"uid://lakm3wo2urk3\" path=\"res://assets/audio/music/army_of_darkness.ogg\" id=\"music\"]
[ext_resource type=\"Script\" uid=\"uid://wq8klpndipnu\" path=\"res://source/common/network/sync/replicated_props.gd\" id=\"rp\"]
[ext_resource type=\"PackedScene\" uid=\"uid://b2ckixon7ryh6\" path=\"res://source/common/gameplay/maps/components/interaction_areas/warper/warper.tscn\" id=\"warper\"]
[ext_resource type=\"PackedScene\" path=\"res://source/common/gameplay/lighting/campfire.tscn\" id=\"camp\"]
[ext_resource type=\"PackedScene\" uid=\"uid://hcfiu2vpqr3u\" path=\"res://source/common/gameplay/maps/props/doors/activable_door/activable_door.tscn\" id=\"door\"]
[ext_resource type=\"Script\" uid=\"uid://trwnxb3wdk15\" path=\"res://source/common/gameplay/dungeon/room_node.gd\" id=\"room\"]
[ext_resource type=\"PackedScene\" uid=\"uid://dbrernsyt26qh\" path=\"res://source/common/gameplay/characters/npc/npc.tscn\" id=\"npc\"]
[ext_resource type=\"PackedScene\" path=\"res://source/common/gameplay/dungeon/spawn_marker.tscn\" id=\"marker\"]
[ext_resource type=\"PackedScene\" uid=\"uid://dbg8y8if4vv5p\" path=\"res://source/common/gameplay/maps/components/interaction_areas/teleporter/teleporter.tscn\" id=\"tp\"]
[ext_resource type=\"Resource\" uid=\"uid://dcmvccg0con6x\" path=\"res://source/common/gameplay/characters/npc/npcs/lost_soul.tres\" id=\"lost\"]
[ext_resource type=\"Texture2D\" path=\"res://assets/sprites/environment/hell/statue.png\" id=\"statue\"]
[ext_resource type=\"Texture2D\" path=\"res://assets/sprites/environment/hell/statue_2.png\" id=\"statue2\"]
[ext_resource type=\"Resource\" path=\"res://source/common/gameplay/characters/npc/types/hell/hell_imp.tres\" id=\"imp\"]
[ext_resource type=\"Resource\" path=\"res://source/common/gameplay/characters/npc/types/hell/hell_damned.tres\" id=\"damned\"]
[ext_resource type=\"Resource\" path=\"res://source/common/gameplay/characters/npc/types/hell/hell_twisted.tres\" id=\"twisted\"]
[ext_resource type=\"Resource\" path=\"res://source/common/gameplay/characters/npc/types/hell/hell_burning.tres\" id=\"burning\"]
[ext_resource type=\"Resource\" path=\"res://source/common/gameplay/characters/npc/types/hell/hell_bloated.tres\" id=\"bloated\"]
[ext_resource type=\"Resource\" path=\"res://source/common/gameplay/characters/npc/types/hell/hell_eye.tres\" id=\"eye\"]
[ext_resource type=\"Resource\" path=\"res://source/common/gameplay/characters/npc/types/hell/hell_skull_wisp.tres\" id=\"wisp\"]
[ext_resource type=\"Resource\" path=\"res://source/common/gameplay/characters/npc/types/hell/hell_giant.tres\" id=\"giant\"]
[ext_resource type=\"Resource\" path=\"res://source/common/gameplay/characters/npc/types/hell/hell_vault_queen.tres\" id=\"queen\"]

[node name=\"HellDungeon\" type=\"Node2D\" node_paths=PackedStringArray(\"replicated_props_container\")]
y_sort_enabled = true
script = ExtResource(\"map\")
replicated_props_container = NodePath(\"ReplicatedPropsContainer\")
map_background_color = Color(0.012, 0.014, 0.028, 1)
music = ExtResource(\"music\")
camera_limit_left = %d
camera_limit_top = %d
camera_limit_right = %d
camera_limit_bottom = %d

[node name=\"CanvasModulate\" type=\"CanvasModulate\" parent=\".\"]
color = Color(0.52, 0.5, 0.62, 1)

[node name=\"Tiles\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true

[node name=\"Ground\" type=\"TileMapLayer\" parent=\"Tiles\"]
z_index = -2
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"tiles\")

[node name=\"Ground2\" type=\"TileMapLayer\" parent=\"Tiles\"]
z_index = -1
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"tiles\")

[node name=\"Walls\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"tiles\")

[node name=\"Props\" type=\"TileMapLayer\" parent=\"Tiles\"]
y_sort_enabled = true
tile_map_data = PackedByteArray(\"%s\")
tile_set = ExtResource(\"tiles\")

[node name=\"SceneProps\" type=\"Node2D\" parent=\".\"]
y_sort_enabled = true

[node name=\"CampLobby\" parent=\"SceneProps\" instance=ExtResource(\"camp\")]
position = Vector2(%s, %s)

[node name=\"Camp1\" parent=\"SceneProps\" instance=ExtResource(\"camp\")]
position = Vector2(%s, %s)

[node name=\"Camp2\" parent=\"SceneProps\" instance=ExtResource(\"camp\")]
position = Vector2(%s, %s)

[node name=\"Camp3\" parent=\"SceneProps\" instance=ExtResource(\"camp\")]
position = Vector2(%s, %s)

[node name=\"Camp4\" parent=\"SceneProps\" instance=ExtResource(\"camp\")]
position = Vector2(%s, %s)

[node name=\"Camp5\" parent=\"SceneProps\" instance=ExtResource(\"camp\")]
position = Vector2(%s, %s)

[node name=\"CampFinal\" parent=\"SceneProps\" instance=ExtResource(\"camp\")]
position = Vector2(%s, %s)

[node name=\"StatueA\" type=\"Sprite2D\" parent=\"SceneProps\"]
z_index = 1
position = Vector2(%s, %s)
texture = ExtResource(\"statue\")

[node name=\"StatueB\" type=\"Sprite2D\" parent=\"SceneProps\"]
z_index = 1
position = Vector2(%s, %s)
texture = ExtResource(\"statue2\")

[node name=\"StatueC\" type=\"Sprite2D\" parent=\"SceneProps\"]
z_index = 1
position = Vector2(%s, %s)
texture = ExtResource(\"statue\")

[node name=\"ReplicatedPropsContainer\" type=\"Node2D\" parent=\".\" node_paths=PackedStringArray(\"id_to_node\", \"node_to_id\")]
y_sort_enabled = true
script = ExtResource(\"rp\")
id_to_node = {
%s
}
node_to_id = {
%s
}

%s%s%s%s%s[node name=\"Warper\" parent=\".\" instance=ExtResource(\"warper\")]
position = Vector2(%s, %s)

[node name=\"LostSoul\" parent=\".\" instance=ExtResource(\"npc\")]
position = Vector2(%s, %s)
npc_resource = ExtResource(\"lost\")

[node name=\"Room1\" type=\"Area2D\" parent=\".\" node_paths=PackedStringArray(\"doors\")]
position = Vector2(%s, %s)
collision_layer = 0
collision_mask = 1
script = ExtResource(\"room\")
wave_delay_s = 0.85
doors = [%s]

[node name=\"CollisionPolygon2D\" type=\"CollisionPolygon2D\" parent=\"Room1\"]
polygon = %s

%s[node name=\"Room2\" type=\"Area2D\" parent=\".\" node_paths=PackedStringArray(\"doors\")]
position = Vector2(%s, %s)
collision_layer = 0
collision_mask = 1
script = ExtResource(\"room\")
wave_delay_s = 0.85
doors = [%s]

[node name=\"CollisionPolygon2D\" type=\"CollisionPolygon2D\" parent=\"Room2\"]
polygon = %s

%s[node name=\"Room3\" type=\"Area2D\" parent=\".\" node_paths=PackedStringArray(\"doors\")]
position = Vector2(%s, %s)
collision_layer = 0
collision_mask = 1
script = ExtResource(\"room\")
wave_delay_s = 0.85
doors = [%s]

[node name=\"CollisionPolygon2D\" type=\"CollisionPolygon2D\" parent=\"Room3\"]
polygon = %s

%s[node name=\"Room4\" type=\"Area2D\" parent=\".\" node_paths=PackedStringArray(\"doors\")]
position = Vector2(%s, %s)
collision_layer = 0
collision_mask = 1
script = ExtResource(\"room\")
wave_delay_s = 0.85
doors = [%s]

[node name=\"CollisionPolygon2D\" type=\"CollisionPolygon2D\" parent=\"Room4\"]
polygon = %s

%s[node name=\"Room5\" type=\"Area2D\" parent=\".\" node_paths=PackedStringArray(\"doors\")]
position = Vector2(%s, %s)
collision_layer = 0
collision_mask = 1
script = ExtResource(\"room\")
wave_delay_s = 0.85
doors = [%s]

[node name=\"CollisionPolygon2D\" type=\"CollisionPolygon2D\" parent=\"Room5\"]
polygon = %s

%s[node name=\"FinalRoom\" type=\"Area2D\" parent=\".\"]
position = Vector2(%s, %s)
collision_layer = 0
collision_mask = 1
script = ExtResource(\"room\")
final_room = true
wave_delay_s = 0.7

[node name=\"CollisionPolygon2D\" type=\"CollisionPolygon2D\" parent=\"FinalRoom\"]
polygon = %s

%s[node name=\"Room1Teleporter\" parent=\".\" node_paths=PackedStringArray(\"target\") instance=ExtResource(\"tp\")]
position = Vector2(%s, %s)
scale = Vector2(4, 1)
target = NodePath(\"../Room1Teleporter2\")

[node name=\"Room1Teleporter2\" parent=\".\" node_paths=PackedStringArray(\"target\") instance=ExtResource(\"tp\")]
position = Vector2(%s, %s)
scale = Vector2(4, 1)
one_way = true
target = NodePath(\"../Room1Teleporter\")

[node name=\"Room2Teleporter\" parent=\".\" node_paths=PackedStringArray(\"target\") instance=ExtResource(\"tp\")]
position = Vector2(%s, %s)
scale = Vector2(4, 1)
target = NodePath(\"../Room2Teleporter2\")

[node name=\"Room2Teleporter2\" parent=\".\" node_paths=PackedStringArray(\"target\") instance=ExtResource(\"tp\")]
position = Vector2(%s, %s)
scale = Vector2(4, 1)
one_way = true
target = NodePath(\"../Room2Teleporter\")

[node name=\"Room3Teleporter\" parent=\".\" node_paths=PackedStringArray(\"target\") instance=ExtResource(\"tp\")]
position = Vector2(%s, %s)
scale = Vector2(4, 1)
target = NodePath(\"../Room3Teleporter2\")

[node name=\"Room3Teleporter2\" parent=\".\" node_paths=PackedStringArray(\"target\") instance=ExtResource(\"tp\")]
position = Vector2(%s, %s)
scale = Vector2(4, 1)
one_way = true
target = NodePath(\"../Room3Teleporter\")

[node name=\"Room4Teleporter\" parent=\".\" node_paths=PackedStringArray(\"target\") instance=ExtResource(\"tp\")]
position = Vector2(%s, %s)
scale = Vector2(4, 1)
target = NodePath(\"../Room4Teleporter2\")

[node name=\"Room4Teleporter2\" parent=\".\" node_paths=PackedStringArray(\"target\") instance=ExtResource(\"tp\")]
position = Vector2(%s, %s)
scale = Vector2(4, 1)
one_way = true
target = NodePath(\"../Room4Teleporter\")

[node name=\"Room5Teleporter\" parent=\".\" node_paths=PackedStringArray(\"target\") instance=ExtResource(\"tp\")]
position = Vector2(%s, %s)
scale = Vector2(1, 4)
target = NodePath(\"../Room5Teleporter2\")

[node name=\"Room5Teleporter2\" parent=\".\" node_paths=PackedStringArray(\"target\") instance=ExtResource(\"tp\")]
position = Vector2(%s, %s)
scale = Vector2(1, 4)
one_way = true
target = NodePath(\"../Room5Teleporter\")
""" % [
		cam_l, cam_t, cam_r, cam_b,
		ground_b64, detail_b64, walls_b64, props_b64,
		str(lobby.x), str(lobby.y - 40.0),
		str(r1c.x), str(r1c.y + 40.0),
		str(r2c.x - 80.0), str(r2c.y + 20.0),
		str(r3c.x - 160.0), str(r3c.y + 220.0),
		str(r4c.x - 90.0), str(r4c.y + 30.0),
		str(r5c.x), str(r5c.y + 50.0),
		str(rfc.x), str(rfc.y + 80.0),
		str(r2c.x - 120.0), str(r2c.y - 40.0),
		str(r5c.x + 90.0), str(r5c.y - 30.0),
		str(rfc.x + 140.0), str(rfc.y - 60.0),
		id_map, node_map,
		_doors_h("Room1Door", d1.x, d1.y),
		_doors_h("Room2Door", d2.x, d2.y),
		_doors_h("Room3Door", d3.x, d3.y),
		_doors_h("Room4Door", d4.x, d4.y),
		_doors_v("Room5Door", d5.x, d5.y),
		str(lobby.x), str(lobby.y),
		str(lost.x), str(lost.y),
		str(r1c.x), str(r1c.y), r1_doors, _poly_text(_room_poly(0, -22, 17, -8, r1c)),
		_markers("Room1", [
			{"type": "imp", "x": -70, "y": 40},
			{"type": "imp", "x": 80, "y": 30},
			{"type": "imp", "x": 10, "y": 55},
			{"type": "damned", "x": 0, "y": -30},
			{"type": "damned", "x": -55, "y": -45, "wave": 1},
			{"type": "damned", "x": 70, "y": -25, "wave": 1},
			{"type": "imp", "x": 90, "y": 10, "wave": 1},
			{"type": "twisted", "x": 5, "y": 45, "wave": 1},
			{"type": "twisted", "x": -20, "y": 20, "wave": 2},
			{"type": "damned", "x": -80, "y": -10, "wave": 2},
			{"type": "damned", "x": 75, "y": -40, "wave": 2},
			{"type": "imp", "x": 15, "y": -55, "wave": 2},
		]),
		str(r2c.x), str(r2c.y), r2_doors, _poly_text(_room_poly(-2, -50, 20, -30, r2c)),
		_markers("Room2", [
			{"type": "damned", "x": -80, "y": 45},
			{"type": "damned", "x": 85, "y": 25},
			{"type": "damned", "x": -30, "y": -20},
			{"type": "twisted", "x": 15, "y": -40},
			{"type": "twisted", "x": -50, "y": -55, "wave": 1},
			{"type": "twisted", "x": 95, "y": -15, "wave": 1},
			{"type": "burning", "x": 25, "y": 60, "wave": 1},
			{"type": "burning", "x": -90, "y": 10, "wave": 1},
			{"type": "damned", "x": 40, "y": 20, "wave": 1},
			{"type": "burning", "x": -70, "y": 50, "wave": 2},
			{"type": "burning", "x": 100, "y": 40, "wave": 2},
			{"type": "eye", "x": -40, "y": -70, "wave": 2},
			{"type": "eye", "x": 55, "y": -60, "wave": 2},
			{"type": "damned", "x": 10, "y": 5, "wave": 2},
		]),
		str(r3c.x), str(r3c.y), r3_doors, _poly_text(_room_poly(-4, -82, 24, -58, r3c)),
		_markers("Room3", [
			{"type": "burning", "x": -300, "y": 220},
			{"type": "burning", "x": 310, "y": 200},
			{"type": "eye", "x": -280, "y": -230},
			{"type": "eye", "x": 290, "y": -210},
			{"type": "eye", "x": -340, "y": 20},
			{"type": "burning", "x": -50, "y": 300, "wave": 1},
			{"type": "burning", "x": -340, "y": 80, "wave": 1},
			{"type": "imp", "x": -320, "y": -90, "wave": 1},
			{"type": "imp", "x": 340, "y": -50, "wave": 1},
			{"type": "bloated", "x": 300, "y": -200, "wave": 1},
			{"type": "bloated", "x": -280, "y": 250, "wave": 2},
			{"type": "bloated", "x": 300, "y": 230, "wave": 2},
			{"type": "eye", "x": -270, "y": -220, "wave": 2},
			{"type": "eye", "x": 310, "y": -180, "wave": 2},
			{"type": "imp", "x": 120, "y": 310, "wave": 2},
		]),
		str(r4c.x), str(r4c.y), r4_doors, _poly_text(_room_poly(0, -110, 19, -90, r4c)),
		_markers("Room4", [
			{"type": "bloated", "x": -60, "y": 35},
			{"type": "bloated", "x": 70, "y": 15},
			{"type": "bloated", "x": 5, "y": -45},
			{"type": "damned", "x": 40, "y": 50},
			{"type": "twisted", "x": -80, "y": -25, "wave": 1},
			{"type": "twisted", "x": 90, "y": -35, "wave": 1},
			{"type": "eye", "x": -25, "y": 55, "wave": 1},
			{"type": "eye", "x": 45, "y": 45, "wave": 1},
			{"type": "damned", "x": -50, "y": 20, "wave": 1},
			{"type": "damned", "x": 55, "y": -50, "wave": 1},
			{"type": "bloated", "x": -40, "y": 10, "wave": 2},
			{"type": "bloated", "x": 80, "y": 5, "wave": 2},
			{"type": "twisted", "x": -90, "y": -40, "wave": 2},
			{"type": "twisted", "x": 70, "y": -20, "wave": 2},
			{"type": "eye", "x": 10, "y": 60, "wave": 2},
			{"type": "burning", "x": 0, "y": -55, "wave": 2},
		]),
		str(r5c.x), str(r5c.y), r5_doors, _poly_text(_room_poly(-2, -142, 22, -118, r5c)),
		_markers("Room5", [
			{"type": "damned", "x": -85, "y": 45},
			{"type": "damned", "x": 80, "y": 35},
			{"type": "twisted", "x": -40, "y": -40},
			{"type": "twisted", "x": 50, "y": -55},
			{"type": "imp", "x": 5, "y": -60},
			{"type": "imp", "x": 95, "y": -15},
			{"type": "bloated", "x": -70, "y": 20, "wave": 1},
			{"type": "bloated", "x": 85, "y": 10, "wave": 1},
			{"type": "burning", "x": -50, "y": -35, "wave": 1},
			{"type": "burning", "x": 60, "y": 50, "wave": 1},
			{"type": "eye", "x": 0, "y": -70, "wave": 1},
			{"type": "giant", "x": 0, "y": 10, "wave": 2},
			{"type": "burning", "x": -75, "y": -25, "wave": 2},
			{"type": "burning", "x": 85, "y": 45, "wave": 2},
			{"type": "eye", "x": -100, "y": -10, "wave": 2},
			{"type": "eye", "x": 110, "y": 0, "wave": 2},
			{"type": "imp", "x": 20, "y": 60, "wave": 2},
		]),
		str(rfc.x), str(rfc.y), _poly_text(_room_poly(30, -146, 58, -116, rfc)),
		_markers("FinalRoom", [
			{"type": "wisp", "x": -100, "y": 55},
			{"type": "wisp", "x": 110, "y": 45},
			{"type": "wisp", "x": 0, "y": 80},
			{"type": "imp", "x": -50, "y": -65},
			{"type": "imp", "x": 55, "y": -55},
			{"type": "imp", "x": 15, "y": 75},
			{"type": "eye", "x": -120, "y": -25},
			{"type": "eye", "x": 125, "y": -15},
			{"type": "bloated", "x": 30, "y": 20},
			{"type": "queen", "x": 0, "y": 0, "wave": 1, "boss": true},
			{"type": "eye", "x": -115, "y": -20, "wave": 1},
			{"type": "eye", "x": 125, "y": -10, "wave": 1},
			{"type": "wisp", "x": -90, "y": 50, "wave": 1},
			{"type": "wisp", "x": 100, "y": 40, "wave": 1},
			{"type": "imp", "x": -40, "y": -70, "wave": 1},
			{"type": "imp", "x": 50, "y": -60, "wave": 1},
		]),
		str(tp1a.x), str(tp1a.y), str(tp1b.x), str(tp1b.y),
		str(tp2a.x), str(tp2a.y), str(tp2b.x), str(tp2b.y),
		str(tp3a.x), str(tp3a.y), str(tp3b.x), str(tp3b.y),
		str(tp4a.x), str(tp4a.y), str(tp4b.x), str(tp4b.y),
		str(tp5a.x), str(tp5a.y), str(tp5b.x), str(tp5b.y),
	]

	var path := ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", path)
