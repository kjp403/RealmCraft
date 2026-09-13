extends GroundCompanionPreset
## HAMSTER BALL. A hamster running flat out inside a clear ball that rolls after
## the wearer. When they stop, the ball rolls to a halt, the hamster sits down,
## and nibbles a seed with its cheeks puffing up.
##
## PROTOTYPE - not registered, no slot yet.
##
## The roll is REAL: the ball's seam rotates by distance travelled over its
## radius, so it turns at exactly the speed it moves and never skates. The
## hamster stays upright at the bottom of the ball, as it would.

const BALL_R: float = 7.5
const BALL: Color = Color(0.70, 0.88, 1.0, 0.22)
const BALL_EDGE: Color = Color(0.82, 0.94, 1.0, 0.75)
const SHINE: Color = Color(1.0, 1.0, 1.0, 0.85)
const FUR: Color = Color(0.94, 0.66, 0.36)
const FUR_LIGHT: Color = Color(1.0, 0.92, 0.80)
const FUR_DARK: Color = Color(0.70, 0.44, 0.20)
const SEED: Color = Color(0.40, 0.30, 0.20)
const SIT_AFTER_S: float = 0.6

var _roll: float = 0.0
var _roll_last_x: float = 0.0
var _roll_primed: bool = false


func _build() -> void:
	hop_peak = 0.0
	add_body_layer(_paint_back, false, 0)
	add_body_layer(_paint_hamster, false, 1)
	add_body_layer(_paint_front, false, 2)


func _tick(delta: float) -> void:
	super(delta)
	var x: float = body.global_position.x / maxf(0.001, global_scale.x)
	if _roll_primed:
		_roll += (x - _roll_last_x) / BALL_R
	_roll_last_x = x
	_roll_primed = true


func _centre() -> Vector2:
	return Vector2(0.0, -BALL_R)


func _paint_back(layer: VfxDrawLayer) -> void:
	apply_hop(layer, BALL_R)
	# The shadow was drawn by apply_hop; the ball itself never squashes.
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	layer.draw_circle(_centre(), BALL_R, BALL)
	# Seams on the ball, turning with the roll.
	for i: int in 3:
		var a: float = _roll + float(i) * TAU / 3.0
		var d: Vector2 = Vector2(cos(a), sin(a)) * (BALL_R - 0.5)
		layer.draw_line(_centre() - d * 0.15, _centre() + d, Color(BALL_EDGE, 0.35), 1.0)


func _paint_hamster(layer: VfxDrawLayer) -> void:
	var sitting: bool = still_for >= SIT_AFTER_S
	layer.draw_set_transform(Vector2(0.0, -1.0), 0.0, Vector2(facing, 1.0))
	var run: float = sin(_elapsed * 22.0) if not sitting else 0.0
	if not sitting:
		layer.draw_rect(Rect2(-2.5 + run, -1.5, 1.0, 1.0), FUR_DARK)
		layer.draw_rect(Rect2(1.5 - run, -1.5, 1.0, 1.0), FUR_DARK)
	# Body: leaning forward while running, round and upright while sitting.
	var body_c: Vector2 = Vector2(0.5 if not sitting else 0.0, -4.0 - (0.5 if sitting else 0.0))
	layer.draw_circle(body_c, 3.6, FUR_DARK)
	layer.draw_circle(body_c + Vector2(-0.2, -0.3), 3.2, FUR)
	layer.draw_circle(body_c + Vector2(0.6, 1.0), 2.0, FUR_LIGHT)
	var head: Vector2 = body_c + Vector2(2.2 if not sitting else 1.0, -3.0)
	layer.draw_circle(head, 2.6, FUR)
	# Ears.
	layer.draw_rect(Rect2(head.x - 2.0, head.y - 3.0, 1.0, 1.0), FUR_DARK)
	layer.draw_rect(Rect2(head.x + 0.5, head.y - 3.0, 1.0, 1.0), FUR_DARK)
	# Cheeks puff while it nibbles.
	var chew: float = absf(sin(still_for * 9.0)) if sitting else 0.0
	layer.draw_circle(head + Vector2(1.0, 1.0), 1.2 + chew * 0.7, FUR_LIGHT)
	var eye: Vector2 = (head + Vector2(0.5, -1.0)).round()
	if blinking(2.7, 0.3):
		layer.draw_rect(Rect2(eye.x, eye.y, 1.0, 1.0), FACE_DARK)
	else:
		layer.draw_rect(Rect2(eye.x, eye.y - 1.0, 1.0, 2.0), FACE_DARK)
	layer.draw_rect(Rect2(head.x + 2.0, head.y, 1.0, 1.0), FACE_BLUSH)
	if sitting:
		# Holding a seed up to its mouth.
		layer.draw_rect(Rect2(head.x + 1.5, head.y + 1.5 - chew, 1.0, 2.0), SEED)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_front(layer: VfxDrawLayer) -> void:
	# The front of the ball: rim and a curved glint, over the hamster.
	layer.draw_arc(_centre(), BALL_R, 0.0, TAU, 28, BALL_EDGE, 1.0)
	layer.draw_arc(_centre() + Vector2(-0.5, -0.5), BALL_R - 2.0, PI * 1.1, PI * 1.45, 6, SHINE, 1.0)
