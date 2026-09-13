extends CompanionPreset
## JACK-O'-LANTERN. A floating carved pumpkin with a candle flickering inside,
## its grin glowing and throwing warm light around it. It bobs along behind the
## wearer, and when they stop it hangs beside them swinging gently like a lantern
## on a string, the odd ember drifting up out of its lid.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS. A natural seasonal (October) item.
##
## The carved face is ADDITIVE and flickers, so it reads as light shining out of
## the pumpkin rather than as yellow paint on it.

const FOLLOW: Vector2 = Vector2(0, -34)
const FOLLOW_PX: float = 16.0
const IDLE_AFTER_S: float = 0.8

const SKIN: Color = Color(0.95, 0.52, 0.12)
const SKIN_DARK: Color = Color(0.70, 0.32, 0.06)
const SKIN_LIGHT: Color = Color(1.0, 0.70, 0.30)
const STEM: Color = Color(0.36, 0.52, 0.20)
const CANDLE: Color = Color(1.0, 0.88, 0.42)
const GLOW: Color = Color(1.0, 0.62, 0.18)

var _swing: float = 0.0


func _build() -> void:
	stiffness = 55.0
	damping = 9.0
	add_body_layer(_paint_glow, true, 0)
	add_body_layer(_paint_pumpkin, false, 1)
	add_body_layer(_paint_face, true, 2)
	var embers: CPUParticles2D = add_motes(GLOW, 6, VfxTextures.dot(3), Vector2(0, -7))
	embers.gravity = Vector2(0, -14.0)
	embers.lifetime = 1.0


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	if still_for < IDLE_AFTER_S:
		_swing = clampf(-body_velocity().x / maxf(0.001, global_scale.x) * 0.004, -0.3, 0.3)
		return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 3.0) * 1.5)
	# A lantern on a string: a pendulum about a point above it.
	_swing = sin(still_for * 2.4) * 0.18
	var side: float = -signf(_heading.x) if absf(_heading.x) > 0.1 else -1.0
	return Vector2(15.0 * side + sin(_swing) * 6.0, -32.0 + (1.0 - cos(_swing)) * 6.0)


func _flicker() -> float:
	return 0.75 + 0.25 * sin(_elapsed * 19.0) * sin(_elapsed * 7.3)


func _paint_glow(layer: VfxDrawLayer) -> void:
	var f: float = _flicker()
	layer.draw_circle(Vector2(0, -1), 14.0, Color(GLOW, 0.07 * f))
	layer.draw_circle(Vector2(0, -1), 9.0, Color(GLOW, 0.13 * f))


func _paint_pumpkin(layer: VfxDrawLayer) -> void:
	layer.draw_set_transform(Vector2.ZERO, _swing, Vector2.ONE)
	# Stem and a curl of vine.
	layer.draw_rect(Rect2(-1.0, -9.0, 2.0, 3.0), STEM)
	layer.draw_line(Vector2(1.0, -8.0), Vector2(3.0, -9.0), STEM, 1.0)
	# Body: three overlapping lobes, darker outer lobes, lighter centre.
	layer.draw_circle(Vector2(-3.2, 0.0), 5.0, SKIN_DARK)
	layer.draw_circle(Vector2(3.2, 0.0), 5.0, SKIN_DARK)
	layer.draw_circle(Vector2(-2.8, -0.3), 4.4, SKIN)
	layer.draw_circle(Vector2(2.8, -0.3), 4.4, SKIN)
	layer.draw_circle(Vector2(0.0, -0.5), 5.0, SKIN)
	# Rib lines and a highlight.
	layer.draw_line(Vector2(-1.5, -5.0), Vector2(-1.5, 4.0), SKIN_DARK, 1.0)
	layer.draw_line(Vector2(1.5, -5.0), Vector2(1.5, 4.0), SKIN_DARK, 1.0)
	layer.draw_rect(Rect2(-5.0, -3.0, 1.0, 2.0), SKIN_LIGHT)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_face(layer: VfxDrawLayer) -> void:
	layer.draw_set_transform(Vector2.ZERO, _swing, Vector2.ONE)
	var light: Color = Color(CANDLE, _flicker())
	# Triangle eyes.
	for side: float in [-1.0, 1.0]:
		var e: Vector2 = Vector2(side * 2.5, -2.0)
		layer.draw_colored_polygon(PackedVector2Array([
			e + Vector2(-1.5, 1.0), e + Vector2(1.5, 1.0), e + Vector2(0.0, -1.5),
		]), light)
	# A gap-toothed grin.
	layer.draw_colored_polygon(PackedVector2Array([
		Vector2(-4.0, 1.0), Vector2(4.0, 1.0), Vector2(2.5, 3.5), Vector2(-2.5, 3.5),
	]), light)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
