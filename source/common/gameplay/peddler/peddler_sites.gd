class_name PeddlerSites
## Where the Traveling Peddler stands: which biome, and which square of it.
##
## THE BIOME is picked deterministically from the cycle index, so every server
## process — and any tool asking "where will the 16:00 peddler be?" — agrees. The
## pool is scanned from the biomes folder rather than listed here, so a new biome
## joins the rotation by existing.
##
## THE SQUARE IS AUTHORED AND FIXED. Each map carries [constant SPOT_NODE]
## markers (Node2D, "PeddlerSpot1".."PeddlerSpot3") and the cart always stands on
## the first one that still checks out. That is the whole placement rule now: one
## square per zone, the same one every window, so a zone's Peddler spot is
## something a player learns once. The later markers are fallbacks, not a
## rotation — see [method pick_spot].
##
## WHY IT IS AUTHORED, because this used to be inferred and the history is the
## argument. The square was probed live against the map's own collision, and each
## rule below was added after players found a cart standing in a wall:
##
##   * a straight-line ray -> a flood fill, because a ray is one pixel wide and
##     slips through the diagonal seam where two wall tiles meet at a corner;
##   * "nothing solid here" -> "and PAINTED", because unpainted nothing passes a
##     collider test perfectly — the walk left the map and set the cart down in
##     the black, 100px off the island in deep_shoals, and in the unpainted corner
##     of fungus_cave on 62 of 120 cycles;
##   * "any paint" -> "paint from a layer that paints FLOOR, vetoed by a wall
##     tile", because a wall is painted too and its tiles routinely overhang its
##     collider — 1397 such cells in sunken_tombs, 1156 in sunspire_terraces;
##   * a point sample -> a swept body, because nine sample points have gaps a
##     wall corner fits between, and the cart's sprite is four times its collider;
##   * plus elbow room, because a cart wedged in a one-tile nook reads as being in
##     the wall even when you can prove a player can reach it.
##
## Every one of those was a correct fix, and each found a new way for tile data to
## disagree with "a player can get here and it looks right". That question is not
## answerable from tile data, so it is now answered once, by a person, and CHECKED
## at build time by tools/verify_peddler_spots.tscn instead of re-decided on every
## 30-minute cycle in nineteen maps. A bad spot is now unshippable rather than
## unpredictable, which is the actual difference.
##
## The geometry rules survive as the CHECK ([method is_valid_spot]) rather than
## the chooser, and [method walkable_cells] survives for the tools that propose
## spots and audit them.
##
## SOME MAPS ARE NOT SITES AT ALL. A boss arena is one sealed pad built around one
## fight — nobody passes through it and dying in it ejects you — so it is barred
## from the pool by name ([constant EXCLUDED_BIOMES]).
##
## A map with no markers falls back to [method failsafe_anchor] every cycle. The
## gate exists so that never silently becomes the normal case.

const BIOMES_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/"

## Biomes the cart never visits, whatever the cycle hashes to. The pool is
## SCANNED rather than listed so a new zone joins the rotation by existing, which
## is right for a zone and wrong for a map players cannot walk into. Two kinds
## qualify:
##
##   * AN ARENA. the_hollow is the only entry in the biomes folder built as one
##     (ArenaWalls, a BossPad and a golem parked on it): a single sealed pad
##     around a single fight, with no through-traffic to find a cart in it and a
##     death return that ejects you out of it. It is where the cart was reported
##     standing on the boundary.
##
##   * A MAP WITH NO WAY IN. woodland_east is one: the biome resource and its
##     map exist, but nothing in the project routes to them — no warper, no
##     quick-travel destination, no death return. The live east expansion is the
##     east wing INSIDE woodland_tiles (woodland_east_shore + woodland_east_link
##     are instanced there), and this .tres is what was left behind when it
##     moved. Only this folder scan still finds it, so the cart was the one
##     thing that ever went there: roughly one window in nineteen announced
##     "A Traveling Peddler has set up in Goblin Woodlands East" and then stood
##     for thirty minutes in a map no player can reach.
##
## Matched case-insensitively against instance_name, which is not consistently
## cased across the pool (Forest, FungusArea1, pirates_cove), and against the
## biome file's own stem, so a rename of either one cannot quietly re-admit an
## excluded map.
const EXCLUDED_BIOMES: PackedStringArray = [
	"the_hollow", "hollow",
	"woodland_east",
]

