extends SceneTree
## Spread Goblin Woodland hostiles + add Wild Wolves / Woodland Rats.
## Run: godot --headless --path . -s tools/spread_woodland_wildlife.gd

const MAP_PATH := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
const HOSTILE := "res://source/common/gameplay/characters/npc/hostile_npc.tscn"
const KEEP_AWAY := [
	Vector2(920, 1280), # Entrance
	Vector2(984, 1320), # Hub portal
	Vector2(978, 839), # Mining portal
	Vector2(2696, 648), # Fungus
	Vector2(1656, 128), # Teleporter entry
	Vector2(2616, 544), # Grove
	Vector2(2696, 600), # Hermit
]

## Desired spawns: name -> [desired pos, enemy ext id key]
## Keys map to ExtResource ids we inject/use in the scene text.
var GOBLIN_MOVES: Dictionary = {
	"GateRunt1": Vector2(300, 1100),
	"GateRunt2": Vector2(500, 940),
	"GateRunt3": Vector2(220, 760),
	"GateRunt4": Vector2(420, 620),
	"GateRunt5": Vector2(680, 1080),
	"PathRunt1": Vector2(820, 980),
	"PathRunt2": Vector2(1080, 1060),
	"PathCutter1": Vector2(900, 740),
	"PathCutter2": Vector2(1140, 660),
	"PathCutter3": Vector2(1380, 700),
	"CampCutter1": Vector2(1500, 380),
	"CampCutter2": Vector2(1700, 460),
	"CampRunt1": Vector2(1580, 560),
	"CampCutter3": Vector2(1820, 380),
	"CampCutter4": Vector2(1900, 540),
	"CampRunt2": Vector2(1460, 620),
	"Slinger1": Vector2(1300, 300),
	"Slinger2": Vector2(1060, 260),
	"Slinger3": Vector2(820, 280),
	"Shaman1": Vector2(580, 260),
	"ShamanEscortCutter": Vector2(740, 420),
	"Shaman2": Vector2(980, 420),
	"ChiefGuardRunt1": Vector2(340, 170),
	"GoblinChief": Vector2(480, 230),
	"ChiefGuardRunt2": Vector2(620, 190),
}

var WOLF_SPAWNS: Array[Vector2] = [
	Vector2(180, 500),
	Vector2(540, 700),
	Vector2(980, 540),
	Vector2(1420, 900),
	Vector2(1740, 700),
	Vector2(1960, 380),
	Vector2(1220, 1140),
	Vector2(200, 900),
]

var RAT_SPAWNS: Array[Vector2] = [
	Vector2(860, 1180),
	Vector2(1100, 1220),
	Vector2(700, 820),
	Vector2(460, 460),
	Vector2(260, 980),
	Vector2(1260, 820),
	Vector2(1580, 740),
	Vector2(1860, 900),
	Vector2(660, 180),
	Vector2(1620, 220),
	Vector2(2020, 620),
	Vector2(1100, 460),
	Vector2(360, 340),
	Vector2(900, 600),
]

var _ground: TileMapLayer
var _walls: TileMapLayer
var _walk: Dictionary = {} # Vector2i -> true


