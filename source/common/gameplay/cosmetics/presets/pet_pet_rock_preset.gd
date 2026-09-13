extends GroundCompanionPreset
## PET ROCK. It is a rock. It has googly eyes and a very small top hat. It
## follows the wearer in dignified little hops, its googly eyes rattling around,
## and when they stop it... sits there. Being a rock. Pupils settling slowly to
## the bottom of its eyes.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## THE GOOGLY EYES ARE REAL PHYSICS, which is the whole joke: each pupil is a
## mass on a spring inside its eye, pulled down by gravity and flung by the
## body's acceleration, so every hop and stop rattles them for real.

const STONE: Color = Color(0.56, 0.56, 0.60)
const STONE_DARK: Color = Color(0.36, 0.36, 0.40)
const STONE_LIGHT: Color = Color(0.74, 0.74, 0.78)
const EYE_WHITE: Color = Color(1.0, 1.0, 1.0)
const HAT: Color = Color(0.14, 0.12, 0.16)
const BAND: Color = Color(0.80, 0.24, 0.30)
const EYE_R: float = 2.2
const PUPIL_TRAVEL: float = 1.2

var _pupil: Vector2 = Vector2.ZERO
var _pupil_vel: Vector2 = Vector2.ZERO
var _last_vel: Vector2 = Vector2.ZERO


func _build() -> void:
	hop_peak = 3.0
	add_body_layer(_paint_rock, false, 0)


func _tick(delta: float) -> void:
	super(delta)
	var s: float = maxf(0.001, global_scale.x)
	var vel: Vector2 = body_velocity() / s + Vector2(0.0, -hop_height * 10.0)
	var accel: Vector2 = (vel - _last_vel) / maxf(delta, 0.001)
	_last_vel = vel
	# Gravity down, a kick opposite the acceleration, a loose spring to centre.
	var force: Vector2 = Vector2(0.0, 30.0) - accel * 0.02 - _pupil * 25.0 - _pupil_vel * 2.5
	_pupil_vel += force * delta
	_pupil += _pupil_vel * delta
	if _pupil.length() > PUPIL_TRAVEL:
		# Bounces off the inside of the eye.
		_pupil = _pupil.normalized() * PUPIL_TRAVEL
		_pupil_vel = _pupil_vel.bounce(_pupil.normalized()) * 0.5


func _paint_rock(layer: VfxDrawLayer) -> void:
	apply_hop(layer, 6.0)
	# The rock: lumpy, shaded, speckled.
	layer.draw_circle(Vector2(-1.0, -4.0), 4.8, STONE_DARK)
	layer.draw_circle(Vector2(2.0, -3.5), 4.2, STONE_DARK)
	layer.draw_circle(Vector2(-1.3, -4.4), 4.2, STONE)
	layer.draw_circle(Vector2(1.7, -3.9), 3.6, STONE)
	layer.draw_rect(Rect2(-4.0, -7.0, 2.0, 1.0), STONE_LIGHT)
	for sp: Vector2 in [Vector2(2.0, -2.0), Vector2(-3.0, -2.0), Vector2(0.0, -1.0)]:
		layer.draw_rect(Rect2(sp.x, sp.y, 1.0, 1.0), STONE_DARK)
	# Googly eyes.
	for side: float in [-1.0, 1.0]:
		var e: Vector2 = Vector2(side * 2.2 - 0.3, -5.0)
		layer.draw_circle(e, EYE_R + 0.5, STONE_DARK)
		layer.draw_circle(e, EYE_R, EYE_WHITE)
		layer.draw_circle(e + _pupil, 1.0, FACE_DARK)
	# The very small top hat, tipped slightly.
	layer.draw_rect(Rect2(-3.5, -10.0, 6.0, 1.0), HAT)
	layer.draw_rect(Rect2(-2.5, -14.0, 4.0, 4.0), HAT)
	layer.draw_rect(Rect2(-2.5, -11.0, 4.0, 1.0), BAND)