## Layer-name fragments that mean "this layer paints FLOOR". Matched
## case-insensitively as substrings, so Ground / Ground2 / GroundDetail /
## UpperGround / Floor / Deck / Terrain all qualify without being listed.
const GROUND_LAYERS: PackedStringArray = ["ground", "floor", "terrain", "deck"]
## ...and the fragments that mean "this layer paints STRUCTURE" — the tiles a
## square is under rather than on. Tested FIRST, so a name that reads both ways
## resolves as structure.
##
## Structure only, and that line is drawn where it is on evidence. A layer earns
## a veto by being one whose paint routinely OVERHANGS its collider — a wall's
## top row, a mountain's cliff face, a roof, a cave ceiling. Scenery does not:
## Props here is a decoration layer painted straight over walkable floor
## (gutterworks runs a band of it down the middle of a corridor, fungus_cave
## paints GroundProps across its whole floor), and vetoing it rejected both maps
## outright and sent the cart to the spawn pad on all 200 sampled cycles. A crate
## you cannot walk through carries a SCENERY collider, and
## [method _is_standable] is what that collider is for.
const BLOCKING_LAYERS: PackedStringArray = [
	"wall", "collider", "collision", "obstacle", "roof", "ceiling",
	"mountain", "tree",
]

## Name prefix of the authored marker nodes. Any Node2D under the map whose name
## starts with this is a place the cart may stand.
const SPOT_NODE: String = "PeddlerSpot"
## How far [method walkable_cells] may wander from its origin. Only tools use the
## fill now, and this is the old MAX_RADIUS x FILL_DETOUR product it used to work
## out to, kept so the audits measure the same area they always did. Callers that
## want a wider sweep pass their own.
const FILL_BUDGET: float = 780.0
## The cart's own body, from the shared character scene the Peddler is built out
## of (character.tscn's CollisionShape2D): a 12x8 box sitting 3px above the node
## origin. The probe uses the REAL footprint, because "this pixel is clear" and
## "the cart fits here" are different questions and only the second one may place
## a cart.
const BODY_SIZE: Vector2 = Vector2(12.0, 8.0)
const BODY_OFFSET: Vector2 = Vector2(0.0, -3.0)
## Breathing room grown onto every side of the body before it is swept. A wall
## collider this close to the cart rejects the square.
const CLEARANCE: float = 16.0
## Reachability-fill resolution: half a 32px tile, so a wall is two cells thick
## in every direction and the fill cannot leak through a corner the way a ray
## can. Also the lattice the cart ends up standing on.
const FILL_STEP: float = 16.0
## Hard stop on fill size, so a map with an unwalled edge cannot cost a world
## server an unbounded loop. The DEFAULT, not the limit: a caller may raise it
## via [method walkable_cells]'s cell_cap, and an offline gate walking a whole
## map has to — at this cap the fill truncates on the larger maps, and a
## truncated fill cannot tell "unreachable" from "ran out of room". Nothing on
## the live server path passes anything but this.
const FILL_CELL_CAP: int = 20000
const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]
## Where the Vault Chest stands relative to the Peddler.
const VAULT_OFFSET: Vector2 = Vector2(40.0, 6.0)
## An author can drop a Node2D with this name into a map to say "park the cart
## HERE when the probe cannot place it". Optional: a map without one falls back
## to its own spawn point, which is reachable by definition.
const ANCHOR_NODE: String = "PeddlerAnchor"

## instance_name -> InstanceResource for every biome, name-sorted. Empty until
## _scan(). Sorted for the same reason [PeddlerCatalog] sorts: the cycle hash
## indexes into it, and directory order is not a guarantee.
static var _biomes: Array[StringName] = []
static var _scanned: bool = false
## The clearance-grown body, built once — see [method _body_probe].
static var _probe_shape: RectangleShape2D = null


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


