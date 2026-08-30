extends CosmeticPreset
## VERDANT AURA. A floral magic circle that sprouts on the ground, vine tendrils
## climbing up around the wearer, and leaves and pollen drifting off them.
##
## This one is drawn rather than shaded, and that is a deliberate split from Toxic
## and Blood. Those two are LIQUIDS - continuous surfaces, which is exactly what a
## fragment shader is good at. Growth is not continuous: it is a countable number
## of discrete things (six flowers, five vines, a leaf on a stem) each on its own
## little life cycle. Chasing that in a shader means faking countable objects out
## of noise; in _draw() it is just a loop, and every flower can be a crisp handful
## of pixels instead of a soft blob.
##
##   CIRCLE  two counter-rotating rune rings on the floor.
##   FLOWERS six blooms around the circle, each sprouting, opening, and fading on
##           its own offset cycle, so the ring is never all in the same state.
##   VINES   five tendrils growing UP around the body, swaying wider as they climb.
##   AIR     glowing leaves shed from the vines, plus a fine pollen haze.

const RING_TINT: Color = Color(0.42, 0.88, 0.40)
const DEEP_TINT: Color = Color(0.16, 0.52, 0.24)
const BLOOM_TINT: Color = Color(0.95, 0.98, 0.62)
const PETAL_TINT: Color = Color(0.72, 1.0, 0.55)
const LEAF_TINT: Color = Color(0.55, 0.95, 0.45)
const POLLEN_TINT: Color = Color(0.95, 1.0, 0.60)

const FLOWER_COUNT: int = 6
const VINE_COUNT: int = 5
## Seconds for one full sprout-bloom-wither cycle. Long: this is worn for hours,
## and anything twitchy at the wearer's feet becomes maddening in an inventory
## screen. The offsets below are what keep it visibly alive at this speed.
const CYCLE_S: float = 4.2
## How tall the tendrils reach, in px. Chest height on a 64 px body - tall enough
## to frame the wearer, short enough not to cover their head or their name plate.
const VINE_HEIGHT: float = 30.0


func _build() -> void:
	_build_leaves()
	_build_pollen()


## Leaves shed off the vines: they drift up and sideways, tumbling as they go.
func _build_leaves() -> void:
	var p: CPUParticles2D = _add_emitter(9, 2.4, VfxTextures.leaf(9))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	# Shed from mid-vine height, not from the floor, so they read as coming OFF
	# the tendrils rather than sprouting out of the tiles.
	p.emission_points = _arc_points(VINE_COUNT, BASE_RADIUS * 0.8, 0.0, TAU)
	p.position = Vector2(0.0, -VINE_HEIGHT * 0.55)
	p.direction = Vector2(0, -1)
	p.spread = 55.0
	p.gravity = Vector2(0, -14.0)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 20.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	# Tumbling is what makes a leaf a leaf and not a green pip.
	p.angular_velocity_min = -110.0
	p.angular_velocity_max = 110.0
	p.color_ramp = _swell_ramp(LEAF_TINT, Color(LEAF_TINT, 0.85), 0.18)


