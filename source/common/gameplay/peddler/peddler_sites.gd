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
## would be nineteen chances to place a cart inside a wall. The probe walks out
## from the map's home spawn and keeps the first candidate that is BOTH clear
## underfoot and reachable in a straight line from the spawn — the second half is
## what stops the cart landing in a sealed side-room (the arena_1 failure mode:
## authored geometry a player can see and never walk to).
##
## Probing needs the map's live physics space, so the square can only be chosen
## once the instance is actually loaded. The BIOME choice does not, which is why
## the two are separate calls.

const BIOMES_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
## How far from the home spawn the cart may set up.
const MIN_RADIUS: float = 90.0
const MAX_RADIUS: float = 260.0
## Probes before giving up and using the spawn point itself.
const PROBE_ATTEMPTS: int = 48
## Clearance required around the chosen point, so the cart is not flush to a wall.
const CLEARANCE: float = 20.0
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
## Falls back to the home spawn when nothing probes clear — a cart on the spawn
## pad is worse placement, not a broken window.
static func pick_spot(map: Map, cycle_index: int) -> Dictionary:
	var home: Vector2 = map.get_spawn_position(0)
	var spot: Vector2 = _probe(map, home, cycle_index)
	return {"peddler": spot, "vault": _vault_spot(map, spot)}


## Walk out from [param origin] looking for a clear, reachable square.
static func _probe(map: Map, origin: Vector2, cycle_index: int) -> Vector2:
	var space: PhysicsDirectSpaceState2D = _space(map)
	if space == null:
		return origin
	# Seeded so the same cycle probes the same candidates in the same order —
	# two world servers hosting the same biome put the cart in the same place.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _cycle_hash(cycle_index)
	for _attempt: int in PROBE_ATTEMPTS:
		var angle: float = rng.randf() * TAU
		var dist: float = rng.randf_range(MIN_RADIUS, MAX_RADIUS)
		var candidate: Vector2 = origin + Vector2.from_angle(angle) * dist
		if _is_standable(space, candidate) and _is_reachable(space, origin, candidate):
			return candidate
	return origin


## The chest's square: beside the Peddler if that is clear, otherwise mirrored to
## the other side, otherwise on top of them (visually tight, still clickable).
static func _vault_spot(map: Map, peddler: Vector2) -> Vector2:
	var space: PhysicsDirectSpaceState2D = _space(map)
	if space == null:
		return peddler + VAULT_OFFSET
	for offset: Vector2 in [VAULT_OFFSET, Vector2(-VAULT_OFFSET.x, VAULT_OFFSET.y)]:
		var candidate: Vector2 = peddler + offset
		if _is_standable(space, candidate) and _is_reachable(space, peddler, candidate):
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
	for i: int in 4:
		var probe: Vector2 = point + Vector2.from_angle(float(i) * TAU / 4.0) * CLEARANCE
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
	_biomes.sort()
