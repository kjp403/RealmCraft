extends CompanionPreset
## STAR SPRITE. A plump little star with a happy face that bobs along beside the
## wearer trailing stardust, rocking gently as it flies. When they stop it does
## a loop-the-loop over their head, spinning as it goes, then settles and twinkles.
##
## PROTOTYPE - not registered, no slot yet.
##
## The face is drawn upright even while the star rocks and spins (rotating
## one-pixel eyes smears them, as the Ghost found), so it always reads.

const FOLLOW: Vector2 = Vector2(0, -36)
const FOLLOW_PX: float = 15.0
const IDLE_AFTER_S: float = 0.8
const LOOP_EVERY_S: float = 4.0
const LOOP_S: float = 1.1
const LOOP_R: float = 8.0

const GOLD: Color = Color(1.0, 0.86, 0.34)
const GOLD_LIGHT: Color = Color(1.0, 0.97, 0.70)
const GOLD_DARK: Color = Color(0.90, 0.55, 0.14)
const GLOW: Color = Color(1.0, 0.85, 0.45)

var _spin: float = 0.0


func _build() -> void:
	stiffness = 80.0
	damping = 10.0
	add_body_layer(_paint_glow, true, 0)
	add_body_layer(_paint_star, false, 1)
	add_motes(GOLD_LIGHT, 12)


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	if still_for < IDLE_AFTER_S:
		_spin = sin(_elapsed * 3.0) * 0.25
		return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 4.0) * 2.0)
	var home: Vector2 = Vector2(-14.0 * signf(_heading.x if absf(_heading.x) > 0.1 else 1.0), -40.0)
	var t: float = fposmod(still_for - IDLE_AFTER_S, LOOP_EVERY_S)
	if t < LOOP_S:
		var k: float = t / LOOP_S
		var a: float = k * TAU
		_spin = a
		return home + Vector2(sin(a) * LOOP_R, -(1.0 - cos(a)) * LOOP_R)
	_spin = sin(_elapsed * 2.0) * 0.12
	return home + Vector2(0, sin(_elapsed * 2.0) * 1.5)


func _star(r_out: float, r_in: float, rot: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 10:
		var a: float = rot - PI * 0.5 + float(i) * TAU / 10.0
		var r: float = r_out if i % 2 == 0 else r_in
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


func _paint_glow(layer: VfxDrawLayer) -> void:
	var tw: float = 0.8 + 0.2 * sin(_elapsed * 6.0)
	layer.draw_circle(Vector2.ZERO, 12.0, Color(GLOW, 0.08 * tw))
	layer.draw_circle(Vector2.ZERO, 8.0, Color(GLOW, 0.16 * tw))


func _paint_star(layer: VfxDrawLayer) -> void:
	# Plump: a high inner radius makes a chubby star rather than a spiky one.
	layer.draw_colored_polygon(_star(8.0, 4.6, _spin), GOLD_DARK)
	layer.draw_colored_polygon(_star(7.0, 3.9, _spin), GOLD)
	layer.draw_colored_polygon(_star(3.2, 1.9, _spin), GOLD_LIGHT)
	var look: Vector2 = Vector2(signf(_heading.x) * 0.6, 0.0)
	# Eyes two apart and three tall: closer and shorter read as a squint.
	draw_eyes(layer, Vector2(0.0, -1.0), 2.0, look, blinking(2.9, 0.2), 3)
	draw_blush(layer, Vector2(look.x, 1.0), 3.5)
	# A proper U smile - a flat dash read as unimpressed.
	var m: float = roundf(look.x)
	layer.draw_rect(Rect2(m - 2.0, 2.0, 1.0, 1.0), FACE_DARK)
	layer.draw_rect(Rect2(m + 1.0, 2.0, 1.0, 1.0), FACE_DARK)
	layer.draw_rect(Rect2(m - 1.0, 3.0, 2.0, 1.0), FACE_DARK)