func _initialize() -> void:
	var packed: PackedScene = load(MAP_PATH) as PackedScene
	var map: Node2D = packed.instantiate() as Node2D
	_ground = map.get_node("Ground") as TileMapLayer
	_walls = map.get_node("Walls") as TileMapLayer
	_build_walkable()
	print("walkable_cells=", _walk.size())

	var final_goblins: Dictionary = {}
	for name: String in GOBLIN_MOVES.keys():
		final_goblins[name] = _snap(GOBLIN_MOVES[name])

	var final_wolves: Array[Vector2] = []
	for p: Vector2 in WOLF_SPAWNS:
		final_wolves.append(_snap(p))

	var final_rats: Array[Vector2] = []
	for p: Vector2 in RAT_SPAWNS:
		final_rats.append(_snap(p))

	# Min-distance pass among all hostiles
	var all: Array = []
	for n: String in final_goblins.keys():
		all.append({"name": n, "pos": final_goblins[n], "kind": "goblin"})
	for i in final_wolves.size():
		all.append({"name": "WildWolf%d" % (i + 1), "pos": final_wolves[i], "kind": "wolf"})
	for i in final_rats.size():
		all.append({"name": "WoodlandRat%d" % (i + 1), "pos": final_rats[i], "kind": "rat"})

	_separate(all, 110.0)

	for e: Dictionary in all:
		e["pos"] = _snap(e["pos"])
		e["pos"] = _away_from_keepouts(e["pos"])

	_apply_tscn(all)
	_verify_min_distance(all, 96.0)
	print("SPREAD_PASS hostiles=", all.size())
	quit(0)


func _build_walkable() -> void:
	var used: Array[Vector2i] = _ground.get_used_cells()
	for c: Vector2i in used:
		if _walls.get_cell_source_id(c) >= 0:
			continue
		_walk[c] = true


func _snap(world: Vector2) -> Vector2:
	var best: Vector2 = world
	var best_d := 1.0e12
	var center := _ground.local_to_map(world)
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var c := center + Vector2i(dx, dy)
			if not _walk.has(c):
				continue
			var wp: Vector2 = _ground.map_to_local(c)
			var d: float = wp.distance_squared_to(world)
			if d < best_d:
				best_d = d
				best = wp
	if best_d > 1.0e11:
		push_warning("no walkable near %s — keeping raw" % world)
		return world
	return best


func _away_from_keepouts(p: Vector2) -> Vector2:
	var out := p
	for k: Vector2 in KEEP_AWAY:
		if out.distance_to(k) < 80.0:
			var dir := (out - k).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			out = _snap(k + dir * 100.0)
	return out


func _separate(all: Array, min_d: float) -> void:
	for _pass in range(8):
		for i in all.size():
			for j in range(i + 1, all.size()):
				var a: Vector2 = all[i]["pos"]
				var b: Vector2 = all[j]["pos"]
				var d: float = a.distance_to(b)
				if d >= min_d or d < 0.001:
					if d < 0.001:
						all[j]["pos"] = _snap(b + Vector2(min_d, 0))
					continue
				var push: Vector2 = (b - a).normalized() * ((min_d - d) * 0.5)
				all[i]["pos"] = a - push
				all[j]["pos"] = b + push


func _verify_min_distance(all: Array, min_d: float) -> void:
	var bad := 0
	for i in all.size():
		for j in range(i + 1, all.size()):
			var d: float = (all[i]["pos"] as Vector2).distance_to(all[j]["pos"] as Vector2)
			if d < min_d:
				bad += 1
				print("CLOSE ", all[i]["name"], " ", all[j]["name"], " d=", snapped(d, 0.1))
	print("pairs_under_", int(min_d), "=", bad)


