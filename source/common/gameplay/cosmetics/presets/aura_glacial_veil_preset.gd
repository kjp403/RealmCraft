extends ThemeAuraPreset
## GLACIAL VEIL. The matching aura for the Glacial Sovereign title: a frozen ring
## under a slow fall of snow, with crystals growing out of the floor.
##
##   RING      the shared theme circle.
##   CRYSTALS  six spurs of ice standing on the ring, growing and shattering on
##             their own cycles. Drawn UPRIGHT - a crystal squashed onto the
##             ground plane is a puddle.
##   SNOW      falling through the whole aura, from above the wearer's head.
##   MIST      a low ground haze. Mix blended and pale rather than additive: it
##             has to sit ON the floor, and additive white over a snow tile
##             simply disappears.

const SPUR_COUNT: int = 6
## Seconds for one spur to grow, hold and go. Offset per spur so the ring is never
## all ice or all bare.
const SPUR_PERIOD_S: float = 5.0
const SPUR_HEIGHT: float = 13.0


func theme() -> StringName:
	return CosmeticThemes.GLACIAL


func _build() -> void:
	_build_snow()
	_build_mist()


## Snow falling through the aura. Emitted from a wide arc ABOVE the head so it
## falls past the wearer rather than materialising around their knees.
func _build_snow() -> void:
	var p: CPUParticles2D = _add_emitter(16, 3.0, VfxTextures.pip(4))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(BASE_RADIUS * 1.2, 2.0)
	p.position = Vector2(0.0, HEAD_Y - 14.0)
	p.direction = Vector2(0, 1)
	p.spread = 12.0
	# A sideways component in gravity, not in direction: it accumulates, so flakes
	# drift further the longer they fall, which is what real snow does.
	p.gravity = Vector2(4.0, 14.0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	p.color_ramp = _swell_ramp(pale(), Color(pale(), 0.9), 0.12)
	p.material = _additive()


## Ground haze inside the ring.
func _build_mist() -> void:
	var p: CPUParticles2D = _add_emitter(8, 3.4, VfxTextures.puff(14))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(8, BASE_RADIUS * 0.7)
	p.direction = Vector2(0, -1)
	p.spread = 80.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 5.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	p.color_ramp = _fade_ramp(accent(), 0.30)


func _draw() -> void:
	_use_ground_plane()
	draw_theme_ring()
	_draw_spurs()


## Ice spurs standing on the ring. Each is a narrow triangle with a pale edge,
## which at this size is the difference between "crystal" and "green cone".
func _draw_spurs() -> void:
	_use_upright_plane()
	for i: int in SPUR_COUNT:
		var offset: float = float(i) / float(SPUR_COUNT)
		var phase: float = fposmod(_elapsed / SPUR_PERIOD_S + offset * 0.81, 1.0)
		# Grow in hard, hold, then go all at once - ice shatters, it does not wilt.
		var grow: float = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.82, 0.95, phase))
		if grow <= 0.03:
			continue
		var angle: float = offset * TAU + ring_spin() * 0.5
		var foot: Vector2 = _ground_point(angle, BASE_RADIUS * 0.92)
		var height: float = SPUR_HEIGHT * grow
		var lean: float = cos(angle) * 2.5
		var tip: Vector2 = foot + Vector2(lean, -height)
		var half: float = 1.6 + grow * 0.8
		draw_colored_polygon(
			PackedVector2Array([
				foot + Vector2(-half, 0.0), foot + Vector2(half, 0.0), tip,
			]),
			Color(core(), 0.55 * grow)
		)
		# The lit edge, one pixel wide up the side facing the camera.
		draw_line(foot + Vector2(half * 0.2, 0.0), tip, Color(pale(), 0.8 * grow), 1.0)
