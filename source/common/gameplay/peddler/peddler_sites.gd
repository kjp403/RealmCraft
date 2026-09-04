class_name PeddlerSites
## Where the Traveling Peddler stands: which biome, and which square of it.
##
## THE BIOME is picked deterministically from the cycle index, so every server
## process — and any tool asking "where will the 16:00 peddler be?" — agrees. The
## pool is scanned from the biomes folder rather than listed here, so a new biome
## joins the rotation by existing.
##
## THE SQUARE is probed live against the map's own collision, because there is no
## authored "peddler stands here" marker and inventing one for nineteen maps
## would be nineteen chances to place a cart inside a wall. It is chosen from the
## squares a player could WALK to from the map's home spawn — a flood fill, not
## the straight-line ray this used to trust. A ray is one pixel wide: it slips
## through the diagonal seam where two wall tiles meet at a corner, through gaps
## no body fits down, and out into the unpainted nothing behind a wall run. Every
## one of those reads to a player as a cart parked inside the wall — reported in
## the sewers, measured worst in the_hollow, where a third of all cycles put the
## cart somewhere no one could reach it (tools/audit_peddler_spots.tscn).
##
## Probing needs the map's live physics space, so the square can only be chosen
## once the instance is actually loaded. The BIOME choice does not, which is why
## the two are separate calls.

const BIOMES_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
## How far from the home spawn the cart may set up.
const MIN_RADIUS: float = 90.0
const MAX_RADIUS: float = 260.0
## Clearance required around the chosen point, so the cart is not flush to a wall.
const CLEARANCE: float = 20.0
## Reachability-fill resolution: half a 32px tile, so a wall is two cells thick
## in every direction and the fill cannot leak through a corner the way a ray
## can. Also the lattice the cart ends up standing on.
const FILL_STEP: float = 16.0
## How far the fill may wander past [constant MAX_RADIUS] to reach a square, as a
## multiple of it. Any square the cart may use is at most MAX_RADIUS from the
## spawn; a walk to one that needs a longer detour than this is not worth the
## point queries it costs to prove.
const FILL_DETOUR: float = 3.0
## Hard stop on fill size, so a map with an unwalled edge cannot cost a world
## server an unbounded loop.
const FILL_CELL_CAP: int = 20000
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
## Where the Vault Chest stands relative to the Peddler.
const VAULT_OFFSET: Vector2 = Vector2(40.0, 6.0)

## instance_name -> InstanceResource for every biome, name-sorted. Empty until
## _scan(). Sorted for the same reason [PeddlerCatalog] sorts: the cycle hash
## indexes into it, and directory order is not a guarantee.
static var _biomes: Array[StringName] = []
static var _scanned: bool = false


## Every biome instance name, sorted. The rotation pool.
static func biome_names() -> Array[StringName]:
	_scan()
	return _biomes


## Which biome the Peddler visits on [param cycle_index]. Empty when no biome
## resource could be scanned at all.
static func biome_for_cycle(cycle_index: int) -> StringName:
	var order: Array[StringName] = rotation_for_cycle(cycle_index)
	return order[0] if not order.is_empty() else &""


## The FULL rotation for [param cycle_index]: every biome, starting at the one
## the cycle hashed to and wrapping around.
##
## The manager walks this rather than taking the first entry alone, because a
## biome can turn out to be unable to host the cart — a map whose
## ReplicatedPropsContainer was never wired up cannot carry a dynamic prop, and
## sending the Peddler there would mean a whole 30-minute window in which they
## silently never appear. Walking a deterministic order means the fallback lands
## on the same biome for everyone, and that a map fixed later rejoins the
## rotation with no change here.
static func rotation_for_cycle(cycle_index: int) -> Array[StringName]:
	_scan()
	var order: Array[StringName] = []
	if _biomes.is_empty():
		return order
	var start: int = _cycle_hash(cycle_index) % _biomes.size()
	for i: int in _biomes.size():
		order.append(_biomes[(start + i) % _biomes.size()])
	return order


## A standable point in [param map] for [param cycle_index], plus the square
## beside it for the Vault Chest, as {"peddler": Vector2, "vault": Vector2} in
## GLOBAL coordinates.
##
## Falls back to the home spawn when nothing qualifies — a cart on the spawn pad
## is worse placement, not a broken window.
static func pick_spot(map: Map, cycle_index: int) -> Dictionary:
	var home: Vector2 = map.get_spawn_position(0)
	var walkable: Dictionary = walkable_cells(map, home)
	var spot: Vector2 = _choose(map, walkable, home, cycle_index)
	return {"peddler": spot, "vault": _vault_spot(map, walkable, spot)}


