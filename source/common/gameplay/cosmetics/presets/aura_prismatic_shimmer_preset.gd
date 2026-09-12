extends ThemeAuraPreset
## PRISMATIC SHIMMER. The matching aura for the Iridescent Aspect title, and the
## set-piece of the set: a ring that carries EVERY DYE THE VAULT SELLS at once.
##
## THE COLOURS ARE NOT A HUE SWEEP. They are [member CosmeticThemes.PRISM_CYCLE] -
## the actual dyes, interpolated - so the rainbow here is made of the same eight
## colours a player can wear on their body, and a Rose-dyed character standing in
## this ring can find their own colour going round it. A generated hue wheel would
## have been one line shorter and would have meant nothing.
##
##   ARC     the ring itself, drawn as coloured segments rather than one arc,
##           because one draw_arc call can only be one colour.
##   FACETS  six shards standing around the rim, each holding one dye and
##           throwing it as a glint.
##   MOTES   sparks in mixed colours, each born with the dye of the point it left.

## Segments in the coloured ring. High enough that adjacent segments overlap into
## a continuous band rather than reading as a dashed line.
const ARC_SEGMENTS: int = 48
const FACET_COUNT: int = 6
## Seconds for the spectrum to travel once round the ring.
const SPECTRUM_PERIOD_S: float = 6.5
## One emitter per dye would be eight emitters. This is the compromise: four
## emitters, each fixed to one dye, spaced evenly round the cycle - so the air
## carries four colours at any moment and the ring carries all eight.
const MOTE_EMITTERS: int = 4


func theme() -> StringName:
	return CosmeticThemes.PRISM


func _build() -> void:
	# Every layer here is light.
	material = _additive()
	for i: int in MOTE_EMITTERS:
		_build_motes(i)


func _build_motes(index: int) -> void:
	var k: float = float(index) / float(MOTE_EMITTERS)
	var tint: Color = CosmeticThemes.prism_at(k)
	var p: CPUParticles2D = _add_emitter(6, 2.0, VfxTextures.sparkle(7))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	# Each emitter takes a QUARTER of the ring, so a colour rises from the part of
	# the circle showing that colour instead of all four mixing at every point.
	p.emission_points = _arc_points(4, BASE_RADIUS * 0.92, k * TAU, (k + 0.25) * TAU)
	p.direction = Vector2(0, -1)
	p.spread = 30.0
	p.gravity = Vector2(0, -14.0)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 22.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	p.color_ramp = _swell_ramp(tint, Color(tint.lightened(0.4), 0.95), 0.2)
	p.material = _additive()


func _draw() -> void:
	_use_ground_plane()
	# The shared ring at low weight, under the spectrum band: it is what ties this
	# aura to the other seven, and at full weight its single colour would fight
	# the thing that makes this one different.
	draw_theme_ring(0.35)
	_draw_spectrum()
	_draw_facets()


## The ring, one short arc per segment. draw_arc takes ONE colour, so a band that
## changes colour along its length has to be drawn in pieces - the same technique
## the strip generator uses for its rainbow rings.
func _draw_spectrum() -> void:
	var travel: float = _elapsed / SPECTRUM_PERIOD_S
	var step: float = TAU / float(ARC_SEGMENTS)
	for i: int in ARC_SEGMENTS:
		var k: float = float(i) / float(ARC_SEGMENTS)
		var from: float = k * TAU
		var tint: Color = CosmeticThemes.prism_at(k + travel)
		# Segments overlap by half a step so the band has no gaps at this radius.
		draw_arc(
			Vector2.ZERO, BASE_RADIUS, from, from + step * 1.5, 3,
			Color(tint, 0.55), 2.0, false
		)


## Shards standing on the rim, each holding one dye. Upright, because a facet is a
## thing catching light rather than a mark on the floor.
func _draw_facets() -> void:
	_use_upright_plane()
	var travel: float = _elapsed / SPECTRUM_PERIOD_S
	for i: int in FACET_COUNT:
		var k: float = float(i) / float(FACET_COUNT)
		var angle: float = k * TAU + ring_spin() * 0.4
		var foot: Vector2 = _ground_point(angle, BASE_RADIUS * 0.9)
		var tint: Color = CosmeticThemes.prism_at(k + travel)
		var near: float = 0.4 + 0.6 * (0.5 + 0.5 * sin(angle))
		var tip: Vector2 = foot + Vector2(cos(angle) * 1.5, -9.0)
		draw_colored_polygon(
			PackedVector2Array([foot + Vector2(-1.8, 0.0), foot + Vector2(1.8, 0.0), tip]),
			Color(tint, 0.6 * near)
		)
		# The glint: a short horizontal streak through the tip, firing on its own
		# cycle. Horizontal rather than a cross, because a wide streak reads as
		# light through a lens and an even cross reads as a star sprite.
		var flash: float = pow(1.0 - clampf(fposmod(_elapsed * 0.7 + k, 1.0) / 0.15, 0.0, 1.0), 2.0)
		if flash > 0.02:
			draw_line(tip - Vector2(6.0, 0.0), tip + Vector2(6.0, 0.0), Color(tint, 0.7 * flash), 1.0)
			draw_circle(tip, 1.6, Color(tint.lightened(0.6), 0.9 * flash))