## The square the cart stands on in [param map], plus the square beside it for
## the Vault Chest, as {"peddler": Vector2, "vault": Vector2} in GLOBAL
## coordinates.
##
## ONE FIXED SQUARE PER MAP: the first authored marker in name order,
## PeddlerSpot1. Takes no cycle, because the answer no longer depends on one.
##
## It used to. The cart moved between a map's three markers on a cycle hash,
## which meant "where does the Peddler stand in the desert" had three answers and
## a player who had found it once still had to sweep the zone the next time. The
## half-hour window is short enough that searching a map is most of it. A fixed,
## learnable square per zone is what lets somebody read the announcement, know
## where they are going, and get there — which is the entire point of the cart
## being somewhere specific.
##
## The other markers are not wasted: they are the FALLBACKS, tried in name order
## when the one before them does not survive [method is_valid_spot]. That check
## failing means the MAP moved under the marker — a wall extended over it, a prop
## dropped on it — because every authored spot was checked by
## tools/verify_peddler_spots.tscn when it shipped. Falling through to spot 2
## keeps the cart somewhere a person chose, rather than dumping it on the spawn
## pad the moment one square goes bad.
##
## Falls back to the home spawn only when NO authored spot qualifies — a cart on
## the spawn pad is worse placement, not a broken window.
static func pick_spot(map: Map) -> Dictionary:
	for spot: Vector2 in authored_spots(map):
		if is_valid_spot(map, spot):
			return {"peddler": spot, "vault": _vault_spot(map, {}, spot)}
		push_warning(
			"PeddlerSites: authored spot %s is no longer valid; trying the next marker." % spot
		)
	var anchor: Vector2 = failsafe_anchor(map)
	return {"peddler": anchor, "vault": _vault_spot(map, {}, anchor)}


## The squares an author marked in [param map], ordered by marker NAME.
##
## Ordered because the cycle hash indexes into this array, so two world servers
## hosting the same biome have to agree on it. Sorted on String, not StringName:
## comparing StringNames sorts by pointer, which is stable within one process and
## different in the next — the exact way an "every server agrees" list quietly
## stops agreeing.
static func authored_spots(map: Map) -> PackedVector2Array:
	var out := PackedVector2Array()
	if map == null:
		return out
	var markers: Array[Node] = map.find_children("%s*" % SPOT_NODE, "Node2D", true, false)
	markers.sort_custom(func(a: Node, b: Node) -> bool:
		return String(a.name) < String(b.name))
	for marker: Node in markers:
		out.append((marker as Node2D).global_position)
	return out


## Where the cart goes when the probe cannot place it: the map's own
## [constant ANCHOR_NODE] if an author placed one, else the home spawn.
##
## The spawn is a poor SITE — it is where everyone arrives, so the cart is not
## somewhere to walk to — but it is the one point in any map guaranteed to exist,
## be clear and be reachable, which is what a failsafe has to be. Author an
## [constant ANCHOR_NODE] in a map to do better than it.
static func failsafe_anchor(map: Map) -> Vector2:
	if map == null:
		return Vector2.ZERO
	var node: Node2D = map.find_child(ANCHOR_NODE, true, false) as Node2D
	if node != null:
		return node.global_position
	return map.get_spawn_position(0)


