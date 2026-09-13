extends CosmeticPreset
## MAIN CHARACTER. A stage spotlight follows the wearer: a warm beam from above,
## a lit pool on the floor, and dust turning slowly in the light.
##
## PROTOTYPE - unregistered. Aura slot.
##
## THE BEAM PASSES OVER THE BODY on purpose. Additive light across the sprite
## brightens the wearer themself, and "this person is lit and nobody else is" is
## the entire joke - a beam kept behind the body reads as a pillar standing next
## to them instead.
##
## No screen texture (it paints black in 2D here): the beam is additive vertex
## colour on a polygon, bright at the floor and fading to nothing at the top.
##
##   POOL   additive floor ellipse with a hot rim, under the body.
##   BEAM   additive trapezoid over the body, a slow sway like a hand-held light.
##   DUST   tiny motes drifting inside the beam.

const LIGHT: Color = Color(1.0, 0.94, 0.78)
const BEAM_TOP_Y: float = -150.0
const BEAM_TOP_HALF: float = 7.0
const POOL_R: float = 21.0


func _build() -> void:
	_add_draw_layer(_paint_pool, true, 0)
	_add_draw_layer(_paint_beam, true, 2)

	var dust: CPUParticles2D = _add_emitter(16, 3.0, VfxTextures.dot(3))
	dust.position = Vector2(0, -36.0)
	# Motes belong to the beam, and the beam follows the wearer.
	dust.local_coords = true
	dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	dust.emission_rect_extents = Vector2(13.0, 34.0)
	dust.direction = Vector2(1, 0)
	dust.spread = 180.0
	dust.gravity = Vector2(0, -1.5)
	dust.initial_velocity_min = 1.0
	dust.initial_velocity_max = 4.0
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.0
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(LIGHT, 0.0), Color(LIGHT, 0.7), Color(LIGHT, 0.7), Color(LIGHT, 0.0)])
	dust.color_ramp = ramp
	dust.material = _additive()
	dust.z_index = 2


## Sideways sway of the beam's top end, in px. The foot stays on the wearer.
func _sway() -> float:
	return sin(_elapsed * 0.6) * 6.0


func _paint_pool(layer: VfxDrawLayer) -> void:
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	var breathe: float = 0.92 + 0.08 * sin(_elapsed * 1.7)
	layer.draw_circle(Vector2.ZERO, POOL_R + 4.0, Color(LIGHT, 0.06 * breathe))
	layer.draw_circle(Vector2.ZERO, POOL_R, Color(LIGHT, 0.16 * breathe))
	layer.draw_circle(Vector2.ZERO, POOL_R * 0.6, Color(LIGHT, 0.10 * breathe))
	layer.draw_arc(Vector2.ZERO, POOL_R, 0.0, TAU, 40, Color(LIGHT, 0.35 * breathe), 1.0)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_beam(layer: VfxDrawLayer) -> void:
	var top: float = _sway()
	var bright: Color = Color(LIGHT, 0.20)
	var clear: Color = Color(LIGHT, 0.0)
	# Wide soft beam, then a narrower brighter core down its middle.
	layer.draw_polygon(
		PackedVector2Array([
			Vector2(top - BEAM_TOP_HALF, BEAM_TOP_Y), Vector2(top + BEAM_TOP_HALF, BEAM_TOP_Y),
			Vector2(POOL_R, 0.0), Vector2(-POOL_R, 0.0),
		]),
		PackedColorArray([clear, clear, bright, bright])
	)
	var core: Color = Color(LIGHT, 0.12)
	layer.draw_polygon(
		PackedVector2Array([
			Vector2(top - BEAM_TOP_HALF * 0.4, BEAM_TOP_Y), Vector2(top + BEAM_TOP_HALF * 0.4, BEAM_TOP_Y),
			Vector2(POOL_R * 0.5, 0.0), Vector2(-POOL_R * 0.5, 0.0),
		]),
		PackedColorArray([clear, clear, core, core])
	)
