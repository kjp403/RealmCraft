extends CosmeticTrailPreset
## STORM TRAIL (rework). Electric arcs snapping along the wearer's path, redrawn
## from scratch many times a second, with scorch marks burned into the tiles at
## every step.
##
## This is the one preset that WANTS to boil. Every other trail here pins its
## randomness to world positions so the shape stays put while the wearer runs on -
## see [TrailBloodPreset], where a re-roll per frame would read as a rendering
## fault. Lightning is the exception: an arc that holds its shape for even a
## quarter second reads as a bent wire. So the offsets here are re-rolled on a
## fixed, deliberately fast cadence and nothing is carried between them.
##
## Re-rolling on a TIMER rather than every frame is what keeps that read honest.
## Per-frame jitter is tied to the frame rate, so the same arc would look calmer
## at 30 fps than at 144; a fixed cadence looks identical on both, and the small
## hold between recalculations is what lets the eye register each arc as a shape
## before it is replaced.
##
##   ARCS    one jagged path drawn three times - a thin white core inside a
##           wider, dimmer blue corona (see _recalculate_arcs).
##   SPARKS  a fine world-space spray, so the path is lit as well as drawn.
##   SCORCH  small burn decals with embers still cooling in them, at step spacing.

const ARC_COUNT: int = 3
## Points per arc. Few and far apart: lightning is made of long straights meeting
## at hard angles, and a dense polyline just curves.
const ARC_SEGMENTS: int = 7
## Seconds between re-rolls. Roughly 22 Hz - fast enough to read as unstable,
## slow enough that each shape is on screen long enough to be seen.
const RECALC_S: float = 0.045
## Peak sideways displacement of the bolt, in px.
const JITTER_PX: float = 11.0

const ARC_CORE: Color = Color(0.88, 0.95, 1.0)
const ARC_MID: Color = Color(0.45, 0.72, 1.0)
const ARC_DEEP: Color = Color(0.18, 0.30, 0.85)
const SCORCH_TINT: Color = Color(0.42, 0.55, 0.95)

const SCORCH_LIFE_S: float = 1.5
const SCORCH_SIZE: float = 14.0

var _arcs: Array[Line2D] = []
var _sparks: CPUParticles2D
var _since_recalc: float = 0.0


func _build() -> void:
	for i: int in ARC_COUNT:
		var k: float = float(i) / float(ARC_COUNT - 1)
		var ramp: Gradient = Gradient.new()
		ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		# The innermost arc is the hot white core; the outer ones are the dim blue
		# corona around it. Drawing all three the same colour makes a fat rope.
		var tint: Color = ARC_DEEP.lerp(ARC_CORE, 1.0 - k)
		ramp.colors = PackedColorArray([
			Color(tint, 0.0), Color(tint, 0.55), Color(tint, 0.9),
		])
		# Thin and bright at the core, wide and dim outside it.
		var line: Line2D = _add_ribbon(lerpf(1.0, 4.5, k), ramp, true)
		# Square joints and caps: lightning has corners, and round joints sand
		# every one of them off.
		line.joint_mode = Line2D.LINE_JOINT_SHARP
		line.begin_cap_mode = Line2D.LINE_CAP_NONE
		line.end_cap_mode = Line2D.LINE_CAP_NONE
		line.width_curve = null # no taper; a bolt does not thin out along its length
		_arcs.append(line)
	_build_sparks()


func _build_sparks() -> void:
	var p: CPUParticles2D = _add_world_emitter(12, 0.5, VfxTextures.dot(6))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 7.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 180.0)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 90.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.7
	p.color_ramp = _fade_ramp(ARC_CORE, 1.0)
	p.material = _additive()
	_sparks = p


func _tick(delta: float) -> void:
	super(delta)
	if _sparks != null:
		_sparks.emitting = is_moving()
	_since_recalc += delta
	if _since_recalc < RECALC_S:
		return
	_since_recalc = 0.0
	_recalculate_arcs()


## Throw the bolt away and build a new one. Nothing is interpolated from the last
## shape on purpose - a bolt that eases between shapes reads as a wobbling rope.
##
## All three arcs share ONE jagged path. Jagging each independently was the first
## attempt and it was wrong: three differently-bent lines overlap into a smooth
## band, and the corona ends up more jagged than the core it is supposed to be
## glowing around. One spine, three widths, is a bolt with a glow.
func _recalculate_arcs() -> void:
	var spine: PackedVector2Array = _resample(path_points(), ARC_SEGMENTS)
	if spine.size() < 2:
		for line: Line2D in _arcs:
			line.clear_points()
		return
	var bolt: PackedVector2Array = _jag(spine, JITTER_PX)
	for line: Line2D in _arcs:
		line.points = bolt


## Displace a spine sideways by a fresh random amount at every point. The ends are
## pinned: an arc has to start at the wearer's feet and end where the path ends,
## or it detaches and floats.
func _jag(spine: PackedVector2Array, amplitude: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	var last: int = spine.size() - 1
	for i: int in spine.size():
		var at: Vector2 = spine[i]
		if i == 0 or i == last:
			out.append(at)
			continue
		var along: Vector2 = spine[mini(i + 1, last)] - spine[maxi(i - 1, 0)]
		var side: Vector2 = Vector2(-along.y, along.x).normalized()
		out.append(at + side * randf_range(-amplitude, amplitude))
	return out


## Even-spaced points along a polyline. The sampled path is much denser than an
## arc wants (one point every few px), and jittering it at that spacing gives
## fuzz rather than jags.
func _resample(path: PackedVector2Array, count: int) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if path.size() < 2 or count < 2:
		return out
	var total: float = 0.0
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	if total <= 0.01:
		return out
	var step: float = total / float(count - 1)
	var walked: float = 0.0
	var segment: int = 1
	var consumed: float = 0.0
	out.append(path[0])
	for _n: int in count - 2:
		walked += step
		while segment < path.size() - 1 and consumed + path[segment - 1].distance_to(path[segment]) < walked:
			consumed += path[segment - 1].distance_to(path[segment])
			segment += 1
		var length: float = path[segment - 1].distance_to(path[segment])
		var into: float = 0.0 if length <= 0.0001 else clampf((walked - consumed) / length, 0.0, 1.0)
		out.append(path[segment - 1].lerp(path[segment], into))
	out.append(path[path.size() - 1])
	return out


func _on_step(world_pos: Vector2, _heading_dir: Vector2) -> void:
	_drop_decal(world_pos, GroundDecal.Variant.SCORCH, SCORCH_TINT, SCORCH_SIZE, SCORCH_LIFE_S)