## Pick this cycle's square out of [param walkable]: far enough from the spawn to
## be somewhere to go, near enough to be found, with room around it.
static func _choose(
	map: Map, walkable: Dictionary, home: Vector2, cycle_index: int
) -> Vector2:
	var space: PhysicsDirectSpaceState2D = _space(map)
	if space == null:
		return home
	var candidates: Array[Vector2i] = []
	for cell: Vector2i in walkable:
		var point: Vector2 = _cell_center(cell)
		var away: float = home.distance_to(point)
		if away < MIN_RADIUS or away > MAX_RADIUS:
			continue
		if not _is_standable(space, point):
			continue
		# Open on all eight sides, in FILL_STEP cells: a 48px box of floor the
		# player can actually walk around the cart in. Clearance alone still
		# accepts a one-tile dead-end nook, and a cart wedged in one reads as
		# being in the wall even though the probe can prove you can reach it.
		if not _has_elbow_room(walkable, cell):
			continue
		candidates.append(cell)
	if candidates.is_empty():
		return home
	# BY COORDINATE, not in whatever order the fill happened to reach cells in.
	# The cycle hash indexes into this array, so two world servers hosting the
	# same biome have to agree on it — the same promise the biome pool's sort
	# keeps, and the same way to break it.
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.y == b.y else a.y < b.y
	)
	return _cell_center(candidates[_cycle_hash(cycle_index) % candidates.size()])


## True when every cell touching [param cell] is walkable too.
static func _has_elbow_room(walkable: Dictionary, cell: Vector2i) -> bool:
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			if not walkable.has(cell + Vector2i(dx, dy)):
				return false
	return true


## Every square a player could WALK to from [param origin], as a set of cell
## keys. This is the placement rule: a square in here is one somebody can reach
## on foot, which a clear point with a clear sightline is not.
##
## Bounded twice, because it runs inside a live world server. To the map's
## PAINTED rect — past it there are no colliders at all, so an unbounded fill
## runs around the outside of the map and re-enters every sealed pocket that
## touches an edge, calling the whole lot reachable. And to a detour budget
## around the origin. Together they keep the walk to a few thousand point
## queries, once per 30-minute window.
static func walkable_cells(map: Map, origin: Vector2) -> Dictionary:
	var cells: Dictionary = {}
	var space: PhysicsDirectSpaceState2D = _space(map)
	if space == null:
		return cells
	var bounds: Rect2 = playable_rect(map)
	# A map built without tile layers (deep_shoals) has no painted rect, and one
	# whose spawn sits outside it is telling us the rect is not the play area.
	# Either way, fall back to the detour budget alone rather than to a fill that
	# cannot leave its first cell.
	var bounded: bool = bounds.has_area() and bounds.has_point(origin)
	var budget: float = MAX_RADIUS * FILL_DETOUR
	var start: Vector2i = _cell_of(origin)
	cells[start] = true
	var queue: Array[Vector2i] = [start]
	# Walked with an index rather than pop_front(): the fill is thousands of cells
	# and Array.pop_front() is O(n), which would make the walk quadratic.
	var head: int = 0
	while head < queue.size() and cells.size() < FILL_CELL_CAP:
		var cell: Vector2i = queue[head]
		head += 1
		for offset: Vector2i in _NEIGHBOURS:
			var next: Vector2i = cell + offset
			if cells.has(next):
				continue
			var point: Vector2 = _cell_center(next)
			if origin.distance_to(point) > budget:
				continue
			if bounded and not bounds.has_point(point):
				continue
			if not _clear_at(space, point):
				continue
			cells[next] = true
			queue.append(next)
	return cells


## The world rect [param map] actually has tiles in, or an empty rect for a map
## built without tile layers.
##
## NOT the camera limits: on most maps those sit a tile OUTSIDE the tiles, and
## that ring is unpainted, uncollided space — exactly the gap a fill would run
## around the map in. On some maps they are TIGHTER than the tiles instead, which
## would wall the fill out of ground players can walk on.
static func playable_rect(map: Map) -> Rect2:
	var rect := Rect2()
	for layer: TileMapLayer in _tile_layers(map):
		var used: Rect2i = layer.get_used_rect()
		if used.size == Vector2i.ZERO or layer.tile_set == null:
			continue
		var tile: Vector2 = Vector2(layer.tile_set.tile_size)
		var world := Rect2(
			layer.to_global(layer.map_to_local(used.position) - tile * 0.5),
			Vector2(used.size) * tile
		)
		rect = world if not rect.has_area() else rect.merge(world)
	return rect


static func _tile_layers(node: Node, out: Array[TileMapLayer] = []) -> Array[TileMapLayer]:
	for child: Node in node.get_children():
		if child is TileMapLayer:
			out.append(child as TileMapLayer)
		_tile_layers(child, out)
	return out


static func _cell_of(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / FILL_STEP), floori(point.y / FILL_STEP))


