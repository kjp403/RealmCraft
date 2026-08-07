class_name ClickNavigation
extends Node
## Client-side collision-aware click navigation. A walkability grid is generated
## from collision layer 2, the same layer the player already collides with.

const TRANSITION_FIX_VERSION: String = "2026-08-07-b"

const CELL_SIZE: float = 16.0
const COLLISION_MASK: int = 2
const PLAYER_CLEARANCE: Vector2 = Vector2(14.0, 8.0)
const PLAYER_SHAPE_OFFSET: Vector2 = Vector2(0.0, -3.0)
const WAYPOINT_REACHED_DISTANCE: float = 7.0
const SEARCH_RADIUS_CELLS: int = 10
const BUILD_BATCH_SIZE: int = 320
const UNBOUNDED_LIMIT: int = 1000000

var _player: LocalPlayer
var _map: Map
var _grid: AStarGrid2D
var _grid_ready: bool = false
var _build_generation: int = 0

var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _pending_target: Vector2
var _has_pending_target: bool = false


func setup(player: LocalPlayer) -> void:
	_player = player
	rebuild_for_map(
		InstanceClient.current.instance_map
		if InstanceClient.current != null
		else null
	)


func rebuild_for_map(map: Map) -> void:
	_build_generation += 1
	_grid_ready = false
	_grid = null
	_map = map
	cancel()
	if map != null:
		_build_grid.call_deferred(_build_generation, map)


func request_move(world_target: Vector2) -> void:
	_pending_target = world_target
	_has_pending_target = true
	if _grid_ready:
		_build_path(world_target)


func cancel() -> void:
	_path = PackedVector2Array()
	_path_index = 0
	_has_pending_target = false


func movement_direction() -> Vector2:
	if not _grid_ready or _path.is_empty():
		return Vector2.ZERO

	while _path_index < _path.size():
		var next_point: Vector2 = _path[_path_index]
		if _player.global_position.distance_to(next_point) > WAYPOINT_REACHED_DISTANCE:
			return _player.global_position.direction_to(next_point)
		_path_index += 1

	cancel()
	return Vector2.ZERO


func is_ready() -> bool:
	return _grid_ready


func _build_grid(generation: int, map: Map) -> void:
	# Arkenelle removes the persistent LocalPlayer from the old map before the
	# destination server spawns it into the new map. During that short window
	# Node.get_tree() is null, so wait through the process-wide SceneTree instead.
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree == null:
		return

	# Do not query a World2D until both reused nodes have entered the destination
	# tree. A newer transition cancels this build through the generation guard.
	while _build_is_current(generation, map) and (
		not _player.is_inside_tree()
		or not map.is_inside_tree()
	):
		await scene_tree.process_frame

	if not _build_is_current(generation, map):
		return
	if not _player.is_inside_tree() or not map.is_inside_tree():
		return

	await scene_tree.physics_frame
	if not _build_is_current(generation, map):
		return

	var bounds: Rect2 = _map_bounds(map)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return

	var start_id := Vector2i(
		floori(bounds.position.x / CELL_SIZE),
		floori(bounds.position.y / CELL_SIZE)
	)
	var end_id := Vector2i(
		ceili(bounds.end.x / CELL_SIZE),
		ceili(bounds.end.y / CELL_SIZE)
	)

	var grid := AStarGrid2D.new()
	grid.region = Rect2i(start_id, end_id - start_id)
	grid.cell_size = Vector2.ONE * CELL_SIZE
	grid.offset = Vector2.ONE * CELL_SIZE * 0.5
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()

	var shape := RectangleShape2D.new()
	shape.size = PLAYER_CLEARANCE
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = COLLISION_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var space: PhysicsDirectSpaceState2D = _player.get_world_2d().direct_space_state
	var processed: int = 0
	for y: int in range(grid.region.position.y, grid.region.end.y):
		for x: int in range(grid.region.position.x, grid.region.end.x):
			if not _build_is_current(generation, map):
				return
			var point_id := Vector2i(x, y)
			var point: Vector2 = grid.get_point_position(point_id)
			query.transform = Transform2D(
				0.0,
				point + PLAYER_SHAPE_OFFSET
			)
			if not space.intersect_shape(query, 1).is_empty():
				grid.set_point_solid(point_id, true)

			processed += 1
			if processed % BUILD_BATCH_SIZE == 0:
				await scene_tree.process_frame

	if not _build_is_current(generation, map):
		return
	_grid = grid
	_grid_ready = true
	if _has_pending_target:
		_build_path(_pending_target)


func _build_path(world_target: Vector2) -> void:
	if not _grid_ready or _grid == null:
		return
	var start_id: Vector2i = _nearest_walkable(
		_world_to_id(_player.global_position)
	)
	var target_id: Vector2i = _nearest_walkable(
		_world_to_id(world_target)
	)
	if start_id == Vector2i(-999999, -999999):
		return
	if target_id == Vector2i(-999999, -999999):
		return

	_path = _grid.get_point_path(start_id, target_id, false)
	_path_index = 0
	_has_pending_target = false
	if _path.size() > 1:
		_path_index = 1


func _nearest_walkable(origin: Vector2i) -> Vector2i:
	if (
		_grid.is_in_boundsv(origin)
		and not _grid.is_point_solid(origin)
	):
		return origin

	var best := Vector2i(-999999, -999999)
	var best_distance: float = INF
	for radius: int in range(1, SEARCH_RADIUS_CELLS + 1):
		for y: int in range(origin.y - radius, origin.y + radius + 1):
			for x: int in range(origin.x - radius, origin.x + radius + 1):
				if (
					x != origin.x - radius
					and x != origin.x + radius
					and y != origin.y - radius
					and y != origin.y + radius
				):
					continue
				var candidate := Vector2i(x, y)
				if not _grid.is_in_boundsv(candidate):
					continue
				if _grid.is_point_solid(candidate):
					continue
				var distance: float = Vector2(candidate).distance_squared_to(
					Vector2(origin)
				)
				if distance < best_distance:
					best = candidate
					best_distance = distance
		if best != Vector2i(-999999, -999999):
			return best
	return best


func _world_to_id(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / CELL_SIZE),
		floori(world_position.y / CELL_SIZE)
	)


func _map_bounds(map: Map) -> Rect2:
	if (
		abs(map.camera_limit_left) < UNBOUNDED_LIMIT
		and abs(map.camera_limit_top) < UNBOUNDED_LIMIT
		and abs(map.camera_limit_right) < UNBOUNDED_LIMIT
		and abs(map.camera_limit_bottom) < UNBOUNDED_LIMIT
	):
		return Rect2(
			Vector2(map.camera_limit_left, map.camera_limit_top),
			Vector2(
				map.camera_limit_right - map.camera_limit_left,
				map.camera_limit_bottom - map.camera_limit_top
			)
		)

	var combined := Rect2()
	var has_bounds: bool = false
	for node: Node in map.find_children("*", "TileMapLayer", true, false):
		var layer := node as TileMapLayer
		if layer == null or layer.tile_set == null:
			continue
		var used: Rect2i = layer.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		var first: Vector2 = layer.to_global(
			layer.map_to_local(used.position)
		)
		var last: Vector2 = layer.to_global(
			layer.map_to_local(used.end - Vector2i.ONE)
		)
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


func _build_is_current(generation: int, map: Map) -> bool:
	return (
		generation == _build_generation
		and is_instance_valid(_player)
		and is_instance_valid(map)
		and map == _map
	)