func _apply_tscn(all: Array) -> void:
	var abs_path := ProjectSettings.globalize_path(MAP_PATH)
	var text := FileAccess.get_file_as_string(abs_path)
	if text.is_empty():
		push_error("empty map")
		quit(1)
		return

	# Ensure ext_resources for wolf + woodland rat
	if text.find('id="35_wolf"') < 0:
		var insert_at := text.find('[ext_resource type="Resource" uid="uid://deo2ei3h78ouy"')
		var line := (
			'[ext_resource type="Resource" uid="uid://c43oawxmbygiq" path="res://source/common/gameplay/characters/npc/types/wolf.tres" id="35_wolf"]\n'
			+ '[ext_resource type="Resource" uid="uid://bq8woodlandrat01" path="res://source/common/gameplay/characters/npc/types/woodland_rat.tres" id="36_wrat"]\n'
		)
		text = text.insert(insert_at, line)

	# Move existing goblins by rewriting their position lines
	for e: Dictionary in all:
		if e["kind"] != "goblin":
			continue
		var name: String = e["name"]
		var pos: Vector2 = e["pos"]
		var node_key := '[node name="%s" parent="ReplicatedPropsContainer"' % name
		var idx := text.find(node_key)
		if idx < 0:
			push_error("missing goblin node %s" % name)
			continue
		var pos_key := "position = Vector2("
		var pidx := text.find(pos_key, idx)
		var pend := text.find(")", pidx)
		var new_pos := "position = Vector2(%d, %d)" % [int(round(pos.x)), int(round(pos.y))]
		text = text.substr(0, pidx) + new_pos + text.substr(pend + 1)

	# Remove any previously injected wildlife nodes (idempotent)
	text = _strip_nodes_matching(text, "WildWolf")
	text = _strip_nodes_matching(text, "WoodlandRat")

	# Rebuild id maps + append wildlife before ChiefGuardRunt2 end... insert before Entrance
	var wildlife_block := ""
	var next_id := 25
	var id_lines: PackedStringArray = PackedStringArray()
	# Keep existing 0..24 goblin map entries, then add wildlife
	# We'll fully rebuild id_to_node / node_to_id from all hostiles in container order.

	var ordered: Array = []
	for e: Dictionary in all:
		if e["kind"] == "goblin":
			ordered.append(e)
	for e: Dictionary in all:
		if e["kind"] == "wolf":
			ordered.append(e)
	for e: Dictionary in all:
		if e["kind"] == "rat":
			ordered.append(e)

	var uid_base := 1900001000
	for e: Dictionary in all:
		if e["kind"] == "goblin":
			continue
		var name: String = e["name"]
		var pos: Vector2 = e["pos"]
		var ext := "35_wolf" if e["kind"] == "wolf" else "36_wrat"
		var uid := uid_base
		uid_base += 1
		wildlife_block += (
			'\n[node name="%s" parent="ReplicatedPropsContainer" unique_id=%d instance=ExtResource("3_2hhap")]\n'
			+ "position = Vector2(%d, %d)\n"
			+ "debug_draw_ranges = false\n"
			+ 'enemy_data = ExtResource("%s")\n'
			+ "weapon = null\n"
		) % [name, uid, int(round(pos.x)), int(round(pos.y)), ext]

	var entrance_idx := text.find('[node name="Entrance"')
	if entrance_idx < 0:
		push_error("Entrance not found")
		quit(1)
		return
	text = text.substr(0, entrance_idx) + wildlife_block + "\n" + text.substr(entrance_idx)

	# Rebuild id_to_node / node_to_id dictionaries
	var id_to := "id_to_node = {\n"
	var node_to := "node_to_id = {\n"
	for i in ordered.size():
		var n: String = ordered[i]["name"]
		id_to += "%d: NodePath(\"%s\"),\n" % [i, n]
		node_to += "NodePath(\"%s\"): %d,\n" % [n, i]
	id_to = id_to.trim_suffix(",\n") + "\n}\n"
	node_to = node_to.trim_suffix(",\n") + "\n}\n"

	var id_start := text.find("id_to_node = {")
	var id_end := text.find("node_to_id = {", id_start)
	var node_end := text.find("metadata/_custom_type_script", id_end)
	if id_start < 0 or id_end < 0 or node_end < 0:
		push_error("failed to locate id maps")
		quit(1)
		return
	text = text.substr(0, id_start) + id_to + node_to + text.substr(node_end)

	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("wrote ", abs_path)


func _strip_nodes_matching(text: String, prefix: String) -> String:
	var out := text
	while true:
		var key := '[node name="%s' % prefix
		var idx := out.find(key)
		if idx < 0:
			break
		# Find next node header after this one
		var next_node := out.find("\n[node name=", idx + 1)
		if next_node < 0:
			out = out.substr(0, idx)
			break
		out = out.substr(0, idx) + out.substr(next_node + 1)
	return out