static func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell) * FILL_STEP + Vector2.ONE * (FILL_STEP * 0.5)


## The chest's square: beside the Peddler if that is clear and walk-reachable,
## otherwise mirrored to the other side, otherwise on top of them (visually
## tight, still clickable).
static func _vault_spot(map: Map, walkable: Dictionary, peddler: Vector2) -> Vector2:
	var space: PhysicsDirectSpaceState2D = _space(map)
	if space == null:
		return peddler + VAULT_OFFSET
	for offset: Vector2 in [VAULT_OFFSET, Vector2(-VAULT_OFFSET.x, VAULT_OFFSET.y)]:
		var candidate: Vector2 = peddler + offset
		if _is_standable(space, candidate) and walkable.has(_cell_of(candidate)):
			return candidate
	return peddler + VAULT_OFFSET


## The nearest square to [param origin] in [param map] that something can be put
## down on, searching outward, or [param origin] itself when nothing probes clear.
##
## The public half of the cart's placement probe, for anything that has to drop a
## prop at a player's feet (the Portable Deposit Box). Reuses the same standable
## + reachable pair the Peddler is placed with, so a box and a cart can never
## disagree about what counts as a valid floor.
static func nearest_standable(
	map: Map, origin: Vector2, max_radius: float = 64.0
) -> Vector2:
	var space: PhysicsDirectSpaceState2D = _space(map)
	if space == null:
		return origin
	if _is_standable(space, origin):
		return origin
	# Rings outward rather than random probes: a box belongs as close to where
	# the player stood as the geometry allows, not somewhere plausible nearby.
	var step: float = maxf(8.0, CLEARANCE * 0.5)
	var radius: float = step
	while radius <= max_radius:
		for i: int in 8:
			var candidate: Vector2 = origin + Vector2.from_angle(float(i) * TAU / 8.0) * radius
			if _is_standable(space, candidate) and _is_reachable(space, origin, candidate):
				return candidate
		radius += step
	return origin


## True when nothing solid occupies [param point] or the ring of clearance around
## it. The ring matters: a bare point test passes in the one-pixel gap between two
## wall tiles, and a cart wedged there is unreachable.
static func _is_standable(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	if not _clear_at(space, point):
		return false
	# EIGHT points around the ring, not four: on a 32px tile grid the axial probes
	# straddle a corner tile without touching it, so the cart could be set down
	# with a wall block cutting diagonally into its square.
	for i: int in 8:
		var probe: Vector2 = point + Vector2.from_angle(float(i) * TAU / 8.0) * CLEARANCE
		if not _clear_at(space, probe):
			return false
	return true


static func _clear_at(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = point
	query.collision_mask = PhysicsLayers.SOLID_GROUND_MASK
	query.collide_with_areas = false
	return space.intersect_point(query, 1).is_empty()


## True when nothing solid sits on the straight line from [param from] to
## [param to]. Not true pathfinding — it is the cheap test that rejects the
## sealed-room case without a navigation bake.
static func _is_reachable(
	space: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2
) -> bool:
	var ray := PhysicsRayQueryParameters2D.create(from, to)
	ray.collision_mask = PhysicsLayers.SOLID_GROUND_MASK
	return space.intersect_ray(ray).is_empty()


static func _space(map: Map) -> PhysicsDirectSpaceState2D:
	if map == null or map.get_world_2d() == null:
		return null
	return map.get_world_2d().direct_space_state


## Non-negative, stable hash of a cycle index. Salted so the biome pick and the
## in-map probe do not both derive from the raw index and correlate.
static func _cycle_hash(cycle_index: int) -> int:
	return int(("peddler-site|%d" % cycle_index).hash()) & 0x7FFFFFFF


static func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	for file_name: String in ResourceLoader.list_directory(BIOMES_DIR):
		if not file_name.ends_with(".tres"):
			continue
		# Untyped load + cast, for the reason InstanceManager.set_instance_collection
		# gives: in an export the custom-class loader may not be registered when
		# this runs, and a typed hint trips the loader.
		var loaded: Resource = ResourceLoader.load(BIOMES_DIR + file_name)
		if loaded == null or not (loaded is InstanceResource):
			continue
		var name: StringName = (loaded as InstanceResource).instance_name
		if name != &"" and not _biomes.has(name):
			_biomes.append(name)
	# BY TEXT, not Array.sort(). StringName's `<` compares the interned pointer,
	# not the characters, so a plain sort() orders the pool by whatever address
	# the engine happened to hand each name — an order that changes with the
	# interning order of the whole process. That silently broke the promise this
	# file is built on: the same cycle index resolved to a DIFFERENT biome in a
	# world server, in a tool, and in the same world server after an unrelated
	# script started interning names earlier. Comparing the text is the only
	# ordering that is the same everywhere.
	_biomes.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
