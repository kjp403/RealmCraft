extends CompanionPreset
## BABY DRAGON. A chubby little dragon flapping along at the wearer's shoulder,
## tail swishing. When they stop it hovers beside them and every few seconds
## tries to breathe fire - and manages a hiccup of flame and a puff of smoke.
##
## PROTOTYPE - not registered, no slot yet.
##
## Drawn facing RIGHT and mirrored by [member _facing] through the layer
## transform, so every part is authored once. Parts back to front: far wing,
## tail, body and belly, head with horns and snout, near wing.

const FOLLOW: Vector2 = Vector2(0, -36)
const FOLLOW_PX: float = 16.0
const IDLE_AFTER_S: float = 0.8
const SNEEZE_EVERY_S: float = 3.2

const SCALE: Color = Color(0.36, 0.74, 0.62)
const SCALE_DARK: Color = Color(0.20, 0.48, 0.42)
const SCALE_LIGHT: Color = Color(0.58, 0.90, 0.76)
const BELLY: Color = Color(1.0, 0.90, 0.66)
const WING: Color = Color(0.26, 0.56, 0.50)
const WING_WEB: Color = Color(0.46, 0.80, 0.70)
const HORN: Color = Color(1.0, 0.94, 0.80)
const FLAME: Color = Color(1.0, 0.62, 0.18)
const FLAME_CORE: Color = Color(1.0, 0.92, 0.50)
const SMOKE: Color = Color(0.70, 0.70, 0.74)

var _facing: float = 1.0


func _build() -> void:
	stiffness = 70.0
	damping = 10.0
	add_body_layer(_paint_dragon, false, 0)
	add_body_layer(_paint_breath, false, 1)


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	if absf(_heading.x) > 0.2:
		_facing = signf(_heading.x)
	if still_for < IDLE_AFTER_S:
		return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 7.0) * 1.5)
	# Idle: hovers beside the wearer's head (see _face_dir for which way it looks).
	return Vector2(-16.0 * _facing, -36.0 + sin(_elapsed * 3.5) * 2.0)


func _face_dir() -> float:
	# Idle it hovers behind the wearer and faces OUTWARD, away from them: its
	# fire-hiccup must never point at a player's head, where it reads as an attack.
	return _facing if still_for < IDLE_AFTER_S else -_facing


