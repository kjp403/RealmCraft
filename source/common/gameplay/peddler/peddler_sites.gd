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
## A CLEAR SQUARE IS NOT A FLOOR. The probe's per-cell test used to be "does
## anything solid overlap this point", and unpainted nothing passes that test
## perfectly: there is no collider out there to hit. So the walk could leave the
## painted map entirely and set the cart down in the black — 100px off the island
## in deep_shoals, and in the unpainted top-left corner of fungus_cave on 62 of
## 120 cycles (measured, not guessed). Every cell now has to be PAINTED as well
## as clear (see [method _has_paint]), which is the only test that tells floor
## from void on a tile map.
##
## A map with no tile layers at all (deep_shoals is one ground Sprite2D) has
## nothing to validate against, so it gets no random square: it goes straight to
## [method failsafe_anchor], and so does any cycle whose walk turns up nothing.
##
## PAINT IS NOT FLOOR EITHER. The paint test above was "does ANY layer have a
## tile here", and a wall is painted. Wherever a wall's tiles reach further than
## its collider — an overhanging top row, a decorative run past the end of a
## block — the square out there is clear (nothing to hit) AND painted (the Walls
## layer), both halves true and both halves wrong. Measured, the old walk
## accepted 1397 such cells in sunken_tombs, 1156 in sunspire_terraces, 466 in
## desert and 260 in Forest. Only a layer that PAINTS FLOOR votes for floor now,
## and a wall / roof / cliff tile over the same square vetoes it outright — the
## veto being the half that matters at a boundary, where the ground layer usually
## runs on underneath the wall ring (see [method _has_paint]).
##
## AND THE CART IS NOT A POINT. Clearance used to be the centre plus eight
## samples on a 20px circle, and nine samples is nine samples: a wall corner sits
## between two of them and the square still reads clear. The cart's centre is
## then genuinely on floor while its body is inside the wall — and its sprite is
## four times the size of its 12x8 collision box, so that reads to a player as a
## cart in the wall just as much as being out of bounds does. The probe now
## sweeps the real body grown by [constant CLEARANCE] (see
## [method _is_standable]); that alone drops 191 of the_hollow's 2262 squares,
## 110 of Forest's and 44 of fungus_cave's.
##
## SOME MAPS ARE NOT SITES AT ALL. A boss arena is one sealed pad built around
## one fight — nobody passes through it and dying in it ejects you — so it is
## barred from the pool by name ([constant EXCLUDED_BIOMES]) rather than left to
## the geometry tests to make unattractive.
##
## Both geometry rules are gated by tools/audit_peddler_ground_rule.tscn, which
## runs the old rules beside the live ones over every biome and fails EITHER way:
## a wall-painted cell still in the pool, or a map so over-rejected that every
## cycle falls back to the anchor.
##
## Probing needs the map's live physics space, so the square can only be chosen
## once the instance is actually loaded. The BIOME choice does not, which is why
## the two are separate calls.

const BIOMES_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/"

## Biomes the cart never visits, whatever the cycle hashes to. The pool is
## SCANNED rather than listed so a new zone joins the rotation by existing, which
## is right for a zone and wrong for a boss arena: an arena is a single sealed
## pad around a single fight, with no through-traffic to find a cart in it and a
## death return that ejects you out of it. the_hollow is the whole current list:
## it is the only entry in the biomes folder built as an arena (ArenaWalls, a
## BossPad and a golem parked on it), and it is where the cart was reported
## standing on the boundary.
##
## Matched case-insensitively against instance_name, which is not consistently
## cased across the pool (Forest, FungusArea1, pirates_cove), and against the
## biome file's own stem, so a rename of either one cannot quietly re-admit an
## arena.
const EXCLUDED_BIOMES: PackedStringArray = ["the_hollow", "hollow"]

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

## How far from the home spawn the cart may set up.
const MIN_RADIUS: float = 90.0
const MAX_RADIUS: float = 260.0
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


## A standable point in [param map] for [param cycle_index], plus the square
## beside it for the Vault Chest, as {"peddler": Vector2, "vault": Vector2} in
## GLOBAL coordinates.
##
## Falls back to the home spawn when nothing qualifies — a cart on the spawn pad
## is worse placement, not a broken window.
static func pick_spot(map: Map, cycle_index: int) -> Dictionary:
	var anchor: Vector2 = failsafe_anchor(map)
	# No FLOOR PAINT means no way to tell floor from void, and a walk with nothing
	# to stop it is how the cart ended up off the island. That covers a map with
	# no tile layers at all (deep_shoals is one ground Sprite2D) and, now, one
	# whose layers are all walls and props — either way there is nothing here to
	# vouch for a square, so it gets the anchor every cycle.
	if ground_layers(map).is_empty():
		return {"peddler": anchor, "vault": _vault_spot(map, {}, anchor)}
	var home: Vector2 = map.get_spawn_position(0)
	var walkable: Dictionary = walkable_cells(map, home)
	var spot: Vector2 = _choose(map, walkable, home, cycle_index, anchor)
	# Last gate before a cart exists in the world. _choose only offers cells that
	# already passed, so this catching anything means a rule above it stopped
	# agreeing with itself — cheap insurance on the one code path whose failures
	# are visible to every player in the biome.
	if spot != anchor and not is_valid_spot(map, spot):
		push_warning("PeddlerSites: rejected an invalid square at %s; using the anchor." % spot)
		spot = anchor
	return {"peddler": spot, "vault": _vault_spot(map, walkable, spot)}


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


## Everything a square must be before a cart may stand on it: painted floor, and
## nothing solid on it or within [constant CLEARANCE] of it. Public so a tool can
## ask the question in the same words the placement does.
static func is_valid_spot(map: Map, point: Vector2) -> bool:
	var space: PhysicsDirectSpaceState2D = _space(map)
	if space == null:
		return false
	return _has_paint(_tile_layers(map), point) and _is_standable(space, point)


## True when [param biome] is barred from the rotation — see
## [constant EXCLUDED_BIOMES]. Public so a tool auditing the biomes folder can
## tell "this map places the cart badly" from "the cart never goes here".
static func is_excluded(biome: StringName) -> bool:
	return EXCLUDED_BIOMES.has(String(biome).to_lower())


## Pick this cycle's square out of [param walkable]: far enough from the spawn to
## be somewhere to go, near enough to be found, with room around it.
static func _choose(
	map: Map, walkable: Dictionary, home: Vector2, cycle_index: int, anchor: Vector2
) -> Vector2:
	var space: PhysicsDirectSpaceState2D = _space(map)
	if space == null:
		return anchor
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
		return anchor
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
