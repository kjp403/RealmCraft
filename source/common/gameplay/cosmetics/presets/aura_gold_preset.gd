extends CosmeticPreset
## GOLD AURA. A metallic runic circle turning clockwise under the wearer, coins
## and gems shimmering up out of it, and lens glints firing off the rim.
##
## Gold is the wealth flex, so this is the one aura allowed to be BRIGHT: the
## drawn layer is fully additive and the glints are deliberately blown out. The
## discipline that keeps it from becoming a white blob is that the brightness is
## spent on small things - a rune tick, a glint core, a gem facet - over a
## restrained warm ring, rather than on a big glowing disc.
##
##   CIRCLE  three concentric rings and a band of rune ticks, all turning
##           CLOCKWISE together (screen y is down, so that is a positive angle).
##   BLOOM   a wide, very low-alpha additive wash under the rings. This is what
##           reads as "expensive metal catching light" instead of "yellow line".
##   RICHES  coins and cut gems rising and tumbling, catching the light as they go.
##   GLINTS  three lens flares spaced around the rim, each firing on its own long
##           cycle so the perimeter sparkles at unpredictable moments.

const RING_TINT: Color = Color(1.0, 0.82, 0.34)
const DEEP_GOLD: Color = Color(0.72, 0.46, 0.08)
const PALE_GOLD: Color = Color(1.0, 0.96, 0.76)
const GEM_TINT: Color = Color(1.0, 0.88, 0.55)

const RUNE_COUNT: int = 10
const GLINT_COUNT: int = 3
## Seconds per rotation of the runic circle. Slow and stately - a fast spin reads
## as a cooldown timer, which is a HUD idiom and wrong for a cosmetic.
const SPIN_PERIOD_S: float = 9.0
## Seconds between one glint's flashes. Long, and offset per glint, so the rim
## twinkles irregularly rather than blinking on a beat.
const GLINT_PERIOD_S: float = 2.8


func _build() -> void:
	# Every drawn layer here is light. Children keep their own materials.
	material = _additive()
	_build_riches()
	_build_dust()


## Coins and cut gems lifting off the circle. Two shapes from one emitter is not
## possible, so the tumble does the work: a diamond spinning through its own plane
## alternately reads as a coin edge-on and as a gem face-on.
func _build_riches() -> void:
	var p: CPUParticles2D = _add_emitter(9, 1.9, VfxTextures.diamond(7))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(10, BASE_RADIUS * 0.8)
	p.direction = Vector2(0, -1)
	p.spread = 16.0
	p.gravity = Vector2(0, -18.0)
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 32.0
	p.damping_min = 4.0
	p.damping_max = 10.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.color_ramp = _swell_ramp(RING_TINT, Color(GEM_TINT, 1.0), 0.18)
	p.material = _additive()


## Fine sparkle dust between the coins, so the column is not just nine objects.
func _build_dust() -> void:
	var p: CPUParticles2D = _add_emitter(12, 1.4, VfxTextures.sparkle(9))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(12, BASE_RADIUS * 0.95)
	p.direction = Vector2(0, -1)
	p.spread = 35.0
	p.gravity = Vector2(0, -26.0)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 26.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	p.color_ramp = _fade_ramp(PALE_GOLD, 0.85)
	p.material = _additive()


func _draw() -> void:
	_use_ground_plane()
	var spin: float = _elapsed * TAU / SPIN_PERIOD_S # positive = clockwise on screen
	_draw_bloom()
	_draw_rings(spin)
	_draw_runes(spin)
	_draw_glints(spin)


## A wide, dim additive wash. Three stacked discs rather than one, because a
## single low-alpha circle has a visible edge and stacked falloffs do not.
func _draw_bloom() -> void:
	var breathe: float = 0.5 + 0.5 * sin(_elapsed * 1.3)
	draw_circle(Vector2.ZERO, BASE_RADIUS * 1.45, Color(DEEP_GOLD, 0.045 + 0.015 * breathe))
	draw_circle(Vector2.ZERO, BASE_RADIUS * 1.05, Color(RING_TINT, 0.055 + 0.020 * breathe))
	draw_circle(Vector2.ZERO, BASE_RADIUS * 0.55, Color(PALE_GOLD, 0.045 + 0.020 * breathe))


