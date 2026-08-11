extends SceneTree
## Push Wild Wolves / Woodland Badgers away from goblin spawn points so players
## fighting goblins don't aggro wildlife. Does not change goblin positions.
## Run: godot --headless --path . -s tools/separate_woodland_wildlife.gd

const MAP_PATH := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
## detection(~85) + wander(~56) + melee buffer — stay outside aggro while fighting goblins.
const MIN_FROM_GOBLIN := 160.0
const KEEP_AWAY := [
	Vector2(920, 1280), # Entrance
	Vector2(984, 1320), # Hub portal
	Vector2(978, 839), # Mining portal
	Vector2(2696, 648), # Fungus
	Vector2(1656, 128), # Teleporter entry
]
## Prefer these quieter pockets when a wildlife spawn is stuck near goblins.
const SAFE_POCKETS: Array[Vector2] = [
	Vector2(120, 200),
	Vector2(120, 400),
	Vector2(120, 600),
	Vector2(2160, 200),
	Vector2(2160, 480),
	Vector2(2160, 720),
	Vector2(2160, 1000),
	Vector2(2160, 1200),
	Vector2(400, 120),
	Vector2(700, 120),
	Vector2(1100, 120),
	Vector2(1400, 120),
	Vector2(1800, 120),
	Vector2(200, 1200),
	Vector2(500, 1240),
	Vector2(1400, 1240),
	Vector2(1700, 1240),
	Vector2(2000, 1240),
]

var _ground: TileMapLayer
var _walls: TileMapLayer
var _walk: Dictionary = {}


func _initialize() -> void:
	var packed: PackedScene = load(MAP_PATH) as PackedScene
	var map: Node2D = packed.instantiate() as Node2D
	_ground = map.get_node("Ground") as TileMapLayer
	_walls = map.get_node("Walls") as TileMapLayer
	_build_walkable()

	var container: Node = map.get_node("ReplicatedPropsContainer")
	var goblins: Array[Vector2] = []
	var wildlife: Array[Dictionary] = []
	for child: Node in container.get_children():
		if not (child is Node2D):
			continue
		var n2: Node2D = child as Node2D
		var name: String = String(child.name)
		if name.begins_with("WildWolf") or name.begins_with("WoodlandRat"):
			wildlife.append({"name": name, "pos": n2.position})
		elif name.begins_with("Gate") or name.begins_with("Path") or name.begins_with("Camp") \
				or name.begins_with("Slinger") or name.begins_with("Shaman") \
				or name.begins_with("Chief") or name.begins_with("Goblin"):
			goblins.append(n2.position)

	print("goblins=", goblins.size(), " wildlife=", wildlife.size())

	for _pass in range(20):
		for entry: Dictionary in wildlife:
			var pos: Vector2 = entry["pos"]
			var nearest_gob: float = _nearest(pos, goblins)
			if nearest_gob >= MIN_FROM_GOBLIN:
				# Light keep-away + wildlife spacing only.
				var soft := Vector2.ZERO
				for k: Vector2 in KEEP_AWAY:
					var d2: float = pos.distance_to(k)
					if d2 < 90.0 and d2 > 0.001:
						soft += (pos - k).normalized() * ((90.0 - d2) * 0.4)
				for other: Dictionary in wildlife:
					if other["name"] == entry["name"]:
						continue
					var d3: float = pos.distance_to(other["pos"])
					if d3 < 80.0 and d3 > 0.001:
						soft += (pos - other["pos"]).normalized() * ((80.0 - d3) * 0.2)
				if soft != Vector2.ZERO:
					entry["pos"] = _snap(pos + soft)
				continue

			# Too close to goblins — hard relocate toward the furthest safe pocket.
			var best: Vector2 = pos
			var best_score: float = -1.0e12
			for pocket: Vector2 in SAFE_POCKETS:
				var candidate: Vector2 = _snap(pocket + Vector2(randf_range(-40, 40), randf_range(-40, 40)))
				var score: float = _nearest(candidate, goblins)
				score -= _nearest_wildlife(candidate, wildlife, entry["name"]) * 0.15
				for k: Vector2 in KEEP_AWAY:
					if candidate.distance_to(k) < 80.0:
						score -= 200.0
				if score > best_score:
					best_score = score
					best = candidate
			# Also try pushing directly away from nearest goblin.
			var away_from := _nearest_point(pos, goblins)
			var pushed: Vector2 = _snap(away_from + (pos - away_from).normalized() * (MIN_FROM_GOBLIN + 24.0))
			if _nearest(pushed, goblins) > best_score:
				best = pushed
			entry["pos"] = best

	var moved := 0
	var abs_path := ProjectSettings.globalize_path(MAP_PATH)
	var text := FileAccess.get_file_as_string(abs_path)
	for entry: Dictionary in wildlife:
		var name: String = entry["name"]
		var pos: Vector2 = entry["pos"]
		var node_key := '[node name="%s" parent="ReplicatedPropsContainer"' % name
		var idx := text.find(node_key)
		if idx < 0:
			push_warning("missing node %s" % name)
			continue
		var pos_key := "position = Vector2("
		var pidx := text.find(pos_key, idx)
		var pend := text.find(")", pidx)
		var old := text.substr(pidx, pend - pidx + 1)
		var new_pos := "position = Vector2(%d, %d)" % [int(round(pos.x)), int(round(pos.y))]
		if old != new_pos:
			moved += 1
			text = text.substr(0, pidx) + new_pos + text.substr(pend + 1)

	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

	var close_pairs := 0
	var worst := 1.0e12
	for entry: Dictionary in wildlife:
		var d: float = _nearest(entry["pos"], goblins)
		worst = mini(worst, d)
		if d < MIN_FROM_GOBLIN:
			close_pairs += 1
			print("STILL_CLOSE ", entry["name"], " d=", snapped(d, 0.1))
	print("SEPARATE_PASS moved=", moved, " still_close=", close_pairs, " worst_d=", snapped(worst, 0.1))
	quit(0 if close_pairs == 0 else 1)


func _build_walkable() -> void:
	for c: Vector2i in _ground.get_used_cells():
		if _walls.get_cell_source_id(c) >= 0:
			continue
		_walk[c] = true


func _snap(world: Vector2) -> Vector2:
	var best: Vector2 = world
	var best_d := 1.0e12
	var center := _ground.local_to_map(world)
	for dy in range(-20, 21):
		for dx in range(-20, 21):
			var c := center + Vector2i(dx, dy)
			if not _walk.has(c):
				continue
			var wp: Vector2 = _ground.map_to_local(c)
			var d: float = wp.distance_squared_to(world)
			if d < best_d:
				best_d = d
				best = wp
	return best if best_d < 1.0e11 else world


func _nearest(pos: Vector2, points: Array[Vector2]) -> float:
	var best := 1.0e12
	for p: Vector2 in points:
		best = mini(best, pos.distance_to(p))
	return best


func _nearest_point(pos: Vector2, points: Array[Vector2]) -> Vector2:
	var best: Vector2 = points[0] if not points.is_empty() else pos
	var best_d := 1.0e12
	for p: Vector2 in points:
		var d: float = pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best


func _nearest_wildlife(pos: Vector2, wildlife: Array[Dictionary], skip: String) -> float:
	var best := 1.0e12
	for other: Dictionary in wildlife:
		if other["name"] == skip:
			continue
		best = mini(best, pos.distance_to(other["pos"]))
	return best
