class_name ClickNavigation
extends Node
## Client-side collision-aware click navigation. A walkability grid is generated
## from collision layer 2, the same layer the player already collides with.

const TRANSITION_FIX_VERSION: String = "2026-08-07-b"

const CELL_SIZE: float = 16.0
const COLLISION_MASK: int = 2

## Must be >= the body in `character.tscn`, or the grid marks cells walkable that
## the player physically cannot enter and the walk ends as a grind along a wall.
##
## It used to be 8x5 against a 16x10 body — half size on both axes — which is
## why click and minimap routes shoved the player into geometry. The body is now
## 12x8, and this carries 1px of margin over it so a cell the grid calls
## walkable is one the body genuinely fits through.
const PLAYER_CLEARANCE: Vector2 = Vector2(13.0, 9.0)
## Matches the CollisionShape2D offset on the character body: the box is at the
## feet, not the sprite centre.
const PLAYER_SHAPE_OFFSET: Vector2 = Vector2(0.0, -3.0)
## Tight enough that the walker stays near the cell centres the grid proved
## clear. At the old 7.0 the player could be most of a tile off the path and
## clip the corner the grid had just routed it around.
const WAYPOINT_REACHED_DISTANCE: float = 4.0
const SEARCH_RADIUS_CELLS: int = 10
## Time-budgeted instead of a fixed cell count: a physics shape query here
## measures ~5us, so a flat 320-cell batch (the old value) spent under 2ms of
## real work per yielded frame — on a biome sub-level map (~205k cells,
## Gutterworks/drowned_cistern/sunspire_terraces/sunken_tombs/ossuary, all
## ~5x a hub map like Sewers) that is 600+ frames, ~10s, of click-to-move
## silently doing nothing with zero player feedback while WASD still works,
## which reads as "click is just broken here." Budgeting real time instead
## keeps every frame cheap while finishing in a few hundred ms regardless of
## map size or hardware.
const BUILD_FRAME_BUDGET_USEC: int = 8000
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
## Last click destination, kept after the path is built so a door opening can
## repath through a gate the first route treated as a wall.
var _has_destination: bool = false
## Door/obstacle rects to re-query after the grid is ready (or after a physics
## frame so CollisionShape2D.set_deferred has landed). Dungeon doors start
## closed; without this, click-move keeps treating an opened gate as a wall.
var _pending_refresh_rects: Array[Rect2] = []
var _refresh_queued: bool = false


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
	if map != _map:
		_pending_refresh_rects.clear()
	_map = map
	cancel()
	if map != null:
		_build_grid.call_deferred(_build_generation, map)


func request_move(world_target: Vector2) -> void:
	_pending_target = world_target
	_has_pending_target = true
	_has_destination = true
	if _grid_ready:
		_build_path(world_target)


## Re-sample walkability in [param rects] after colliders change (dungeon doors
## opening/sealing). Cheap compared to a full map rebuild — only the overlapping
## cells are queried. Safe to call before the grid is ready; the rects wait.
func refresh_world_rects(rects: Array[Rect2]) -> void:
	if rects.is_empty():
		return
	for rect: Rect2 in rects:
		_pending_refresh_rects.append(rect)
	if not _grid_ready:
		return
	if _refresh_queued:
		return
	_refresh_queued = true
	_flush_refresh_rects.call_deferred()


func cancel() -> void:
	_path = PackedVector2Array()
	_path_index = 0
	_has_pending_target = false
	_has_destination = false


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
	# A diagonal step is only legal when BOTH orthogonal neighbours are clear.
	# `AT_LEAST_ONE_WALKABLE` lets the path cut round the outside of a corner —
	# geometrically shorter, but the body clips the corner it just routed past,
	# which reads to the player as the character catching on nothing.
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
	var batch_started_usec: int = Time.get_ticks_usec()
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

			if Time.get_ticks_usec() - batch_started_usec >= BUILD_FRAME_BUDGET_USEC:
				await scene_tree.process_frame
				batch_started_usec = Time.get_ticks_usec()

	if not _build_is_current(generation, map):
		return
	_grid = grid
	_grid_ready = true
	_apply_refresh_rects()
	if _has_pending_target:
		_build_path(_pending_target)
	elif _has_destination:
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


func _flush_refresh_rects() -> void:
	var scene_tree := Engine.get_main_loop() as SceneTree
	if scene_tree != null:
		await scene_tree.physics_frame
	_refresh_queued = false
	_apply_refresh_rects()
	if _has_destination and _grid_ready:
		_build_path(_pending_target)


func _apply_refresh_rects() -> void:
	if _pending_refresh_rects.is_empty() or not _grid_ready or _grid == null:
		_pending_refresh_rects.clear()
		return
	if _player == null or not _player.is_inside_tree():
		return
	var space: PhysicsDirectSpaceState2D = _player.get_world_2d().direct_space_state
	if space == null:
		return
	var shape := RectangleShape2D.new()
	shape.size = PLAYER_CLEARANCE
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = COLLISION_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var seen: Dictionary[Vector2i, bool] = {}
	for rect: Rect2 in _pending_refresh_rects:
		var expanded: Rect2 = rect.grow(maxi(PLAYER_CLEARANCE.x, PLAYER_CLEARANCE.y))
		var min_id := Vector2i(
			floori(expanded.position.x / CELL_SIZE),
			floori(expanded.position.y / CELL_SIZE)
		)
		var max_id := Vector2i(
			ceili(expanded.end.x / CELL_SIZE),
			ceili(expanded.end.y / CELL_SIZE)
		)
		for y: int in range(min_id.y, max_id.y + 1):
			for x: int in range(min_id.x, max_id.x + 1):
				var point_id := Vector2i(x, y)
				if seen.has(point_id) or not _grid.is_in_boundsv(point_id):
					continue
				seen[point_id] = true
				var point: Vector2 = _grid.get_point_position(point_id)
				query.transform = Transform2D(0.0, point + PLAYER_SHAPE_OFFSET)
				_grid.set_point_solid(point_id, not space.intersect_shape(query, 1).is_empty())
	_pending_refresh_rects.clear()