## Everything a square must be before a cart may stand on it: nothing solid on it
## or within [constant CLEARANCE] of it, and — on a map that HAS floor paint —
## painted floor under it. Public so a tool can ask the question in the same
## words the placement does.
##
## The paint half is conditional for the same reason it is in
## [method walkable_cells]: a map built without tile layers has no paint for any
## square, so an unconditional test answers false for every point on it and says
## nothing. deep_shoals is that map, and it is not a hole in the check — its land
## is bounded by REAL colliders (water, prop footprints and a sealed outer rim,
## see beach_area_colliders.gd), so "clear" there already means "on the island"
## in a way it does not on a tile map.
static func is_valid_spot(map: Map, point: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = _space(map)
	if space == null:
		return false
	if not _is_standable(space, point):
		return false
	if ground_layers(map).is_empty():
		return true
	return _has_paint(_tile_layers(map), point)


## True when [param biome] is barred from the rotation — see
## [constant EXCLUDED_BIOMES]. Public so a tool auditing the biomes folder can
## tell "this map places the cart badly" from "the cart never goes here".
static func is_excluded(biome: StringName) -> bool:
	return EXCLUDED_BIOMES.has(String(biome).to_lower())


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
static func walkable_cells(
	map: Map, origin: Vector2, budget: float = FILL_BUDGET,
	cell_cap: int = FILL_CELL_CAP
) -> Dictionary:
	var cells: Dictionary = {}
	var space: PhysicsDirectSpaceState2D = _space(map)
	if space == null:
		return cells
	var layers: Array[TileMapLayer] = _tile_layers(map)
	# Checked whenever the map has floor paint to check AGAINST. A map with no
	# ground layer would have every cell rejected, so it is left unchecked and
	# answers with a plain open-space walk — pick_spot sends those maps to the
	# anchor anyway, but a caller asking what is walkable deserves a real answer.
	var check_paint: bool = not ground_layers(map).is_empty()
	var bounds: Rect2 = playable_rect(map)
	# A map built without tile layers (deep_shoals) has no painted rect, and one
	# whose spawn sits outside it is telling us the rect is not the play area.
	# Either way, fall back to the detour budget alone rather than to a fill that
	# cannot leave its first cell.
	var bounded: bool = bounds.has_area() and bounds.has_point(origin)
	var start: Vector2i = _cell_of(origin)
	cells[start] = true
	var queue: Array[Vector2i] = [start]
	# Walked with an index rather than pop_front(): the fill is thousands of cells
	# and Array.pop_front() is O(n), which would make the walk quadratic.
	var head: int = 0
	while head < queue.size() and cells.size() < cell_cap:
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
			# The test that keeps the walk on the map, and off the walls.
			# Clear-but-unpainted is the void, and the rect bound above cannot catch
			# it: that rect merges EVERY layer, so a hole in the floor of a painted
			# map sits well inside it — as does the painted wall ring at the map's
			# edge, whose collider is narrower than its tiles. Both are excluded
			# here, which is what keeps boundary wall tops out of the cell pool
			# entirely rather than out of the final square only.
			if check_paint and not _has_paint(layers, point):
				continue
			cells[next] = true
			queue.append(next)
	# The seed went in unchecked, because the walk needs somewhere to start and
	# the origin is where a player is standing. It is not a RESULT, though, and a
	# spawn pad tucked under a wall tile (fungus_cave) would otherwise hand back
	# the one cell this whole test exists to exclude.
	if check_paint and not _has_paint(layers, origin):
		cells.erase(start)
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
	var layers: Array[TileMapLayer] = _tile_layers(map)
	var check_paint: bool = not ground_layers(map).is_empty()
	for offset: Vector2 in [VAULT_OFFSET, Vector2(-VAULT_OFFSET.x, VAULT_OFFSET.y)]:
		var candidate: Vector2 = peddler + offset
		# walkable is empty on the anchor path (no fill was run) — the chest then
		# rides the same paint + clearance test the anchor itself passed.
		if check_paint and not _has_paint(layers, candidate):
			continue
		if _is_standable(space, candidate) and (walkable.is_empty() or walkable.has(_cell_of(candidate))):
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


## True when the cart's own body FITS at [param point], with [constant CLEARANCE]
## to spare on every side of it.
##
## A SHAPE SWEEP, not a ring of sample points. The ring was the centre plus eight
## points on a 20px circle, and nine samples is nine samples: a wall corner fits
## between two of them, a pillar fits inside them, and the square still read
## clear. Sweeping the actual body grown by the clearance has no gaps to slip
## through and asks the question placement actually cares about — is there room
## for the cart — instead of a proxy for it.
static func _is_standable(space: PhysicsDirectSpaceState2D, point: Vector2) -> bool:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _body_probe()
	query.transform = Transform2D(0.0, point + BODY_OFFSET)
	query.collision_mask = PhysicsLayers.SOLID_GROUND_MASK
	query.collide_with_areas = false
	# One hit is all the answer there is; asking for more is wasted broadphase.
	return space.intersect_shape(query, 1).is_empty()


## The cart's footprint grown by [constant CLEARANCE] on every side.
##
## Built once and reused: a RectangleShape2D holds no per-query state, and
## placement sweeps it a few thousand times per window.
static func _body_probe() -> RectangleShape2D:
	if _probe_shape == null:
		_probe_shape = RectangleShape2D.new()
		_probe_shape.size = BODY_SIZE + Vector2.ONE * (CLEARANCE * 2.0)
	return _probe_shape


## True when [param point] stands on painted FLOOR: a ground layer has a tile
## over it, and no structural layer does.
##
## "Some layer has a tile here" used to be the whole test, on the reasoning that
## walls are painted too but [method _is_standable] would reject them for being
## solid. That holds only where a wall's collider covers every tile the wall
## paints, and it frequently does not — a top row drawn above the collider, a run
## of blocks continued past the end of one. The square out there is clear and
## painted at the same time, which is a wall top the walk is happy to stand a
## cart on: 1397 such cells in sunken_tombs, 1156 in sunspire_terraces, 466 in
## desert, 260 in Forest, all of them now excluded.
##
## So paint only counts from a layer that paints floor, and a structural tile is
## a VETO rather than merely a non-vote. The veto is the half that does the work
## at a boundary, where the ground layer usually runs on underneath the wall
## ring: "is there ground here" is true up there too. "Is there also a wall" is not.
static func _has_paint(layers: Array[TileMapLayer], point: Vector2) -> bool:
	var on_floor: bool = false
	for layer: TileMapLayer in layers:
		if layer.get_cell_source_id(layer.local_to_map(layer.to_local(point))) == -1:
			continue
		if _layer_matches(layer, BLOCKING_LAYERS):
			return false
		if _layer_matches(layer, GROUND_LAYERS):
			on_floor = true
	return on_floor


## True when [param layer]'s name contains any of [param hints], case-insensitively.
static func _layer_matches(layer: TileMapLayer, hints: PackedStringArray) -> bool:
	var lower: String = String(layer.name).to_lower()
	for hint: String in hints:
		if lower.contains(hint):
			return true
	return false


## The layers of [param map] that paint floor. Empty means the map cannot be
## validated at all — there is nothing in it that tells floor from void — and
## such a map gets its anchor rather than a square nobody can vouch for.
##
## Named "Ground" in every biome in the pool today (gutterworks and sewers add
## "Deck", mining_cave "GroundDetail"). Checked by HINT rather than by exact name
## because the failure mode of a name rule is silent — a map whose floor layer is
## called something unlisted does not error, it just stops offering squares and
## quietly puts the cart on the spawn pad forever. That is the case
## tools/audit_peddler_ground_rule.tscn exists to fail on.
static func ground_layers(map: Map) -> Array[TileMapLayer]:
	var out: Array[TileMapLayer] = []
	for layer: TileMapLayer in _tile_layers(map):
		if _layer_matches(layer, BLOCKING_LAYERS):
			continue
		if _layer_matches(layer, GROUND_LAYERS):
			out.append(layer)
	return out


## True when nothing solid sits exactly on [param point].
##
## Still a POINT test, and only used by the flood fill: the fill visits thousands
## of cells and a shape sweep on each would be a five-figure broadphase bill
## every window. It does not have to be exact there — it decides which cells the
## walk may pass through, and every cell it hands on as a CANDIDATE is then swept
## properly by [method _is_standable].
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


## Non-negative, stable hash of a cycle index. Drives the biome rotation only —
## the square within a biome is fixed ([method pick_spot]). The salt is kept so
## the rotation a live world produces does not change under anyone who has
## learned it.
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
		# Barred by instance_name OR by file stem: four biomes are named
		# differently from their .tres (Forest/forest, FungusArea1/fungus_cave,
		# pirates_cove/deep_shoals), so keying off one alone would let a rename of
		# the other quietly re-admit an arena to the rotation.
		if is_excluded(name) or is_excluded(StringName(file_name.get_basename())):
			continue
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
