extends GroundCompanionPreset
## FROG. A plump green frog that follows the wearer in big slow leaps, legs
## trailing out behind on every jump. When they stop it sits beside them while a
## fly buzzes round its head - until its tongue shoots out, the fly is gone, and
## it gulps happily. Then another fly turns up.
##
## PROTOTYPE - not registered, no slot yet.

const SKIN: Color = Color(0.40, 0.76, 0.34)
const SKIN_DARK: Color = Color(0.24, 0.52, 0.22)
const BELLY: Color = Color(0.86, 0.94, 0.62)
const EYE_BULB: Color = Color(0.52, 0.86, 0.44)
const TONGUE: Color = Color(1.0, 0.46, 0.58)
const FLY: Color = Color(0.18, 0.18, 0.22)
const FLY_WING: Color = Color(0.86, 0.92, 1.0, 0.7)
const IDLE_AFTER_S: float = 0.8
const CATCH_EVERY_S: float = 4.0
const TONGUE_S: float = 0.22
const GULP_S: float = 0.6
const FLY_BACK_S: float = 1.4


func _build() -> void:
	hop_peak = 9.0
	hop_rate = 1.8
	stiffness = 30.0
	add_body_layer(_paint_frog, false, 0)
	add_body_layer(_paint_fly, false, 1)


## Where the fly is, in body space, or null while it has been eaten.
func _fly_pos() -> Variant:
	if still_for < IDLE_AFTER_S:
		return null
	var t: float = fposmod(still_for - IDLE_AFTER_S, CATCH_EVERY_S)
	var eaten_at: float = CATCH_EVERY_S - FLY_BACK_S - GULP_S - TONGUE_S
	if t > eaten_at + TONGUE_S and t < CATCH_EVERY_S - 0.01:
		return null
	return _fly_path()


## The fly's loop round the frog's head, whether or not it has been eaten - the
## tongue aims here, so it always hits where the fly actually is.
func _fly_path() -> Vector2:
	var a: float = _elapsed * 4.0
	return Vector2(cos(a) * 8.0 + sin(_elapsed * 17.0) * 0.8, -15.0 + sin(a * 2.0) * 2.5)


func _paint_fly(layer: VfxDrawLayer) -> void:
	var p: Variant = _fly_pos()
	if p == null:
		return
	var at: Vector2 = (p as Vector2).round()
	var beat: bool = fposmod(_elapsed * 30.0, 1.0) < 0.5
	layer.draw_rect(Rect2(at.x - 1.0, at.y - (2.0 if beat else 1.0), 1.0, 1.0), FLY_WING)
	layer.draw_rect(Rect2(at.x + 1.0, at.y - (2.0 if beat else 1.0), 1.0, 1.0), FLY_WING)
	layer.draw_rect(Rect2(at.x - 1.0, at.y, 2.0, 1.0), FLY)


func _paint_frog(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 6.0)
	var airborne: bool = is_hopping() and hop_height > 1.0
	# Back legs: tucked while sitting, stretched down and back mid-leap.
	if airborne:
		layer.draw_rect(Rect2(-5.0, -2.0, 2.0, 4.0), SKIN_DARK)
		layer.draw_rect(Rect2(3.0, -2.0, 2.0, 4.0), SKIN_DARK)
	else:
		layer.draw_rect(Rect2(-6.0, -2.0, 3.0, 2.0), SKIN_DARK)
		layer.draw_rect(Rect2(3.0, -2.0, 3.0, 2.0), SKIN_DARK)
	# Body: squat and round.
	var gulp: float = 0.0
	var tongue_k: float = -1.0
	if still_for >= IDLE_AFTER_S:
		var t: float = fposmod(still_for - IDLE_AFTER_S, CATCH_EVERY_S)
		var shoot_at: float = CATCH_EVERY_S - FLY_BACK_S - GULP_S - TONGUE_S
		if t >= shoot_at and t < shoot_at + TONGUE_S:
			tongue_k = (t - shoot_at) / TONGUE_S
		elif t >= shoot_at + TONGUE_S and t < shoot_at + TONGUE_S + GULP_S:
			gulp = sin((t - shoot_at - TONGUE_S) / GULP_S * PI)
	layer.draw_circle(Vector2(0.0, -4.0), 5.2 + gulp * 0.6, SKIN_DARK)
	layer.draw_circle(Vector2(0.0, -4.3), 4.7 + gulp * 0.6, SKIN)
	layer.draw_circle(Vector2(0.0, -2.8), 2.8 + gulp, BELLY)
	# Eye bulbs on top, with shiny pupils.
	for side: float in [-1.0, 1.0]:
		var bulb: Vector2 = Vector2(side * 2.8, -8.5)
		layer.draw_circle(bulb, 2.1, SKIN_DARK)
		layer.draw_circle(bulb + Vector2(0, -0.2), 1.7, EYE_BULB)
	var look: Vector2 = Vector2.ZERO
	var fly: Variant = _fly_pos()
	if fly != null:
		look = ((fly as Vector2) - Vector2(0, -8.5)).normalized() * 0.6
	draw_eyes(layer, Vector2(0.0, -8.5), 2.8, look, blinking(3.6, 1.3), 2)
	# Mouth: a wide line, and a blush.
	layer.draw_rect(Rect2(-2.5, -5.5, 5.0, 1.0), SKIN_DARK)
	draw_blush(layer, Vector2(0.0, -6.0), 4.0)
	# The tongue: out to where the fly is, and back.
	if tongue_k >= 0.0:
		var target: Vector2 = _fly_path()
		var reach: float = sin(tongue_k * PI)
		layer.draw_line(Vector2(0.0, -5.0), Vector2(0.0, -5.0).lerp(target, reach), TONGUE, 1.0)
		layer.draw_circle(Vector2(0.0, -5.0).lerp(target, reach), 1.0, TONGUE)
