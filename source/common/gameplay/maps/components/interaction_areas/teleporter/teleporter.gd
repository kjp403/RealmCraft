@tool
@icon("res://assets/node_icons/blue/icon_flag.png")
extends InteractionArea
class_name Teleporter
## Used to teleport from a point A to a point B inside the same instance.
## To change instance, use a Warper instead.
##
## Arrival rules (why this class is more than a pair of NodePaths): movement is
## CLIENT-authoritative, so after the server jumps a player the server's copy of
## that body keeps receiving input packets that were sent BEFORE the client knew
## about the jump — for a full round trip the body is dragged back and forth
## between the two pads, firing `body_entered` on both. Landing the traveller
## dead-centre on the destination pad (what this used to do) parks them inside the
## very trigger they are about to re-enter, so the next entry event throws them
## straight back where they came from — and then back again. That is the "walk
## into the next dungeon room, get shoved into the room you just left" ping-pong.
## Two things kill it:
##   1. [method arrival_point_from] lands the traveller PAST the destination pad,
##      clear of its own shape, so normal play never re-touches it on arrival.
##   2. [method accepts] ignores a peer that arrived here within
##      [constant ARRIVAL_LOCK_MS], which covers the stale-packet window on any
##      realistic connection.

## How long a pad ignores a peer that just ARRIVED on it. Must comfortably exceed
## a round trip (the client only learns about the jump after one, and holds its own
## 500 ms movement freeze on top), or the flapping window outlives the lock and the
## bounce-back returns.
const ARRIVAL_LOCK_MS: int = 1500
## Teleport lock stamped on the traveller themselves, so the pad they LEFT can't
## re-fire while stale packets are still dragging their body across it. Longer than
## Player.mark_just_teleported's 500 ms default for the same reason.
const JUMP_LOCK_MS: int = 1200
## Lattice step for the landing search. Fine enough to set the traveller down close
## to the gate, coarse enough that the ring search stays a handful of shape queries.
const ARRIVAL_SEARCH_STEP_PX: float = 4.0
## How far PAST the pad's own footprint the search may wander before giving up. The
## woodland boat pads need most of this: a 64x64 trigger sitting in a 72x56 cutout of
## the water collider, where the only standing room is diagonally onto the pier.
const ARRIVAL_SEARCH_SPAN_PX: float = 64.0
## Elbow room we TRY to leave between the pad's edge and the traveller's body, so a
## normal corridor gate sets them down well clear rather than a pixel past it. A pad
## with no room for it falls back to bare clearance, never to the pad centre.
const ARRIVAL_COMFORT_PX: float = 8.0
## Fallback half-size for a pad whose shape we cannot measure.
const DEFAULT_HALF_EXTENT_PX: float = 8.0
## Body box used to prove the computed landing spot is not inside geometry.
## Matches character.tscn's CollisionShape2D.
const BODY_PROBE_SIZE: Vector2 = Vector2(12.0, 8.0)
const BODY_PROBE_OFFSET: Vector2 = Vector2(0.0, -3.0)

@export var one_way: bool = false
## Fallback wiring for a pad whose partner lives OUTSIDE its own scene. Godot resolves
## an exported node REFERENCE (`target`) against the sub-scene's own root when that
## sub-scene is instanced, so a path climbing past that root — the woodland boat pads
## point at `../../WoodlandDeepCove/BoatToBeach`, and beach + deep cove are separate
## sub-scenes instanced side by side under woodland_tiles — silently lands on null and
## the pad does nothing at all. This is a plain NodePath, so it survives instancing
## untouched and we resolve it ourselves in _ready, by which point the whole map is in
## the tree and the partner genuinely exists. Leave it empty for a normal same-scene
## pair; `target` remains the authoritative link once resolved.
@export var target_path: NodePath
@export var target: Teleporter:
	set(value):
		# Needs rework.
		if value == target:
			return
		if value == null:
			if target:
				if not one_way:
					value = target
					target = null
					value.target = null
				target = null
		else:
			if value == self:
				value = null
				if target:
					if not one_way:
						target.target = null
					target = null
				push_warning("Impossible to assign a teleporter to itself.")
			target = value
			if target:
				if not one_way:
					target.target = self
		queue_redraw()
		update_configuration_warnings()

