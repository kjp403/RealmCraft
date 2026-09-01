class_name CosmeticTrailPreset
extends CosmeticPreset
## Base for the scripted TRAIL presets: everything that has to know where the
## wearer has actually been.
##
## The strip trails could not do this. A trail sprite is authored "running right"
## and mirrored with the body, so it always streams straight out sideways — it
## points the wrong way the instant you walk up, down or diagonally, and it keeps
## streaming while you stand still. Here the path is SAMPLED from real motion, so
## the ribbon curves through corners, stops when you stop, and the floor marks
## stay on the tiles you stepped on instead of sliding along with you.
##
## Position is sampled from the node's own global_position rather than from
## [member Character.velocity] on purpose: remote players never run the movement
## code, their position arrives through [NetMotionSmoother], and velocity is left
## at zero. Sampling the transform is the only reading that works for BOTH the
## local player and everyone else on screen.

## Path samples closer together than this are dropped. Small enough to curve
## smoothly through a corner, large enough that a jittering idle adds no points.
const SAMPLE_DISTANCE: float = 4.0

## Distance between "steps" — the cadence floor marks and splatters are dropped
## at. Roughly one stride for a 64 px body, so marks land where feet land.
const STEP_DISTANCE: float = 20.0

## Seconds a path sample survives. This is what makes the ribbon a fixed LENGTH
## in time rather than in points: sprint and it stretches, dawdle and it shortens.
const PATH_LIFE: float = 0.55

## Below this many px/s the wearer counts as standing still and the trail stops
## feeding. Set above network jitter so a stationary remote player does not
## dribble a trail out of the smoother's micro-corrections.
const MOVING_SPEED: float = 12.0

## Recent world positions, oldest first: {"p": Vector2, "t": float(_elapsed)}.
var _path: Array[Dictionary] = []
## World distance travelled since the last step mark.
var _step_accum: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _has_last: bool = false
## Metres-per-second-ish, smoothed, so a single dropped network frame does not
## read as a dead stop.
var _speed: float = 0.0
## Unit heading, kept from the last real movement so a mark dropped on the frame
## the wearer stops still points the right way.
var _heading: Vector2 = Vector2.RIGHT


func _tick(delta: float) -> void:
	var now: Vector2 = global_position
	if not _has_last:
		_last_pos = now
		_has_last = true
		return
	var step: Vector2 = now - _last_pos
	var dist: float = step.length()
	# A teleport (warp, respawn, instance change) must not draw a ribbon across
	# the map, so drop the whole path rather than bridging to the new position.
	if dist > 200.0:
		_path.clear()
		_step_accum = 0.0
		_last_pos = now
		return
	var instant: float = dist / maxf(delta, 0.0001)
	_speed = lerpf(_speed, instant, 0.35)
	if dist > 0.01:
		_heading = step / dist
	_last_pos = now

	if is_moving() and (_path.is_empty() or now.distance_to(_path[-1]["p"]) >= SAMPLE_DISTANCE):
		_path.append({"p": now, "t": _elapsed})
	_expire_path()

	if is_moving():
		_step_accum += dist
		while _step_accum >= STEP_DISTANCE:
			_step_accum -= STEP_DISTANCE
			_on_step(now, _heading)


## Drop samples older than PATH_LIFE. Ages are compared against [member _elapsed],
## which is this preset's own clock, so it is unaffected by other wearers.
func _expire_path() -> void:
	var cutoff: float = _elapsed - PATH_LIFE
	var drop: int = 0
	while drop < _path.size() and float(_path[drop]["t"]) < cutoff:
		drop += 1
	if drop > 0:
		_path = _path.slice(drop)


## Override: called once per stride while moving, with the world position and the
## unit heading. Floor decals and splatters hang off this.
func _on_step(_world_pos: Vector2, _heading_dir: Vector2) -> void:
	pass


func is_moving() -> bool:
	return _speed >= MOVING_SPEED


## Path as world-space points, newest LAST. Empty while standing still long
## enough for the whole path to expire.
func path_points() -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for sample: Dictionary in _path:
		out.append(sample["p"])
	return out


## 0 at the oldest surviving sample, 1 at the newest — the fade weight a ribbon
## or a per-point colour needs.
func path_age(index: int) -> float:
	if _path.is_empty():
		return 0.0
	var age: float = _elapsed - float(_path[index]["t"])
	return clampf(1.0 - age / PATH_LIFE, 0.0, 1.0)


# --- Shared layers -----------------------------------------------------------

## A world-space ribbon. top_level so its points are world coordinates and the
## ribbon stays put while the wearer runs on.
##
## Depth is left INHERITED (z_as_relative, z_index 0). Pinning it to an absolute
## floor depth looks right in the world and breaks the wardrobe, where the same
## node is previewed inside a UI panel and an absolute -1 puts the ribbon behind
## the panel background. Inheriting means the mount point decides: -1 under a
## Character, 0 in the preview.
func _add_ribbon(width: float, gradient: Gradient, additive: bool = false) -> Line2D:
	var line: Line2D = Line2D.new()
	line.top_level = true
	line.width = width
	line.gradient = gradient
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = false # crisp, to match the pixel-art bodies
	# Taper to nothing at the tail so the ribbon dissolves instead of ending in a
	# blunt stub — the single biggest tell that a trail is a drawn object.
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.15))
	curve.add_point(Vector2(0.65, 0.85))
	curve.add_point(Vector2(1.0, 1.0))
	line.width_curve = curve
	if additive:
		line.material = _additive()
	add_child(line)
	return line


## A world-space emitter that leaves its particles BEHIND. local_coords = false is
## the whole point: with it on, every particle rides along with the wearer and the
## "trail" becomes a cloud stapled to their feet.
func _add_world_emitter(amount: int, lifetime: float, texture: Texture2D) -> CPUParticles2D:
	var p: CPUParticles2D = _add_emitter(amount, lifetime, texture)
	p.local_coords = false
	return p


## Drop a dissolving floor mark at a world position. See [GroundDecal].
func _drop_decal(world_pos: Vector2, variant: int, tint: Color, size: float, life: float) -> GroundDecal:
	var decal: GroundDecal = GroundDecal.new()
	decal.variant = variant
	decal.tint = tint
	decal.diameter = size
	decal.life = life
	decal.heading = _heading
	decal.top_level = true
	add_child(decal)
	# AFTER add_child: a top_level node's global_position is only meaningful once
	# it is in the tree, and setting it before would be silently discarded.
	decal.global_position = world_pos
	return decal
