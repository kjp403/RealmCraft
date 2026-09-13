extends CompanionPreset
## AXOLOTL. A pink axolotl that swims through the air beside the wearer, body
## undulating and frilly gills waving. When they stop it curls round to face
## them with its wide smile, little legs paddling, blowing the odd bubble.
##
## PROTOTYPE - not registered, no slot yet.
##
## Drawn facing RIGHT, mirrored by facing. The body is a chain of circles on a
## travelling sine wave, which is what reads as swimming rather than floating.

const FOLLOW: Vector2 = Vector2(0, -34)
const FOLLOW_PX: float = 17.0
const IDLE_AFTER_S: float = 0.8

const SKIN: Color = Color(1.0, 0.72, 0.80)
const SKIN_DARK: Color = Color(0.88, 0.50, 0.62)
const SKIN_LIGHT: Color = Color(1.0, 0.88, 0.92)
const GILL: Color = Color(0.92, 0.36, 0.56)
const GILL_TIP: Color = Color(1.0, 0.56, 0.72)
const BUBBLE: Color = Color(0.80, 0.92, 1.0)

var _facing: float = 1.0
var _bubbles: CPUParticles2D


func _build() -> void:
	stiffness = 55.0
	damping = 9.0
	add_body_layer(_paint_axolotl, false, 0)
	var b: CPUParticles2D = add_motes(BUBBLE, 5, VfxTextures.dot(5), Vector2(4, -3))
	b.gravity = Vector2(0, -18.0)
	b.lifetime = 1.3
	b.material = null   # bubbles are glass, not light
	_bubbles = b


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	var idle: bool = still_for >= IDLE_AFTER_S
	_bubbles.emitting = idle
	if absf(_heading.x) > 0.2:
		_facing = signf(_heading.x)
	if not idle:
		return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 4.0) * 2.0)
	return Vector2(-16.0 * _facing, -30.0 + sin(_elapsed * 1.8) * 2.0)


func _paint_axolotl(layer: VfxDrawLayer) -> void:
	var idle: bool = still_for >= IDLE_AFTER_S
	# Idle it hovers BEHIND the wearer's heading, so facing the heading points it
	# back toward them.
	var f: float = _facing
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2(f, 1.0))
	var speed: float = 9.0 if not idle else 3.5
	var amp: float = 1.2 if not idle else 0.6

	# Tail: tapering chain with a soft fin along the top.
	for i: int in range(6, 0, -1):
		var x: float = -2.0 - float(i) * 1.8
		var y: float = sin(_elapsed * speed - float(i) * 0.7) * amp * (float(i) / 3.0)
		var r: float = maxf(0.8, 2.6 - float(i) * 0.3)
		layer.draw_circle(Vector2(x, y + 0.8), r + 0.6, SKIN_LIGHT)
		layer.draw_circle(Vector2(x, y), r, SKIN)
	# Body and legs.
	var paddle: float = sin(_elapsed * speed * 1.2)
	layer.draw_rect(Rect2(-3.0 + paddle, 2.0, 1.0, 2.0), SKIN_DARK)
	layer.draw_rect(Rect2(2.0 - paddle, 2.0, 1.0, 2.0), SKIN_DARK)
	layer.draw_circle(Vector2(0.0, 0.0), 3.4, SKIN_DARK)
	layer.draw_circle(Vector2(-0.2, -0.3), 3.0, SKIN)
	# Head: wide and round, belly-light underneath.
	var head: Vector2 = Vector2(4.5, -1.5)
	layer.draw_circle(head, 4.2, SKIN_DARK)
	layer.draw_circle(head + Vector2(-0.2, -0.3), 3.8, SKIN)
	layer.draw_rect(Rect2(head.x - 2.0, head.y + 1.5, 4.0, 1.0), SKIN_LIGHT)
	# Gills: three frilly stalks each side of the head, waving.
	for g: int in 3:
		var wave: float = sin(_elapsed * 6.0 + float(g) * 1.1) * 0.8
		var ang: float = -2.2 + float(g) * 0.55
		var root: Vector2 = head + Vector2(-2.5, -1.0)
		var tip: Vector2 = root + Vector2(cos(ang), sin(ang)) * 4.0 + Vector2(wave, 0.0)
		layer.draw_line(root, tip, GILL, 1.0)
		layer.draw_rect(Rect2(tip.round() - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), GILL_TIP)
	# Face: wide-set eyes and a big smile.
	var eye: Vector2 = (head + Vector2(1.5, -1.5)).round()
	if blinking(3.4, 0.5):
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y, 2.0, 1.0), FACE_DARK)
	else:
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y - 1.0, 2.0, 2.0), FACE_DARK)
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y - 1.0, 1.0, 1.0), FACE_SHINE)
	layer.draw_rect(Rect2(head.x + 1.0, head.y + 0.5, 3.0, 1.0), FACE_DARK)
	layer.draw_rect(Rect2(head.x - 0.5, head.y + 0.5, 1.0, 1.0), FACE_BLUSH)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