## peer_id -> Time.get_ticks_msec() when they landed on this pad. See the class
## comment: an arrival must not be able to fire the pad it arrived on.
var _arrived_ms: Dictionary[int, int] = {}


func _ready() -> void:
	_resolve_target_path()
	if Engine.is_editor_hint():
		return
	# Clear the arrival lock once the traveller has genuinely walked off — but only
	# after it has expired, because the stale-packet flapping itself produces exits.
	body_exited.connect(_on_body_exited)


## Late-bind a cross-scene partner (see [member target_path]). Only ever FILLS a null
## target — an authored same-scene link always wins. Assigning through the setter also
## wires the partner back to us when this pad is not one_way, so a two-way pair only
## needs one end to resolve.
func _resolve_target_path() -> void:
	if target != null or target_path.is_empty():
		return
	var partner := get_node_or_null(target_path) as Teleporter
	if partner == null:
		push_warning("Teleporter '%s': target_path '%s' resolved to no Teleporter." % [
			name, target_path
		])
		return
	target = partner


func _on_body_exited(body: Node2D) -> void:
	if body is not Player:
		return
	var peer_id: int = body.name.to_int()
	var landed_ms: int = _arrived_ms.get(peer_id, 0)
	if landed_ms == 0 or Time.get_ticks_msec() >= landed_ms + ARRIVAL_LOCK_MS:
		_arrived_ms.erase(peer_id)


## True when this pad should actually fire for [param player]. False while they are
## still inside the arrival lock from landing here.
func accepts(player: Player) -> bool:
	if target == null:
		return false
	var peer_id: int = player.name.to_int()
	var landed_ms: int = _arrived_ms.get(peer_id, 0)
	if landed_ms == 0:
		return true
	if Time.get_ticks_msec() < landed_ms + ARRIVAL_LOCK_MS:
		return false
	# Expired. A traveller now lands CLEAR of this pad, so body_exited may never
	# fire for that arrival — prune here or the stamp outlives the player.
	_arrived_ms.erase(peer_id)
	return true


## Stamp [param player] as having just landed here, so this pad ignores them until
## the round-trip window has passed.
func mark_arrival(player: Player) -> void:
	_arrived_ms[player.name.to_int()] = Time.get_ticks_msec()


## Where a traveller coming from [param from] actually lands: the nearest spot that
## clears this pad's own shape AND fits a character body. Nearest-first ring search
## on a small lattice, mirroring ClickNavigation._nearest_walkable, with ties broken
## toward "straight on through the gate" so a corridor pair still reads as a straight
## walk. A ring search rather than four axis rays because a pad can be wedged into a
## cutout where the only standing room is diagonal — the woodland boat pads are a
## 64x64 trigger inside a 72x56 hole in the water collider, reachable only by
## stepping up onto the pier.
##
## Falls back to this pad's centre if nothing within the search span fits. That is a
## bounce-prone landing, but the arrival lock still stops the ping-pong, and setting
## someone down inside a wall would be worse.
func arrival_point_from(from: Teleporter) -> Vector2:
	var onward: Vector2 = _onward_direction(from)
	var reach: float = _max_half_extent() + BODY_PROBE_SIZE.length() + ARRIVAL_SEARCH_SPAN_PX
	var rings: int = int(ceilf(reach / ARRIVAL_SEARCH_STEP_PX))
	# Comfortable elbow room first, bare clearance second. Only a pad with genuinely no
	# room for the margin takes the second pass, so the common corridor gate still sets
	# the traveller down well clear of the trigger.
	for margin: float in [ARRIVAL_COMFORT_PX, 0.0]:
		var landing: Vector2 = _search_landing(rings, onward, margin)
		if landing != Vector2.INF:
			return landing
	return global_position


## Nearest lattice point that clears this pad by [param margin] and fits a body, or
## Vector2.INF when the whole search span is blocked.
func _search_landing(rings: int, onward: Vector2, margin: float) -> Vector2:
	var here: Vector2 = global_position
	for ring: int in range(1, rings + 1):
		for offset: Vector2 in _ring_offsets(ring, onward):
			var candidate: Vector2 = here + offset
			if clears_pad(candidate, margin) and _fits_at(candidate):
				return candidate
	return Vector2.INF


