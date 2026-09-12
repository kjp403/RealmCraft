extends ThemeAuraPreset
## ALCHEMICAL SUN. The matching aura for the Alchemical Exarch title: a gold
## transmutation circle with a standing sunburst turning over it.
##
## THE RAYS ARE DRAWN UNDER THE PRESET, on their own layer at a negative z, so
## they pass BEHIND the wearer's body while the circle stays on the floor. A fan
## of long triangles from one point is the only honest way to draw light from a
## source; a ring of sprites reads as a row of streaks. Same argument, same shape,
## as the ray fan on the Diamond title.
##
##   RING    the shared theme circle, full weight.
##   RAYS    twelve rays turning slowly, breathing in two overlapping cycles so
##           the fan never looks like a fixed star.
##   GLYPHS  four alchemical marks at the compass points, lighting in sequence.
##   FLARES  gold sparks lifting off the rim.

const RAY_COUNT: int = 12
## Seconds per turn of the fan. Deliberately out of step with the floor ring's
## period, so the two never line up and the aura keeps changing shape.
const RAY_PERIOD_S: float = 17.0
## Ray length in px. Short enough to stay a HALO BEHIND the torso rather than
## spokes crossing the whole cell - a fan that reaches past the body reads as a
## boss telegraph, which is a gameplay idiom and wrong on a cosmetic.
const RAY_REACH: float = 18.0
## Where the fan is anchored, in local space (origin is the feet).
##
## NOT [constant CosmeticPreset.CHEST_Y]. Those landmarks are for a 64px cell, and
## the figure drawn inside one only occupies its lower two thirds - anchoring at
## CHEST_Y put the origin level with the top of the helmet and the fan came out as
## antennae. Measured against the real stand-in body in the proof capture instead.
const FAN_Y: float = -18.0
const GLYPH_COUNT: int = 4
## Seconds for the four marks to light in sequence, one after another.
const GLYPH_CYCLE_S: float = 3.6


func theme() -> StringName:
	return CosmeticThemes.SOLAR


func _build() -> void:
	# BEHIND the preset's own drawing and behind the body: a negative layer z, and
	# additive because every pixel of it is light.
	_add_draw_layer(_paint_rays, true, -1)
	_build_flares()


func _build_flares() -> void:
	var p: CPUParticles2D = _add_emitter(11, 1.8, VfxTextures.sparkle(9))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(10, BASE_RADIUS * 0.95)
	p.direction = Vector2(0, -1)
	p.spread = 26.0
	p.gravity = Vector2(0, -16.0)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 26.0
	p.damping_min = 4.0
	p.damping_max = 10.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	p.color_ramp = _swell_ramp(accent(), Color(pale(), 1.0), 0.18)
	p.material = _additive()


## The fan. Drawn UPRIGHT rather than squashed onto the ground: this is light
## standing behind the wearer, not a pattern painted on the tiles.
func _paint_rays(layer: Node2D) -> void:
	var turn: float = _elapsed * TAU / RAY_PERIOD_S
	for i: int in RAY_COUNT:
		var angle: float = turn + float(i) * TAU / float(RAY_COUNT)
		# Two breathing terms at different rates, so the rays are never all the
		# same length and the fan never resolves into a symmetric star.
		var reach: float = RAY_REACH * (0.6 + 0.4 * sin(_elapsed * 0.8 + float(i)))
		# Bright enough to read as GOLD. At the alpha this started on, an additive
		# pale gold adds almost the same amount to all three channels over a dark
		# floor, and the fan came out neutral grey - the right shape in the wrong
		# colour, which looks like a missing texture rather than a tuning miss.
		var alpha: float = 0.22 + 0.16 * (0.5 + 0.5 * sin(_elapsed * 1.3 + float(i) * 2.1))
		var half: float = 0.045
		layer.draw_colored_polygon(
			PackedVector2Array([
				Vector2(0.0, FAN_Y),
				Vector2(0.0, FAN_Y) + Vector2.from_angle(angle - half) * reach,
				Vector2(0.0, FAN_Y) + Vector2.from_angle(angle + half) * reach,
			]),
			# core(), not pale(): the saturated dye is what carries the hue once it
			# is being ADDED to whatever is underneath.
			Color(core(), alpha)
		)


func _draw() -> void:
	_use_ground_plane()
	draw_theme_ring()
	_draw_glyphs()


## Four marks on the circle - the alchemical elements, as far as three pixels can
## carry that - lighting one after another rather than together, so the circle
## reads as being WORKED rather than as decoration.
func _draw_glyphs() -> void:
	for i: int in GLYPH_COUNT:
		var phase: float = fposmod(_elapsed / GLYPH_CYCLE_S - float(i) / float(GLYPH_COUNT), 1.0)
		var lit: float = 0.25 + 0.75 * pow(1.0 - clampf(phase / 0.25, 0.0, 1.0), 2.0)
		var angle: float = ring_spin() + float(i) * TAU / float(GLYPH_COUNT)
		var at: Vector2 = _ground_point(angle, BASE_RADIUS * 0.55)
		# A triangle per mark, alternately pointing out and in - fire and water,
		# which is as much alchemy as fits in five pixels.
		var out: Vector2 = _ground_point(angle, BASE_RADIUS * 0.55 + (3.0 if i % 2 == 0 else -3.0))
		var side: Vector2 = _ground_point(angle + PI * 0.5, 3.0)
		draw_colored_polygon(
			PackedVector2Array([at + side, out, at - side]),
			Color(pale(), 0.7 * lit)
		)