## Three concentric rings at different weights. The weights are what make it look
## engraved: an even set of identical circles reads as a target.
func _draw_rings(spin: float) -> void:
	draw_arc(Vector2.ZERO, BASE_RADIUS, spin, spin + TAU, 44, Color(RING_TINT, 0.75), 2.0, false)
	draw_arc(
		Vector2.ZERO, BASE_RADIUS * 0.86, spin, spin + TAU, 40,
		Color(DEEP_GOLD, 0.55), 1.0, false
	)
	draw_arc(
		Vector2.ZERO, BASE_RADIUS * 0.46, spin * 1.3, spin * 1.3 + TAU * 0.68, 28,
		Color(PALE_GOLD, 0.60), 1.0, false
	)


## The rune band between the two outer rings. Each glyph is two or three pixels
## arranged from its own index, so the ring carries a repeating but non-uniform
## inscription - readable as writing, not as tick marks.
func _draw_runes(spin: float) -> void:
	for i: int in RUNE_COUNT:
		var angle: float = spin + float(i) * TAU / float(RUNE_COUNT)
		var at: Vector2 = _ground_point(angle, BASE_RADIUS * 0.93)
		# Glyphs catch the light as they come round the near side.
		var lit: float = 0.45 + 0.55 * (0.5 + 0.5 * sin(angle))
		var glyph: int = i % 4
		draw_rect(Rect2(at - Vector2(0.5, 1.5), Vector2(1.0, 3.0)), Color(PALE_GOLD, 0.8 * lit))
		if glyph != 0:
			draw_rect(Rect2(at + Vector2(-1.5, -1.5), Vector2(3.0, 1.0)), Color(RING_TINT, 0.7 * lit))
		if glyph > 1:
			draw_rect(Rect2(at + Vector2(-1.5, 0.5), Vector2(3.0, 1.0)), Color(RING_TINT, 0.7 * lit))


## Lens flares on the rim: a hot core with a long horizontal streak and a short
## vertical one. The asymmetry is the whole trick - an even cross reads as a star
## sprite, while a wide horizontal streak reads as light through a lens.
##
## Drawn UPRIGHT: a flare is a lens artefact in screen space, so squashing it onto
## the ground plane would be the one place the floor illusion actively hurts.
func _draw_glints(spin: float) -> void:
	var positions: Array[Vector2] = []
	var strengths: Array[float] = []
	for i: int in GLINT_COUNT:
		var phase: float = fposmod(_elapsed / GLINT_PERIOD_S + float(i) * 0.37, 1.0)
		# A short flash and a long wait: bright for roughly a fifth of the cycle.
		var flash: float = pow(1.0 - clampf(phase / 0.2, 0.0, 1.0), 2.0)
		if flash <= 0.02:
			continue
		var angle: float = spin * 0.8 + float(i) * TAU / float(GLINT_COUNT)
		positions.append(_ground_point(angle, BASE_RADIUS))
		strengths.append(flash)
	if positions.is_empty():
		return
	_use_upright_plane()
	for i: int in positions.size():
		var at: Vector2 = positions[i]
		var flash: float = strengths[i]
		draw_line(at - Vector2(9.0, 0.0), at + Vector2(9.0, 0.0), Color(RING_TINT, 0.5 * flash), 1.0)
		draw_line(at - Vector2(0.0, 4.0), at + Vector2(0.0, 4.0), Color(PALE_GOLD, 0.6 * flash), 1.0)
		draw_circle(at, 2.6, Color(PALE_GOLD, 0.9 * flash))
	_use_ground_plane()
