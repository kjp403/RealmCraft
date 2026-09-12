extends ThemeAuraPreset
## LOTUS PETALS. The matching aura for the Lotus Weaver title: blossom falling
## around the wearer over a soft pink circle, with a lotus opening on the floor.
##
## The second of the two QUIET auras - see [AuraVerdantBloomPreset] - and priced
## with it. Nothing here flashes; the only event is one flower opening and closing
## over four seconds, which is slow enough to be restful in an inventory screen
## and the reason this reads as "serene" rather than "pink particles".
##
##   RING    the shared theme circle at half weight.
##   LOTUS   one bloom in the middle of the ring, opening and closing.
##   PETALS  blossom falling from above the head, tumbling as it goes.
##   DRIFT   a fine warm haze between them.

const PETAL_RING: int = 8
## Seconds for the bloom to open and close once.
const BLOOM_PERIOD_S: float = 4.4


func theme() -> StringName:
	return CosmeticThemes.LOTUS


func _build() -> void:
	_build_petals()
	_build_drift()


## Falling blossom. Emitted above the head so it falls PAST the wearer; a petal
## layer emitted at the feet has nowhere to go and reads as rising confetti.
func _build_petals() -> void:
	var p: CPUParticles2D = _add_emitter(12, 3.2, VfxTextures.leaf(8))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(BASE_RADIUS * 1.15, 2.0)
	p.position = Vector2(0.0, HEAD_Y - 10.0)
	p.direction = Vector2(0.3, 1.0)
	p.spread = 22.0
	# Sideways drift accumulates through gravity rather than being fired once, so
	# a petal curves across as it falls instead of travelling in a straight line.
	p.gravity = Vector2(5.0, 11.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 8.0
	p.damping_min = 2.0
	p.damping_max = 5.0
	p.angular_velocity_min = -90.0
	p.angular_velocity_max = 90.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.color_ramp = _swell_ramp(core(), Color(core(), 0.95), 0.12)
	# Matte: a petal that glows is a spark.


func _build_drift() -> void:
	var p: CPUParticles2D = _add_emitter(10, 2.8, VfxTextures.dot(6))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(10, BASE_RADIUS * 0.8)
	p.direction = Vector2(0, -1)
	p.spread = 40.0
	p.gravity = Vector2(0, -7.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 9.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	p.color_ramp = _swell_ramp(pale(), Color(pale(), 0.45), 0.3)
	p.material = _additive()


func _draw() -> void:
	_use_ground_plane()
	draw_theme_ring(0.5)
	_draw_lotus()


## The bloom at the wearer's feet: one ring of petals opening outward, a paler
## inner ring opening behind it, and a bright centre.
##
## Drawn on the GROUND plane so it lies flat like a lily on water. This is the one
## place in the set where the squash is the point rather than a compromise.
func _draw_lotus() -> void:
	var phase: float = fposmod(_elapsed / BLOOM_PERIOD_S, 1.0)
	# Open slowly, hold, close slowly. Symmetric here, unlike the ember coals -
	# a flower that snaps shut is a trap, not a lotus.
	var open: float = smoothstep(0.0, 0.35, phase) * (1.0 - smoothstep(0.6, 1.0, phase))
	if open <= 0.02:
		return
	var reach: float = BASE_RADIUS * (0.18 + 0.30 * open)
	for i: int in PETAL_RING:
		var angle: float = float(i) * TAU / float(PETAL_RING) + _elapsed * 0.12
		var tip: Vector2 = _ground_point(angle, reach)
		var half: Vector2 = _ground_point(angle + PI * 0.5, 2.2 + open * 1.2)
		draw_colored_polygon(
			PackedVector2Array([half, tip, -half]),
			Color(core(), 0.45 * open)
		)
	for i: int in PETAL_RING:
		# The inner ring is offset half a petal, so the two interleave the way a
		# real bloom's do rather than stacking.
		var angle: float = (float(i) + 0.5) * TAU / float(PETAL_RING) - _elapsed * 0.09
		var tip: Vector2 = _ground_point(angle, reach * 0.62)
		var half: Vector2 = _ground_point(angle + PI * 0.5, 1.6 + open)
		draw_colored_polygon(
			PackedVector2Array([half, tip, -half]),
			Color(pale(), 0.5 * open)
		)
	draw_circle(Vector2.ZERO, 1.8 + open, Color(accent(), 0.75 * open))
