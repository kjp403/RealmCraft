extends GroundCompanionPreset
## MUSHROOM SPROUT. A little red-capped mushroom with a face on its stem that
## bounces after the wearer, cap wobbling on every landing. When they stop it
## settles down, wiggles its cap side to side, and puffs out glowing spores.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.

const CAP: Color = Color(0.86, 0.24, 0.24)
const CAP_DARK: Color = Color(0.58, 0.12, 0.16)
const CAP_LIGHT: Color = Color(1.0, 0.48, 0.44)
const SPOT: Color = Color(1.0, 0.97, 0.90)
const STEM: Color = Color(0.98, 0.92, 0.80)
const STEM_SHADE: Color = Color(0.82, 0.74, 0.62)
const GILL: Color = Color(0.74, 0.60, 0.52)
const SPORE: Color = Color(0.80, 1.0, 0.55)
const IDLE_AFTER_S: float = 0.8

var _spores: CPUParticles2D


func _build() -> void:
	hop_peak = 5.0
	add_body_layer(_paint_mushroom, false, 0)
	var p: CPUParticles2D = add_motes(SPORE, 8, VfxTextures.dot(4), Vector2(0, -12))
	p.gravity = Vector2(0, -6.0)
	p.lifetime = 1.4
	p.emission_sphere_radius = 5.0
	_spores = p


func _tick(delta: float) -> void:
	super(delta)
	_spores.emitting = still_for >= IDLE_AFTER_S


## Upper half-ellipse with its flat edge on [param base].
func _dome(base: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 13:
		var a: float = PI + PI * float(i) / 12.0
		pts.append(base + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _paint_mushroom(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 6.0)
	# Stem with the face on it.
	layer.draw_rect(Rect2(-3.0, -7.0, 6.0, 7.0), STEM)
	layer.draw_rect(Rect2(2.0, -7.0, 1.0, 7.0), STEM_SHADE)
	layer.draw_rect(Rect2(-3.0, -1.0, 6.0, 1.0), STEM_SHADE)
	var look: Vector2 = Vector2(facing * 0.6, 0.0)
	draw_eyes(layer, Vector2(0.0, -4.0), 1.5, look, blinking(3.3, 0.4), 2)
	draw_blush(layer, Vector2(look.x, -2.0), 2.5)

	# The cap wiggles when idle, and lags a hop behind the stem when moving.
	var wiggle: float = 0.0
	if still_for >= IDLE_AFTER_S:
		wiggle = sin(still_for * 5.0) * 1.2 * float(fposmod(still_for, 3.0) < 1.0)
	var lag: float = -hop_height * 0.25
	var c: Vector2 = Vector2(wiggle, -8.0 + lag)
	# Dome: gills underneath, then the cap in two tones, a highlight, then spots.
	# Half-ellipse polygons, not circles - a full circle hangs down over the face.
	layer.draw_rect(Rect2(c.x - 6.0, c.y, 12.0, 1.0), GILL)
	layer.draw_colored_polygon(_dome(c, 7.0, 7.0), CAP_DARK)
	layer.draw_colored_polygon(_dome(c + Vector2(-0.5, -0.8), 5.8, 5.8), CAP)
	layer.draw_rect(Rect2(c.x - 3.0, c.y - 6.0, 3.0, 1.0), CAP_LIGHT)
	for s: Vector3 in [Vector3(-3.0, -4.0, 1.2), Vector3(2.0, -5.0, 1.0), Vector3(3.5, -2.0, 0.8), Vector3(-0.5, -1.5, 0.7)]:
		layer.draw_circle(c + Vector2(s.x, s.y), s.z, SPOT)