## The perimeter of lattice ring [param ring], ordered nearest-first and, among
## equals, most aligned with [param onward] first.
func _ring_offsets(ring: int, onward: Vector2) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	for gy: int in range(-ring, ring + 1):
		for gx: int in range(-ring, ring + 1):
			if absi(gx) != ring and absi(gy) != ring:
				continue # interior — already covered by a smaller ring
			offsets.append(Vector2(gx, gy) * ARRIVAL_SEARCH_STEP_PX)
	offsets.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var da: float = a.length() - a.normalized().dot(onward) * ARRIVAL_SEARCH_STEP_PX
		var db: float = b.length() - b.normalized().dot(onward) * ARRIVAL_SEARCH_STEP_PX
		return da < db)
	return offsets


## The axis this pair points along, or ZERO when there is no sensible one (no source,
## or the two pads are stacked). Pads are authored as corridor gates, so "onward" is
## the dominant axis of the jump, not the raw diagonal between the two centres.
func _onward_direction(from: Teleporter) -> Vector2:
	if from == null:
		return Vector2.ZERO
	var travel: Vector2 = global_position - from.global_position
	if travel.is_zero_approx():
		return Vector2.ZERO
	if absf(travel.x) >= absf(travel.y):
		return Vector2(signf(travel.x), 0.0)
	return Vector2(0.0, signf(travel.y))


## True when a character body standing at [param point] does NOT overlap this pad's
## own trigger shape — i.e. arriving there cannot re-fire it. Public so the landing
## audit checks the same rule the runtime applies.
func clears_pad(point: Vector2, margin: float = 0.0) -> bool:
	var body_half: Vector2 = BODY_PROBE_SIZE * 0.5
	var body_rect := Rect2(
		point + BODY_PROBE_OFFSET - body_half, BODY_PROBE_SIZE
	).grow(margin)
	for child: Node in get_children():
		var collider := child as CollisionShape2D
		if collider == null or collider.shape == null or collider.disabled:
			continue
		var half: Vector2 = _aabb_half(collider)
		if Rect2(collider.global_position - half, half * 2.0).intersects(body_rect):
			return false
	return true


## Largest half-extent of this pad's shapes on either axis, in global px.
func _max_half_extent() -> float:
	var best: float = DEFAULT_HALF_EXTENT_PX
	for child: Node in get_children():
		var collider := child as CollisionShape2D
		if collider == null or collider.shape == null or collider.disabled:
			continue
		var half: Vector2 = _aabb_half(collider)
		var reach: Vector2 = (collider.global_position - global_position).abs() + half
		best = maxf(best, maxf(reach.x, reach.y))
	return best


## Axis-aligned half-size of [param collider]'s shape in GLOBAL space, including the
## node's scale and rotation (pads are authored as a 16x16 box stretched with `scale`).
func _aabb_half(collider: CollisionShape2D) -> Vector2:
	var half: Vector2 = _shape_half_extents(collider.shape)
	var basis: Transform2D = collider.global_transform
	return Vector2(
		absf(basis.x.x) * half.x + absf(basis.y.x) * half.y,
		absf(basis.x.y) * half.x + absf(basis.y.y) * half.y
	)


static func _shape_half_extents(shape: Shape2D) -> Vector2:
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size * 0.5
	if shape is CircleShape2D:
		var radius: float = (shape as CircleShape2D).radius
		return Vector2(radius, radius)
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		return Vector2(capsule.radius, capsule.height * 0.5)
	return Vector2(DEFAULT_HALF_EXTENT_PX, DEFAULT_HALF_EXTENT_PX)


## True when a character body fits at [param point] — walls AND scenery, the same
## mask the body itself collides with.
func _fits_at(point: Vector2) -> bool:
	if not is_inside_tree():
		return true
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	if space == null:
		return true
	var box := RectangleShape2D.new()
	box.size = BODY_PROBE_SIZE
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = box
	query.collision_mask = PhysicsLayers.SOLID_GROUND_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.transform = Transform2D(0.0, point + BODY_PROBE_OFFSET)
	return space.intersect_shape(query, 1).is_empty()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		if target:
			target.queue_redraw()
		queue_redraw()


func _get_configuration_warnings() -> PackedStringArray:
	if target == null:
		return PackedStringArray([
			"This teleporter has no target!",
			"Consider adding one in the inspector tab."
		])
	return []


func _draw() -> void:
	if Engine.is_editor_hint():
		if target:
			draw_line(Vector2.ZERO, to_local(target.global_position), Color.RED, 1, true)
