extends CompanionPreset
## MOTH. A soft little moth that flutters along behind the wearer and, when they
## stand still for a moment, lands on top of their head and slowly fans its wings.
## Take a step and it startles off again.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## LANDING ON THE HEAD NEEDS THE HEAD. Skins are different heights, so the perch
## is MEASURED rather than assumed ([method CompanionPreset.wearer_head_top]). A fixed
## height would perch the moth inside a tall skin's hat or floating over a short
## one.
##
##   WINGS    two drawn wing pairs; a fast flap in flight, a slow fan when perched.
##   FLIGHT   a wandering loop on top of the follow target, so it flutters rather
##            than gliding on rails.

const FOLLOW: Vector2 = Vector2(-14, -30)
const LAND_AFTER_S: float = 1.2
## The flight path's wander, in px, and how fast it wanders.
const WANDER_PX: float = 5.0

const WING: Color = Color(0.93, 0.88, 0.76)
const WING_EDGE: Color = Color(0.72, 0.64, 0.52)
const SPOT: Color = Color(0.55, 0.46, 0.62)
const BODY: Color = Color(0.36, 0.28, 0.22)

var _perched: bool = false
var _facing: float = 1.0



func _build() -> void:
	stiffness = 70.0
	damping = 10.0
	var art: VfxDrawLayer = add_body_layer(_paint_moth, false, 0)
	# Drawn at 1x it is nine pixels wide and reads as a speck at game zoom.
	art.scale = Vector2(1.4, 1.4)


func target_local(_delta: float) -> Vector2:
	_perched = still_for >= LAND_AFTER_S
	if _perched:
		set_in_front(true)
		# A perch has to be exact: stiffen the spring so it settles on the head
		# instead of bobbing round it.
		stiffness = 160.0
		damping = 22.0
		return Vector2(0.0, wearer_head_top() - 3.0)
	stiffness = 70.0
	damping = 10.0
	if absf(_heading.x) > 0.2:
		_facing = signf(_heading.x)
	set_in_front(true)
	var wander: Vector2 = Vector2(sin(_elapsed * 3.1) + sin(_elapsed * 7.3) * 0.4, cos(_elapsed * 4.3) * 0.8) * WANDER_PX
	return Vector2(FOLLOW.x * _facing, FOLLOW.y) + wander


func _paint_moth(layer: VfxDrawLayer) -> void:
	# Flap: fast and full in flight, a slow half-fan when perched.
	var flap: float
	if _perched:
		flap = 0.55 + 0.35 * sin(_elapsed * 2.2)
	else:
		flap = 0.5 + 0.5 * sin(_elapsed * 22.0)
	var span: float = lerpf(1.0, 4.0, flap)
	for side: float in [-1.0, 1.0]:
		# Forewing and hindwing: ellipses squashed by the flap, drawn as stacked
		# circles so they stay crisp at this size.
		var fore: Vector2 = Vector2(side * span, -1.0)
		var hind: Vector2 = Vector2(side * span * 0.75, 1.0)
		layer.draw_circle(fore, 2.2, WING_EDGE)
		layer.draw_circle(fore, 1.7, WING)
		layer.draw_circle(hind, 1.6, WING_EDGE)
		layer.draw_circle(hind, 1.1, WING)
		if flap > 0.45:
			layer.draw_rect(Rect2(fore.round() - Vector2(0.5, 0.5), Vector2(1, 1)), SPOT)
	layer.draw_rect(Rect2(Vector2(-0.5, -2.0), Vector2(1.0, 4.0)), BODY)
	# Antennae.
	layer.draw_line(Vector2(0.0, -2.0), Vector2(-1.5, -4.0), BODY, 1.0)
	layer.draw_line(Vector2(0.0, -2.0), Vector2(1.5, -4.0), BODY, 1.0)
