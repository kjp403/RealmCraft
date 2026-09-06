extends Node
## Diagnostic: is the square PeddlerSites picks one a PLAYER can actually stand on?
##
## TWO questions, because the cart has been wrong in two different ways:
##
##   REACHABLE — flood-fill the map's open cells outward from the home spawn and
##     check the chosen point is in that component. A point that is clear and
##     ray-visible but OUTSIDE the fill is the cart-in-the-wall bug: a pocket of
##     unpainted nothing behind a wall run, seen through a diagonal seam.
##
##   ON A FLOOR — ask [method PeddlerSites.is_valid_spot] whether a tile is
##     actually painted under it. This audit used to run its OWN fill with the
##     same "nothing solid here" test the placement used, so when the placement
##     walked out into the void the audit walked out with it and called the void
##     reachable. It reported a clean sweep while fungus_cave was putting the
##     cart in unpainted black on half its cycles. An audit that shares the bug
##     it is auditing for is worse than no audit, so this half deliberately asks
##     a question the fill cannot answer for itself.
##   godot --headless --path . --mode=client res://tools/audit_peddler_spots.tscn

const BIOMES_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const CYCLES: int = 200
## Only audit this biome when set — for chasing one reported sighting.
const FILTER: StringName = &""
## Real cycles either side of now to sweep as well, so a report of "the cart is
## in a wall right now" can be checked against the cycle that actually placed it.
const LIVE_WINDOW: int = 48
## Flood-fill resolution. Half a 32px tile, so a one-cell diagonal seam does not
## leak the fill into a sealed pocket the way a ray does.
const STEP: float = 16.0
const MAX_CELLS: int = 60000


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var bad_total: int = 0
	for file_name: String in ResourceLoader.list_directory(BIOMES_DIR):
		if not file_name.ends_with(".tres"):
			continue
		bad_total += await _audit(BIOMES_DIR + file_name)
	print("TOTAL bad placements (unreachable or floorless): %d" % bad_total)
	get_tree().quit(0)


func _audit(res_path: String) -> int:
	var biome: InstanceResource = ResourceLoader.load(res_path) as InstanceResource
	if biome == null:
		return 0
	if FILTER != &"" and biome.instance_name != FILTER:
		return 0
	var packed: PackedScene = load(biome.map_path) as PackedScene
	if packed == null:
		return 0
	var map: Node = packed.instantiate()
	add_child(map)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if map is not Map:
		map.queue_free()
		return 0
	var m: Map = map as Map
	var home: Vector2 = m.get_spawn_position(0)
	var space: PhysicsDirectSpaceState2D = m.get_world_2d().direct_space_state
	var bounds: Rect2 = _painted_rect(m)
	# Bounded only when the rect is real AND contains the spawn: deep_shoals has
	# no tile layers at all, and a rect that excludes the spawn is not the play
	# area.
	if not (bounds.has_area() and bounds.has_point(home)):
		bounds = Rect2()
	var open: Dictionary = _flood(space, home, bounds)
	var bad: int = 0
	var floorless: int = 0
	var lines: Array[String] = []
	for c: int in CYCLES:
		var p: Vector2 = PeddlerSites.pick_spot(m, c)["peddler"]
		var walkable: bool = open.has(_key(p))
		if not walkable:
			bad += 1
			if lines.size() < 6:
				lines.append("    cycle %2d  (%6d,%6d)  %5dpx from home  UNREACHABLE" % [
				c, p.x, p.y, p.distance_to(home)])
		# The anchor is the deliberate fallback, not a placement, and on a map
		# with no tile layers there is no paint for it to stand on by design.
		if p != PeddlerSites.failsafe_anchor(m) and not PeddlerSites.is_valid_spot(m, p):
			floorless += 1
			if lines.size() < 6:
				lines.append("    cycle %2d  (%6d,%6d)  NO FLOOR PAINTED UNDER IT" % [
				c, p.x, p.y])
	print("%-22s home=(%d,%d) open_cells=%d  unreachable=%d/%d  floorless=%d/%d" % [
		biome.instance_name, home.x, home.y, open.size(), bad, CYCLES,
		floorless, CYCLES])
	bad += floorless
	var live: int = PeddlerSchedule.cycle_index()
	for i: int in range(-LIVE_WINDOW, LIVE_WINDOW + 1):
		var cycle: int = live + i
		if PeddlerSites.biome_for_cycle(cycle) != biome.instance_name:
			continue
		var at: Vector2 = PeddlerSites.pick_spot(m, cycle)["peddler"]
		var when: String = Time.get_datetime_string_from_unix_time(
			PeddlerSchedule.cycle_start_s(cycle)
		)
		print("    LIVE cycle %d (%s UTC) -> (%d,%d) %s" % [
			cycle, when, at.x, at.y,
			"reachable" if open.has(_key(at)) else "UNREACHABLE",
		])
	for line: String in lines:
		print(line)
	map.queue_free()
	await get_tree().process_frame
	return bad


## The world rect the map actually has tiles in. NOT the camera limits: those sit
## a tile OUTSIDE the tiles on most maps, and that one-tile ring has no colliders
## at all, so a fill allowed into it runs around the outside of the map and
## re-enters every sealed pocket that touches an edge — which is exactly the
## geometry this audit is trying to catch.
static func _painted_rect(map: Map) -> Rect2:
	var rect := Rect2()
	var first: bool = true
	for layer: TileMapLayer in _tile_layers(map):
		var used: Rect2i = layer.get_used_rect()
		if used.size == Vector2i.ZERO:
			continue
		var world := Rect2(
			layer.to_global(layer.map_to_local(used.position) - Vector2(layer.tile_set.tile_size) * 0.5),
			Vector2(used.size * layer.tile_set.tile_size)
		)
		rect = world if first else rect.merge(world)
		first = false
	return rect


static func _tile_layers(node: Node, out: Array[TileMapLayer] = []) -> Array[TileMapLayer]:
	for child: Node in node.get_children():
		if child is TileMapLayer:
			out.append(child as TileMapLayer)
		_tile_layers(child, out)
	return out


static func _key(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / STEP), floori(point.y / STEP))


## Every STEP-cell reachable from [param origin] without crossing something solid.
static func _flood(
	space: PhysicsDirectSpaceState2D, origin: Vector2, bounds: Rect2
) -> Dictionary:
	var seen: Dictionary = {}
	var start: Vector2i = _key(origin)
	seen[start] = true
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty() and seen.size() < MAX_CELLS:
		var cell: Vector2i = queue.pop_front()
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + offset
			if seen.has(next):
				continue
			var point := Vector2((next.x + 0.5) * STEP, (next.y + 0.5) * STEP)
			# The fill stops at the map's own camera limits. Past them there are
			# no colliders at all, so an unbounded fill would flow around the
			# outside of the map and call every sealed pocket reachable.
			if bounds.has_area() and not bounds.has_point(point):
				continue
			var query := PhysicsPointQueryParameters2D.new()
			query.position = point
			query.collision_mask = PhysicsLayers.SOLID_GROUND_MASK
			query.collide_with_areas = false
			if not space.intersect_point(query, 1).is_empty():
				continue
			seen[next] = true
			queue.append(next)
	return seen
