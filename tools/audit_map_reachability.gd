extends Node
## Regression guard for the click-navigation mask fix. Making SCENERY solid in the
## walkability grid is correct (the body collides with it either way), but it must
## not seal anything off. Flood-fill the grid from the map's spawn under BOTH the
## old mask and the new one, and flag only a REGRESSION: something the old
## WORLD-only grid could route to that the new WORLD|SCENERY grid cannot. Targets
## that were already unreachable (behind a teleport link, or authored inside
## scenery) are pre-existing and not this change's business.
##   godot --path . --mode=client res://tools/audit_map_reachability.tscn

const MAPS: Array[String] = [
	"res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn",
	"res://source/common/gameplay/maps/maps/forest/forest.tscn",
	"res://source/common/gameplay/maps/maps/dungeon/dungeon.tscn",
	"res://source/common/gameplay/maps/maps/hell_dungeon/hell_dungeon.tscn",
]

## Mirrors ClickNavigation, so the grid audited here is the grid players walk on.
const CELL_SIZE: float = 16.0
const PLAYER_CLEARANCE: Vector2 = Vector2(13.0, 9.0)
const PLAYER_SHAPE_OFFSET: Vector2 = Vector2(0.0, -3.0)
## Reaching an ore vein means standing NEXT to it, not inside it. Matches
## ClickNavigation._nearest_walkable's snap radius.
const SEARCH_RADIUS_CELLS: int = 10
## What the grid used to sample: WORLD only, blind to SCENERY.
const OLD_MASK: int = 2

var _failures: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	for map_path: String in MAPS:
		if not ResourceLoader.exists(map_path):
			continue
		var root: Node = (load(map_path) as PackedScene).instantiate()
		add_child(root)
		# Room seals open: a player only reaches anything past them once cleared.
		for door: Node in root.find_children("*", "ActivableDoor", true, false):
			(door as ActivableDoor).set_open(true, false)
		await get_tree().physics_frame
		await get_tree().physics_frame
		await _check(map_path, root)
		root.queue_free()
		await get_tree().process_frame
	print("\n%d reachability regressions" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(map_path: String, root: Node) -> void:
	print("\n=== %s ===" % map_path.get_file())
	var old_reached: Dictionary[Vector2i, bool] = await _reachable(root, OLD_MASK)
	var new_reached: Dictionary[Vector2i, bool] = await _reachable(
		root, PhysicsLayers.SOLID_GROUND_MASK
	)
	print("  reachable cells: old %d -> new %d" % [old_reached.size(), new_reached.size()])
	for type: String in ["MineableNode", "Warper", "Teleporter", "Npc"]:
		for node: Node in root.find_children("*", type, true, false):
			var node_2d := node as Node2D
			if node_2d == null:
				continue
			var origin: Vector2i = _to_id(node_2d.global_position)
			if _any_near(old_reached, origin) and not _any_near(new_reached, origin):
				print("  REGRESSION   %-14s %s @ %s" % [type, node.name, node_2d.global_position])
				_failures += 1


## Every grid cell reachable on foot from the map's spawn, sampling [param mask].
func _reachable(root: Node, mask: int) -> Dictionary[Vector2i, bool]:
	var solid: Dictionary[Vector2i, bool] = {}
	var bounds: Rect2 = _bounds(root)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return solid
	var space: PhysicsDirectSpaceState2D = get_viewport().world_2d.direct_space_state
	var box := RectangleShape2D.new()
	box.size = PLAYER_CLEARANCE
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = box
	query.collision_mask = mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var min_id: Vector2i = _to_id(bounds.position)
	var max_id: Vector2i = _to_id(bounds.end)
	for y: int in range(min_id.y, max_id.y + 1):
		for x: int in range(min_id.x, max_id.x + 1):
			var id := Vector2i(x, y)
			query.transform = Transform2D(0.0, _to_world(id) + PLAYER_SHAPE_OFFSET)
			solid[id] = not space.intersect_shape(query, 1).is_empty()
		await get_tree().process_frame

	var start_id: Vector2i = _nearest_open(solid, _to_id(_spawn_point(root)))
	if start_id == Vector2i.MAX:
		return {}
	return _flood(solid, start_id)


## True when any reached cell lies within the pathfinder's own snap radius of
## [param origin] — i.e. the walker can get next to whatever sits there.
func _any_near(reached: Dictionary[Vector2i, bool], origin: Vector2i) -> bool:
	for y: int in range(origin.y - SEARCH_RADIUS_CELLS, origin.y + SEARCH_RADIUS_CELLS + 1):
		for x: int in range(origin.x - SEARCH_RADIUS_CELLS, origin.x + SEARCH_RADIUS_CELLS + 1):
			if reached.has(Vector2i(x, y)):
				return true
	return false


func _flood(solid: Dictionary[Vector2i, bool], from: Vector2i) -> Dictionary[Vector2i, bool]:
	var seen: Dictionary[Vector2i, bool] = {from: true}
	var queue: Array[Vector2i] = [from]
	# 4-way only: a diagonal step is legal in the grid only when BOTH orthogonal
	# neighbours are clear, so a 4-way flood never over-reports connectivity.
	var steps: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	while not queue.is_empty():
		var id: Vector2i = queue.pop_back()
		for step: Vector2i in steps:
			var next: Vector2i = id + step
			if seen.has(next) or not solid.has(next) or solid[next]:
				continue
			seen[next] = true
			queue.append(next)
	return seen


func _nearest_open(solid: Dictionary[Vector2i, bool], origin: Vector2i) -> Vector2i:
	if solid.has(origin) and not solid[origin]:
		return origin
	for radius: int in range(1, SEARCH_RADIUS_CELLS + 1):
		for y: int in range(origin.y - radius, origin.y + radius + 1):
			for x: int in range(origin.x - radius, origin.x + radius + 1):
				var id := Vector2i(x, y)
				if solid.has(id) and not solid[id]:
					return id
	return Vector2i.MAX


func _spawn_point(root: Node) -> Vector2:
	for spawn_name: String in ["RespawnPoint", "Entrance"]:
		var node := root.get_node_or_null(NodePath(spawn_name)) as Node2D
		if node != null:
			return node.global_position
	for node: Node in root.find_children("*", "Warper", true, false):
		return (node as Node2D).global_position
	return Vector2.ZERO


func _to_id(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / CELL_SIZE), floori(world.y / CELL_SIZE))


func _to_world(id: Vector2i) -> Vector2:
	return Vector2(id) * CELL_SIZE + Vector2.ONE * CELL_SIZE * 0.5


func _bounds(root: Node) -> Rect2:
	var combined := Rect2()
	var has_bounds: bool = false
	for node: Node in root.find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		var used: Rect2i = layer.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		var first: Vector2 = layer.to_global(layer.map_to_local(used.position))
		var last: Vector2 = layer.to_global(layer.map_to_local(used.end - Vector2i.ONE))
		var half_tile: Vector2 = Vector2(layer.tile_set.tile_size) * 0.5
		var layer_bounds := Rect2(
			Vector2(minf(first.x, last.x), minf(first.y, last.y)) - half_tile,
			Vector2(absf(last.x - first.x), absf(last.y - first.y))
				+ Vector2(layer.tile_set.tile_size)
		)
		if not has_bounds:
			combined = layer_bounds
			has_bounds = true
		else:
			combined = combined.merge(layer_bounds)
	return combined
