extends CompanionPreset
## OWL. A round little owl that flies after the wearer on beating wings, and when
## they stop, glides in and perches on top of their head - where it slowly
## blinks, looks around, and every so often swivels its head right round so all
## you see is the back of it, then swivels back.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## The perch uses [method CompanionPreset.wearer_head_top], the same measured
## head height the Moth uses, so it sits ON the head for every skin.

const FOLLOW: Vector2 = Vector2(-2, -36)
const FOLLOW_PX: float = 15.0
const PERCH_AFTER_S: float = 1.0
const SWIVEL_EVERY_S: float = 4.5
const SWIVEL_S: float = 1.2

const FEATHER: Color = Color(0.58, 0.42, 0.30)
const FEATHER_DARK: Color = Color(0.38, 0.26, 0.18)
const BELLY: Color = Color(0.92, 0.84, 0.70)
const BELLY_MARK: Color = Color(0.70, 0.56, 0.42)
const EYE_RING: Color = Color(1.0, 0.96, 0.86)
const IRIS: Color = Color(1.0, 0.76, 0.20)
const BEAK: Color = Color(1.0, 0.68, 0.22)

var _perched: bool = false


func _build() -> void:
	stiffness = 70.0
	damping = 11.0
	add_body_layer(_paint_owl, false, 0)


func target_local(_delta: float) -> Vector2:
	_perched = still_for >= PERCH_AFTER_S
	set_in_front(true)
	if _perched:
		stiffness = 160.0
		damping = 22.0
		return Vector2(0.0, wearer_head_top() - 0.5)
	stiffness = 70.0
	damping = 11.0
	return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 6.0) * 2.0)


func _paint_owl(layer: VfxDrawLayer) -> void:
	# Origin is the owl's FEET, so a perch lands it standing on the head.
	var flap: float = 0.0 if _perched else sin(_elapsed * 13.0)
	# Wings: out and beating in flight, folded at the sides when perched.
	for side: float in [-1.0, 1.0]:
		if _perched:
			layer.draw_rect(Rect2(side * 4.0 - 1.0, -7.0, 2.0, 5.0), FEATHER_DARK)
		else:
			layer.draw_colored_polygon(PackedVector2Array([
				Vector2(side * 3.0, -7.0), Vector2(side * 9.0, -9.0 - flap * 4.0),
				Vector2(side * 8.0, -5.0 - flap * 2.0), Vector2(side * 3.0, -3.0),
			]), FEATHER_DARK)
	# Body.
	layer.draw_circle(Vector2(0, -5.0), 4.6, FEATHER_DARK)
	layer.draw_circle(Vector2(0, -5.3), 4.1, FEATHER)
	layer.draw_circle(Vector2(0, -4.0), 2.8, BELLY)
	for m: Vector2 in [Vector2(-1.0, -4.5), Vector2(1.0, -4.5), Vector2(0.0, -3.0)]:
		layer.draw_rect(Rect2(m.x - 0.5, m.y, 1.0, 1.0), BELLY_MARK)
	# Feet gripping.
	layer.draw_rect(Rect2(-2.0, -1.0, 1.0, 1.0), BEAK)
	layer.draw_rect(Rect2(1.0, -1.0, 1.0, 1.0), BEAK)

	# Head, with the swivel: part way through a turn the face slides off one side
	# and the plain back of the head is all that shows.
	var head: Vector2 = Vector2(0, -12.0)
	var turn: float = 0.0   # -1..1, face offset as it turns
	var back_of_head: bool = false
	if _perched:
		var t: float = fposmod(still_for - PERCH_AFTER_S, SWIVEL_EVERY_S)
		if t < SWIVEL_S:
			var k: float = t / SWIVEL_S
			turn = sin(k * TAU)
			back_of_head = k > 0.3 and k < 0.7
		else:
			turn = sin(still_for * 0.8) * 0.4
	layer.draw_rect(Rect2(head.x - 4.0, head.y - 5.0, 2.0, 2.0), FEATHER_DARK)   # ear tufts
	layer.draw_rect(Rect2(head.x + 2.0, head.y - 5.0, 2.0, 2.0), FEATHER_DARK)
	layer.draw_circle(head, 4.4, FEATHER_DARK)
	layer.draw_circle(head + Vector2(0, -0.3), 4.0, FEATHER)
	if back_of_head:
		layer.draw_rect(Rect2(head.x - 1.0, head.y - 1.0, 2.0, 3.0), FEATHER_DARK)
		return
	var face: Vector2 = head + Vector2(roundf(turn * 1.5), 0.0)
	var slow_blink: bool = fposmod(_elapsed, 3.8) < 0.35 if _perched else blinking(3.0)
	for side: float in [-1.0, 1.0]:
		var e: Vector2 = (face + Vector2(side * 2.0, -0.5)).round()
		layer.draw_circle(e, 1.9, EYE_RING)
		if slow_blink:
			layer.draw_rect(Rect2(e.x - 1.0, e.y, 2.0, 1.0), FEATHER_DARK)
		else:
			layer.draw_rect(Rect2(e.x - 1.0, e.y - 1.0, 2.0, 2.0), IRIS)
			layer.draw_rect(Rect2(e.x - 0.5, e.y - 0.5, 1.0, 1.0), FACE_DARK)
			layer.draw_rect(Rect2(e.x - 1.0, e.y - 1.0, 1.0, 1.0), FACE_SHINE)
	layer.draw_rect(Rect2(face.x - 0.5, face.y + 1.0, 1.0, 2.0), BEAK)