## Fine pollen: many, tiny, dim, slow. It is the layer nobody notices and the one
## that makes the space between the vines feel occupied.
func _build_pollen() -> void:
	var p: CPUParticles2D = _add_emitter(16, 3.2, VfxTextures.dot(6))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(14, BASE_RADIUS * 0.95)
	p.direction = Vector2(0, -1)
	p.spread = 40.0
	p.gravity = Vector2(0, -6.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 10.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	p.color_ramp = _swell_ramp(POLLEN_TINT, Color(POLLEN_TINT, 0.55), 0.3)
	p.material = _additive() # motes of light, not specks of paint


func _draw() -> void:
	_draw_circle_runes()
	_draw_flowers()
	_draw_vines()


## Two counter-rotating rings. Counter-rotation, rather than one ring, is what
## makes it read as a worked magic circle instead of a spinning hoop.
func _draw_circle_runes() -> void:
	_use_ground_plane()
	var spin: float = _elapsed * 0.45
	draw_arc(Vector2.ZERO, BASE_RADIUS, spin, spin + TAU, 40, Color(RING_TINT, 0.45), 1.0, false)
	draw_arc(
		Vector2.ZERO, BASE_RADIUS * 0.62, -spin * 1.4, -spin * 1.4 + TAU * 0.78,
		30, Color(DEEP_TINT, 0.6), 1.0, false
	)
	# Tick marks on the outer ring, turning with it - the detail that reads as
	# "inscribed" at a glance without needing legible glyphs at this size.
	for i: int in 12:
		var angle: float = spin + float(i) * TAU / 12.0
		var inner: Vector2 = _ground_point(angle, BASE_RADIUS * 0.90)
		var outer: Vector2 = _ground_point(angle, BASE_RADIUS * 1.04)
		draw_line(inner, outer, Color(RING_TINT, 0.35), 1.0)


## Blooms around the circle. Each runs the same sprout curve on its own offset, so
## at any instant some are buds, some are open, and some are already fading.
func _draw_flowers() -> void:
	_use_ground_plane()
	for i: int in FLOWER_COUNT:
		var offset: float = float(i) / float(FLOWER_COUNT)
		var phase: float = fposmod(_elapsed / CYCLE_S + offset, 1.0)
		# Sprout fast, hold open, wither slowly - a symmetric curve makes the
		# whole ring look like it is breathing in unison.
		var open: float = smoothstep(0.0, 0.22, phase) * (1.0 - smoothstep(0.55, 1.0, phase))
		if open <= 0.02:
			continue
		# Each bloom sits at a fixed angle and drifts a little with the ring.
		var angle: float = offset * TAU + _elapsed * 0.45
		var at: Vector2 = _ground_point(angle, BASE_RADIUS * 0.88)
		var petal: float = 1.6 + open * 1.4
		for k: int in 5:
			var petal_angle: float = float(k) * TAU / 5.0 + phase * 1.2
			var tip: Vector2 = at + Vector2(cos(petal_angle), sin(petal_angle)) * (petal * 1.5)
			draw_rect(
				Rect2(tip - Vector2(petal, petal) * 0.5, Vector2(petal, petal)),
				Color(PETAL_TINT, 0.85 * open)
			)
		draw_rect(
			Rect2(at - Vector2(1.0, 1.0), Vector2(2.0, 2.0)),
			Color(BLOOM_TINT, 0.95 * open)
		)


## Tendrils climbing around the body. Upright plane - a vine squashed onto the
## ground plane looks like it is lying down, which is the whole failure mode.
func _draw_vines() -> void:
	_use_upright_plane()
	for i: int in VINE_COUNT:
		var offset: float = float(i) / float(VINE_COUNT)
		var phase: float = fposmod(_elapsed / CYCLE_S + offset * 0.77, 1.0)
		var grow: float = smoothstep(0.0, 0.35, phase) * (1.0 - smoothstep(0.7, 1.0, phase))
		if grow <= 0.02:
			continue
		var base_angle: float = offset * TAU + _elapsed * 0.25
		var base: Vector2 = _ground_point(base_angle, BASE_RADIUS * 0.75)
		var points: PackedVector2Array = PackedVector2Array()
		const SEGMENTS: int = 9
		for s: int in SEGMENTS + 1:
			var k: float = float(s) / float(SEGMENTS)
			var height: float = k * VINE_HEIGHT * grow
			# Sway widens with height and turns with the base angle, so the
			# tendril spirals around the wearer instead of standing flat.
			var sway: float = sin(k * 3.4 + _elapsed * 1.6 + offset * 6.0) * (1.0 + k * 4.5)
			points.append(base + Vector2(sway, -height))
		var alpha: float = 0.85 * grow
		# Taper by stacking: the full line thin, its lower half thicker. Cheaper
		# and crisper than a width curve at this size.
		draw_polyline(points, Color(DEEP_TINT, alpha), 1.0)
		draw_polyline(points.slice(0, 5), Color(DEEP_TINT, alpha), 2.0)
		# Leaves on the stem, alternating sides.
		for s: int in range(2, SEGMENTS, 2):
			var at: Vector2 = points[s]
			var side: float = 1.0 if s % 4 == 0 else -1.0
			var leaf: Vector2 = at + Vector2(side * 3.0, -1.0)
			draw_rect(
				Rect2(leaf - Vector2(1.5, 1.0), Vector2(3.0, 2.0)),
				Color(LEAF_TINT, alpha)
			)
