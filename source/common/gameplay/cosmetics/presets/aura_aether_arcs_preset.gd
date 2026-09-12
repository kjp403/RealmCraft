extends ThemeAuraPreset
## AETHER ARCS. The matching aura for the Aether Storm title: a charged ring that
## throws lightning up around the wearer.
##
## AN ARC IS A DRAWN POLYLINE, not particles, and that is the whole design
## decision here. A particle system can only place sprites, so a "bolt" made of
## them is a row of dots travelling in a line - which reads as a spray, never as
## a discharge. A jagged polyline drawn in one frame reads as lightning
## immediately, and the cost is one _draw pass the preset was already paying.
##
##   RING    the shared theme circle.
##   ARCS    three bolts, each firing on its own long cycle, each re-jagged from
##           a seed that changes per strike so no two are the same shape.
##   SPARKS  charge motes hopping off the ring between strikes.

const ARC_COUNT: int = 3
## Seconds between one arc's strikes. Long and offset, so the aura crackles
## irregularly rather than blinking on a beat.
const STRIKE_PERIOD_S: float = 1.9
## How much of that cycle the bolt is visible for. Very short: lightning that
## lingers is a laser.
const STRIKE_VISIBLE: float = 0.16
const ARC_SEGMENTS: int = 7
const ARC_HEIGHT: float = 30.0


func theme() -> StringName:
	return CosmeticThemes.STORM


func _build() -> void:
	var p: CPUParticles2D = _add_emitter(14, 0.9, VfxTextures.pip(4))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(12, BASE_RADIUS * 0.95)
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.gravity = Vector2(0, -30.0)
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 40.0
	p.damping_min = 10.0
	p.damping_max = 24.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.7
	p.color_ramp = _fade_ramp(accent(), 0.9)
	p.material = _additive()


func _draw() -> void:
	_use_ground_plane()
	draw_theme_ring()
	_draw_arcs()


## Three bolts standing up from the ring. Each is drawn twice - a wide dim core in
## the dye, then a one-pixel white-hot line down the middle - which is how a
## flat-shaded bolt gets a glow without a blur pass.
func _draw_arcs() -> void:
	_use_upright_plane()
	for i: int in ARC_COUNT:
		var phase: float = fposmod(_elapsed / STRIKE_PERIOD_S + float(i) * 0.41, 1.0)
		if phase > STRIKE_VISIBLE:
			continue
		# Bright at the instant of the strike, gone a few frames later.
		var flash: float = pow(1.0 - phase / STRIKE_VISIBLE, 1.6)
		# One integer per strike: the jag is re-rolled when this changes and is
		# frozen for the few frames the bolt is up, so it does not writhe.
		var strike: float = floor(_elapsed / STRIKE_PERIOD_S + float(i) * 0.41)
		var angle: float = float(i) * TAU / float(ARC_COUNT) + strike * 1.7
		var foot: Vector2 = _ground_point(angle, BASE_RADIUS * 0.9)
		var points: PackedVector2Array = PackedVector2Array()
		for s: int in ARC_SEGMENTS + 1:
			var k: float = float(s) / float(ARC_SEGMENTS)
			# A deterministic hash of (segment, strike): no RNG, so the same frame
			# drawn twice is the same bolt, and a render tool captures what plays.
			var jag: float = sin(float(s) * 12.9898 + strike * 78.233) * 4.5 * (1.0 - k * 0.4)
			points.append(foot + Vector2(jag + cos(angle) * k * 3.0, -ARC_HEIGHT * k))
		draw_polyline(points, Color(core(), 0.55 * flash), 3.0)
		draw_polyline(points, Color(pale(), 0.95 * flash), 1.0)
		# The flash at the foot, where it leaves the ring.
		draw_circle(foot, 3.0, Color(accent(), 0.5 * flash))
