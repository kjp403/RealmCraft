extends CompanionPreset
## CLOUD PUP. A puppy made of cloud: fluffy white puffs, floppy ears that flap
## as it flies, a wagging puff of a tail and its tongue out with happiness. When
## the wearer stops it sits on the air beside them and a little rainbow arcs over
## its head.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.

const FOLLOW: Vector2 = Vector2(0, -32)
const FOLLOW_PX: float = 17.0
const IDLE_AFTER_S: float = 0.8
const RAINBOW_IN_S: float = 0.8

const PUFF: Color = Color(0.98, 0.98, 1.0)
const PUFF_SHADE: Color = Color(0.80, 0.84, 0.96)
const EAR: Color = Color(0.66, 0.72, 0.90)
const NOSE: Color = Color(0.20, 0.18, 0.28)
const TONGUE: Color = Color(1.0, 0.52, 0.64)
const RAINBOW: Array[Color] = [
	Color(1.0, 0.40, 0.40), Color(1.0, 0.70, 0.30), Color(1.0, 0.95, 0.40),
	Color(0.50, 0.90, 0.50), Color(0.45, 0.70, 1.0), Color(0.72, 0.52, 1.0),
]

var _facing: float = 1.0


func _build() -> void:
	stiffness = 65.0
	damping = 10.0
	add_body_layer(_paint_rainbow, true, 0)
	add_body_layer(_paint_pup, false, 1)


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	if absf(_heading.x) > 0.2:
		_facing = signf(_heading.x)
	if still_for < IDLE_AFTER_S:
		return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 5.0) * 1.5)
	return Vector2(-16.0 * _facing, -30.0 + sin(_elapsed * 1.6) * 1.0)


func _paint_rainbow(layer: VfxDrawLayer) -> void:
	var k: float = clampf((still_for - IDLE_AFTER_S) / RAINBOW_IN_S, 0.0, 1.0)
	if k <= 0.0:
		return
	var sweep: float = PI * k
	for i: int in RAINBOW.size():
		var r: float = 11.0 - float(i)
		layer.draw_arc(Vector2(0, 0), r, PI, PI + sweep, 20, Color(RAINBOW[i], 0.55), 1.0)


func _paint_pup(layer: VfxDrawLayer) -> void:
	var moving: bool = still_for < IDLE_AFTER_S
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2(_facing, 1.0))
	var flop: float = sin(_elapsed * (10.0 if moving else 3.0)) * (1.5 if moving else 0.5)
	# Tail puff, wagging.
	var wag: float = sin(_elapsed * 14.0) * 1.5
	layer.draw_circle(Vector2(-7.0, -2.0 + wag), 2.2, PUFF_SHADE)
	layer.draw_circle(Vector2(-7.2, -2.3 + wag), 1.7, PUFF)
	# Cloud body: shaded puffs first, lit puffs over them.
	for p: Vector3 in [Vector3(-4.0, 1.0, 3.2), Vector3(0.0, 2.0, 3.4), Vector3(3.5, 1.0, 3.0), Vector3(-1.5, -1.5, 3.5)]:
		layer.draw_circle(Vector2(p.x, p.y + 0.8), p.z, PUFF_SHADE)
	for p: Vector3 in [Vector3(-4.0, 1.0, 3.2), Vector3(0.0, 2.0, 3.4), Vector3(3.5, 1.0, 3.0), Vector3(-1.5, -1.5, 3.5)]:
		layer.draw_circle(Vector2(p.x, p.y), p.z - 0.5, PUFF)
	# Head.
	var head: Vector2 = Vector2(4.5, -4.0)
	layer.draw_circle(head + Vector2(0, 0.6), 4.0, PUFF_SHADE)
	layer.draw_circle(head, 3.6, PUFF)
	# Floppy ears that flap.
	layer.draw_colored_polygon(PackedVector2Array([
		head + Vector2(-3.0, -2.0), head + Vector2(-1.0, -3.0), head + Vector2(-2.5, 1.5 + flop), head + Vector2(-4.5, 1.0 + flop),
	]), EAR)
	layer.draw_colored_polygon(PackedVector2Array([
		head + Vector2(1.0, -3.2), head + Vector2(2.8, -2.4), head + Vector2(2.2, 0.8 - flop), head + Vector2(0.6, 0.4 - flop),
	]), EAR)
	# Face.
	var eye: Vector2 = (head + Vector2(0.5, -1.0)).round()
	if blinking(3.1, 1.7):
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y, 2.0, 1.0), FACE_DARK)
	else:
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y - 1.0, 2.0, 2.0), FACE_DARK)
		layer.draw_rect(Rect2(eye.x - 1.0, eye.y - 1.0, 1.0, 1.0), FACE_SHINE)
	layer.draw_rect(Rect2(head.x + 3.0, head.y - 0.5, 2.0, 2.0), NOSE)
	layer.draw_rect(Rect2(head.x - 1.5, head.y + 1.5, 2.0, 1.0), FACE_BLUSH)
	# Tongue out while it runs, panting.
	if moving:
		var pant: float = 1.0 + roundf(absf(sin(_elapsed * 12.0)))
		layer.draw_rect(Rect2(head.x + 2.0, head.y + 2.0, 1.5, pant), TONGUE)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