func _paint_dragon(layer: VfxDrawLayer) -> void:
	var f: float = _face_dir()
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2(f, 1.0))
	var flap_rate: float = 14.0 if still_for < IDLE_AFTER_S else 9.0
	var flap: float = sin(_elapsed * flap_rate)   # -1 down, +1 up

	_wing(layer, Vector2(-1.0, -3.0), flap, true)

	# Tail: a curve back and down with a spade tip, swishing.
	var swish: float = sin(_elapsed * 3.0) * 1.5
	var tail: PackedVector2Array = PackedVector2Array([
		Vector2(-3.0, 1.0), Vector2(-6.0, 2.5 + swish * 0.3), Vector2(-8.5, 1.5 + swish), Vector2(-10.0, -0.5 + swish),
	])
	layer.draw_polyline(tail, SCALE_DARK, 2.0)
	var tip: Vector2 = tail[3]
	layer.draw_colored_polygon(PackedVector2Array([
		tip + Vector2(-2.0, 0.0), tip + Vector2(0.0, -2.0), tip + Vector2(1.5, 0.5), tip + Vector2(0.0, 1.5),
	]), SCALE_DARK)

	# Body and belly.
	layer.draw_circle(Vector2(0.0, 0.0), 4.2, SCALE_DARK)
	layer.draw_circle(Vector2(-0.3, -0.3), 3.7, SCALE)
	layer.draw_circle(Vector2(1.0, 1.0), 2.4, BELLY)
	# Little feet tucked under.
	layer.draw_rect(Rect2(-2.0, 3.5, 2.0, 1.0), SCALE_DARK)
	layer.draw_rect(Rect2(1.0, 3.5, 2.0, 1.0), SCALE_DARK)

	# Head: round, with a snout, two horns and a cheek of lighter scale.
	var head: Vector2 = Vector2(3.5, -5.0)
	layer.draw_rect(Rect2(head.x + 0.0, head.y - 5.5, 1.0, 2.0), HORN)
	layer.draw_rect(Rect2(head.x + 2.0, head.y - 5.0, 1.0, 2.0), HORN)
	layer.draw_circle(head, 3.8, SCALE_DARK)
	layer.draw_circle(head + Vector2(-0.3, -0.3), 3.3, SCALE)
	layer.draw_rect(Rect2(head.x + 2.0, head.y - 0.5, 3.0, 2.5), SCALE)
	layer.draw_rect(Rect2(head.x + 4.0, head.y - 0.5, 1.0, 1.0), SCALE_DARK)   # nostril
	layer.draw_rect(Rect2(head.x - 2.0, head.y - 2.5, 2.0, 1.0), SCALE_LIGHT)
	# One eye (it is in profile), with the shared shine, and a blush.
	var eye: Vector2 = (head + Vector2(1.0, -1.5)).round()
	if blinking(3.6, 1.1):
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y + 1.0, 2.0, 1.0), FACE_DARK)
	else:
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y - 1.0, 2.0, 3.0), FACE_DARK)
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y - 1.0, 1.0, 1.0), FACE_SHINE)
	layer.draw_rect(Rect2(head.x - 1.0, head.y + 1.5, 2.0, 1.0), FACE_BLUSH)

	_wing(layer, Vector2(0.0, -2.0), flap, false)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A bat wing from [param root]: leading edge up to a tip that rises and falls
## with the flap, a scalloped trailing edge, and two web lines.
func _wing(layer: VfxDrawLayer, root: Vector2, flap: float, far: bool) -> void:
	var lift: float = flap * 4.5
	var tip: Vector2 = root + Vector2(-5.0, -6.0 - lift)
	var elbow: Vector2 = root + Vector2(-2.0, -4.0 - lift * 0.5)
	var back: Vector2 = root + Vector2(-7.0, -1.0 - lift * 0.4)
	var pts: PackedVector2Array = PackedVector2Array([root, elbow, tip, back, root + Vector2(-3.5, 0.5)])
	layer.draw_colored_polygon(pts, WING if not far else WING.darkened(0.25))
	layer.draw_line(elbow, back, WING_WEB if not far else WING, 1.0)
	layer.draw_line(tip, root + Vector2(-3.5, 0.5), WING_WEB if not far else WING, 1.0)


## The sneeze: a hiccup of flame out of the snout, then a puff of smoke that
## drifts up and fades. Only while idle.
func _paint_breath(layer: VfxDrawLayer) -> void:
	if still_for < IDLE_AFTER_S + 1.0:
		return
	var f: float = _face_dir()
	var t: float = fposmod(still_for, SNEEZE_EVERY_S)
	var snout: Vector2 = Vector2(9.0 * f, -4.5)
	if t < 0.25:
		var k: float = t / 0.25
		var reach: float = 3.0 + 5.0 * sin(k * PI)
		layer.draw_colored_polygon(PackedVector2Array([
			snout + Vector2(0, -1.5), snout + Vector2(reach * f, 0), snout + Vector2(0, 1.5),
		]), FLAME)
		layer.draw_circle(snout + Vector2(1.5 * f, 0), 1.2, FLAME_CORE)
	elif t < 1.3:
		var k: float = (t - 0.25) / 1.05
		for i: int in 3:
			var at: Vector2 = snout + Vector2((3.0 + float(i) * 2.0 + k * 3.0) * f, -k * 7.0 - float(i) * 1.5)
			layer.draw_circle(at, 1.2 + k * 1.8 - float(i) * 0.3, Color(SMOKE, 0.7 * (1.0 - k)))
