extends GroundCompanionPreset
## DUCKLING. A fluffy yellow duckling that waddles after the wearer, wings
## flapping when it has to hurry. When they stop it sits down beside them, and
## every so often looks up and quacks - with a little heart floating up.
##
## PROTOTYPE - not registered, no slot yet.
##
## A duckling WADDLES rather than bounces: a low hop, and a side-to-side rock
## synced to the step, drawn as a small rotation of the whole body.

const FEATHER: Color = Color(1.0, 0.88, 0.32)
const FEATHER_LIGHT: Color = Color(1.0, 0.97, 0.66)
const FEATHER_DARK: Color = Color(0.90, 0.66, 0.16)
const BEAK: Color = Color(1.0, 0.56, 0.16)
const FEET: Color = Color(1.0, 0.50, 0.14)
const HEART: Color = Color(1.0, 0.45, 0.62)
const SIT_AFTER_S: float = 0.8
const QUACK_EVERY_S: float = 3.4


func _build() -> void:
	hop_peak = 2.0
	add_body_layer(_paint_duck, false, 0)


func _paint_duck(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 5.0)
	var sitting: bool = still_for >= SIT_AFTER_S
	var f: float = facing
	var rock: float = sin(hop_phase * TAU) * 0.09 if is_hopping() else 0.0
	layer.draw_set_transform(Vector2(0.0, -hop_height), rock, Vector2(squash * f, 1.0 / squash))

	var sink: float = 2.0 if sitting else 0.0
	if not sitting:
		var step: float = sin(hop_phase * TAU) if is_hopping() else 0.0
		layer.draw_rect(Rect2(-3.0, -1.0 - maxf(0.0, step), 2.0, 1.0), FEET)
		layer.draw_rect(Rect2(1.0, -1.0 - maxf(0.0, -step), 2.0, 1.0), FEET)
	# Body: a round fluffball, shaded underneath, with a tail tuft.
	var b: Vector2 = Vector2(-0.5, -5.0 + sink)
	layer.draw_circle(b, 4.6, FEATHER_DARK)
	layer.draw_circle(b + Vector2(-0.3, -0.4), 4.1, FEATHER)
	layer.draw_rect(Rect2(b.x - 5.5, b.y - 2.0, 2.0, 1.0), FEATHER)
	# Wing: flaps when hurrying, folded when sitting.
	var flap: float = absf(sin(_elapsed * 16.0)) * 2.0 if is_hopping() and body_velocity().length() > 40.0 else 0.0
	layer.draw_colored_polygon(PackedVector2Array([
		b + Vector2(-2.5, -1.0), b + Vector2(1.5, -1.0), b + Vector2(0.5, 2.0), b + Vector2(-3.0, 1.5 - flap),
	]), FEATHER_DARK)
	# Head, looking up while it quacks.
	var t: float = fposmod(still_for, QUACK_EVERY_S)
	var quacking: bool = sitting and t < 0.45
	var h: Vector2 = b + Vector2(2.5, -5.0 - (1.0 if quacking else 0.0))
	layer.draw_circle(h, 3.3, FEATHER_DARK)
	layer.draw_circle(h + Vector2(-0.3, -0.3), 2.9, FEATHER)
	layer.draw_rect(Rect2(h.x - 1.0, h.y - 3.5, 2.0, 1.0), FEATHER_LIGHT)   # fluff tuft
	# Beak: opens on the quack.
	layer.draw_rect(Rect2(h.x + 2.5, h.y, 2.5, 1.0), BEAK)
	layer.draw_rect(Rect2(h.x + 2.5, h.y + (2.0 if quacking else 1.0), 2.0, 1.0), BEAK)
	# Eye in profile, with shine; blush.
	var eye: Vector2 = (h + Vector2(1.0, -1.0)).round()
	if blinking(3.0, 0.9):
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y + 1.0, 2.0, 1.0), FACE_DARK)
	else:
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y - 1.0, 2.0, 2.0), FACE_DARK)
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y - 1.0, 1.0, 1.0), FACE_SHINE)
	layer.draw_rect(Rect2(h.x - 1.0, h.y + 1.0, 2.0, 1.0), FACE_BLUSH)

	# The heart: drawn unmirrored, rising and fading after each quack.
	layer.draw_set_transform(Vector2(0.0, -hop_height), 0.0, Vector2.ONE)
	if sitting and t < 1.4:
		var k: float = t / 1.4
		var at: Vector2 = Vector2(h.x * f + 3.0 * f, h.y - 4.0 - k * 8.0).round()
		var c: Color = Color(HEART, 1.0 - k)
		layer.draw_rect(Rect2(at.x - 2.0, at.y, 2.0, 1.0), c)
		layer.draw_rect(Rect2(at.x + 1.0, at.y, 2.0, 1.0), c)
		layer.draw_rect(Rect2(at.x - 2.0, at.y + 1.0, 5.0, 1.0), c)
		layer.draw_rect(Rect2(at.x - 1.0, at.y + 2.0, 3.0, 1.0), c)
		layer.draw_rect(Rect2(at.x, at.y + 3.0, 1.0, 1.0), c)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
