extends CompanionPreset
## BUMBLEBEE. A round fuzzy bumblebee that buzzes along after the wearer in a
## jittery little flight. When they stop it does its waggle dance beside them -
## a figure-eight - leaving a dotted flight path hanging in the air behind it.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## The dotted path is world-space and drawn BELOW the wearer (see
## [method CompanionPreset.set_in_front] for why a top_level layer needs a z
## strictly under theirs), so a loop that crosses the player never covers them.

const FOLLOW: Vector2 = Vector2(0, -34)
const FOLLOW_PX: float = 15.0
const IDLE_AFTER_S: float = 0.8
const DOT_EVERY_S: float = 0.06
const DOT_LIFE_S: float = 1.1

const FUZZ: Color = Color(1.0, 0.80, 0.20)
const FUZZ_LIGHT: Color = Color(1.0, 0.93, 0.55)
const STRIPE: Color = Color(0.20, 0.14, 0.10)
const WING: Color = Color(0.90, 0.96, 1.0, 0.65)
const PATH: Color = Color(1.0, 0.95, 0.70)

var _facing: float = 1.0
## World-space path dots: {"p", "t"}.
var _dots: Array[Dictionary] = []
var _since_dot: float = 0.0


func _build() -> void:
	stiffness = 95.0
	damping = 12.0
	var path: VfxDrawLayer = _add_draw_layer(_paint_path, false, -2)
	path.top_level = true
	add_body_layer(_paint_bee, false, 0)


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	if absf(_heading.x) > 0.2:
		_facing = signf(_heading.x)
	if still_for < IDLE_AFTER_S:
		var buzz: Vector2 = Vector2(sin(_elapsed * 23.0), cos(_elapsed * 19.0)) * 1.5
		return FOLLOW - _heading * FOLLOW_PX + buzz
	# The waggle dance: a figure-eight beside the wearer.
	var a: float = (still_for - IDLE_AFTER_S) * 3.0
	return Vector2(-15.0 * _facing + sin(a) * 8.0, -34.0 + sin(a * 2.0) * 3.0)


func _tick(delta: float) -> void:
	super(delta)
	_since_dot += delta
	if _since_dot >= DOT_EVERY_S and still_for >= IDLE_AFTER_S:
		_since_dot = 0.0
		_dots.append({"p": body.global_position, "t": 0.0})
	for i: int in range(_dots.size() - 1, -1, -1):
		_dots[i]["t"] += delta
		if _dots[i]["t"] >= DOT_LIFE_S:
			_dots.remove_at(i)


func _paint_path(layer: VfxDrawLayer) -> void:
	var s: float = global_scale.x
	for d: Dictionary in _dots:
		var k: float = 1.0 - float(d["t"]) / DOT_LIFE_S
		layer.draw_rect(Rect2((d["p"] as Vector2) - Vector2(0.5, 0.5) * s, Vector2.ONE * s), Color(PATH, 0.6 * k))


func _paint_bee(layer: VfxDrawLayer) -> void:
	# Mirror by which way it is flying: during the dance, by the dance's own motion.
	var f: float = _facing
	if still_for >= IDLE_AFTER_S and absf(body_velocity().x) > 1.0:
		f = signf(body_velocity().x)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2(f, 1.0))
	# Wings: a blur of two ellipses flickering size every frame.
	var beat: float = 0.6 + 0.4 * absf(sin(_elapsed * 60.0))
	layer.draw_circle(Vector2(-1.5, -4.0), 2.4 * beat, WING)
	layer.draw_circle(Vector2(1.0, -4.5), 2.0 * beat, WING)
	# Fuzzy body with two stripes and a stinger.
	layer.draw_rect(Rect2(-5.0, -0.5, 1.0, 1.0), STRIPE)
	layer.draw_circle(Vector2.ZERO, 3.4, STRIPE)
	layer.draw_circle(Vector2(-0.2, -0.2), 3.0, FUZZ)
	layer.draw_rect(Rect2(-2.0, -2.5, 1.0, 5.0), STRIPE)
	layer.draw_rect(Rect2(0.5, -2.8, 1.0, 5.6), STRIPE)
	layer.draw_rect(Rect2(-1.0, -2.5, 1.0, 1.0), FUZZ_LIGHT)
	# Head, antennae, a shiny eye and a blush.
	var head: Vector2 = Vector2(3.8, -0.5)
	layer.draw_line(head + Vector2(0.0, -1.5), head + Vector2(1.0, -4.0), STRIPE, 1.0)
	layer.draw_line(head + Vector2(1.0, -1.5), head + Vector2(2.5, -3.5), STRIPE, 1.0)
	layer.draw_circle(head, 2.2, STRIPE)
	var eye: Vector2 = (head + Vector2(0.5, -0.5)).round()
	if not blinking(3.0, 2.0):
		layer.draw_rect(Rect2(eye.x, eye.y - 1.0, 1.0, 1.0), FACE_SHINE)
	layer.draw_rect(Rect2(head.x - 1.0, head.y + 1.0, 1.0, 1.0), FACE_BLUSH)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
