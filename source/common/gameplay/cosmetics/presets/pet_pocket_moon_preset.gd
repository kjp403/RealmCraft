extends CompanionPreset
## POCKET MOON. A tiny moon in orbit round the wearer, passing behind them and
## coming round in front, going through its phases as it goes - new, crescent,
## full and back - with a faint orbit line and the odd star glinting nearby.
##
## PET slot - sold in the Vault's Pets tab, priced in PremiumCatalog.COSMETIC_COSTS.
##
## A MOON DOES NOT CHASE. Unlike the other companions it rides the wearer
## rigidly (a stiff spring) - the orbit is the motion, and a lagging moon would
## wobble its own orbit out of shape every time the wearer turned.
##
## THE PHASE IS REAL GEOMETRY, not a dark disc slid across a light one (that
## would spill outside the moon, and 2D has no clip here): the lit part is a
## polygon bounded by the bright limb and the terminator, an ellipse whose width
## runs from -r to +r over the cycle.

const ORBIT_CENTRE: Vector2 = Vector2(0, -24)
const ORBIT_RX: float = 22.0
const ORBIT_SQUASH: float = 0.35
const ORBIT_PERIOD_S: float = 6.0
## One full new -> full -> new cycle.
const PHASE_PERIOD_S: float = 12.0
const MOON_R: float = 4.0

const LIT: Color = Color(0.94, 0.93, 0.86)
const DARK: Color = Color(0.22, 0.24, 0.34)
const CRATER: Color = Color(0.78, 0.77, 0.72)
const GLOW: Color = Color(0.75, 0.82, 1.0)

var _angle: float = 0.0


func _build() -> void:
	stiffness = 900.0
	damping = 60.0
	# The orbit line sits on the wearer (not on the moon), split so its far half
	# passes behind the body and its near half in front.
	_add_draw_layer(_paint_orbit_far, true, 0)
	_add_draw_layer(_paint_orbit_near, true, 2)
	add_body_layer(_paint_glow, true, 0)
	add_body_layer(_paint_moon, false, 1)


func target_local(_delta: float) -> Vector2:
	_angle = _elapsed * TAU / ORBIT_PERIOD_S
	set_in_front(sin(_angle) > 0.0)
	return _orbit_point(_angle)


func _orbit_point(angle: float) -> Vector2:
	return ORBIT_CENTRE + Vector2(cos(angle) * ORBIT_RX, sin(angle) * ORBIT_RX * ORBIT_SQUASH)


func _paint_orbit_far(layer: VfxDrawLayer) -> void:
	_paint_orbit(layer, false)


func _paint_orbit_near(layer: VfxDrawLayer) -> void:
	_paint_orbit(layer, true)


## The orbit line, brightest just behind the moon and fading round the ring, so
## it reads as the path the moon just travelled.
func _paint_orbit(layer: VfxDrawLayer, near: bool) -> void:
	var steps: int = 40
	for i: int in steps:
		var a0: float = float(i) * TAU / float(steps)
		var a1: float = float(i + 1) * TAU / float(steps)
		if (sin((a0 + a1) * 0.5) > 0.0) != near:
			continue
		var behind: float = fposmod(_angle - a0, TAU) / TAU   # 0 just behind the moon
		var alpha: float = 0.35 * pow(1.0 - behind, 2.0) + 0.04
		layer.draw_line(_orbit_point(a0), _orbit_point(a1), Color(GLOW, alpha), 1.0)
	# A star glinting near the orbit now and then.
	if near:
		var cycle: float = fposmod(_elapsed, 2.7)
		if cycle < 0.35:
			var n: float = floor(_elapsed / 2.7)
			var at: Vector2 = _orbit_point(n * 2.4) + Vector2(sin(n * 5.1) * 6.0, -4.0)
			var k: float = sin(cycle / 0.35 * PI)
			layer.draw_line(at - Vector2(2.0 * k, 0.0), at + Vector2(2.0 * k, 0.0), Color(LIT, k), 1.0)
			layer.draw_line(at - Vector2(0.0, 2.0 * k), at + Vector2(0.0, 2.0 * k), Color(LIT, k), 1.0)


func _paint_glow(layer: VfxDrawLayer) -> void:
	var full: float = _fullness()
	layer.draw_circle(Vector2.ZERO, MOON_R + 5.0, Color(GLOW, 0.06 + 0.12 * full))
	layer.draw_circle(Vector2.ZERO, MOON_R + 2.0, Color(GLOW, 0.08 + 0.15 * full))


## 0 at new moon, 1 at full.
func _fullness() -> float:
	return 0.5 - 0.5 * cos(_elapsed * TAU / PHASE_PERIOD_S)


func _paint_moon(layer: VfxDrawLayer) -> void:
	layer.draw_circle(Vector2.ZERO, MOON_R, DARK)
	# Waxing lights the right limb, waning the left.
	var cycle: float = fposmod(_elapsed / PHASE_PERIOD_S, 1.0)
	var waxing: bool = cycle < 0.5
	var side: float = 1.0 if waxing else -1.0
	# Where the terminator crosses the equator, in the lit limb's frame: +r at
	# new moon (it sits ON the lit limb, nothing lit), 0 at the quarters, -r at
	# full (it has swept round to the far limb, everything lit).
	var term_x: float = cos(cycle * TAU) * MOON_R
	var points: PackedVector2Array = PackedVector2Array()
	var steps: int = 12
	for i: int in steps + 1:
		var a: float = -PI * 0.5 + PI * float(i) / float(steps)
		points.append(Vector2(cos(a) * MOON_R * side, sin(a) * MOON_R))
	for i: int in steps + 1:
		var a: float = PI * 0.5 - PI * float(i) / float(steps)
		points.append(Vector2(cos(a) * term_x * side, sin(a) * MOON_R))
	# Skip the last sliver before new moon: a crescent under a pixel wide has
	# near-coincident edges and fails to triangulate (and would not show anyway).
	if term_x < MOON_R - 0.6:
		layer.draw_colored_polygon(points, LIT)
	# Craters only show on the lit side.
	for c: Vector3 in [Vector3(-1.2, -1.0, 0.8), Vector3(1.4, 1.2, 0.7), Vector3(0.3, 2.0, 0.5)]:
		var lit_here: bool = (c.x * side) > term_x * sqrt(maxf(0.0, 1.0 - (c.y / MOON_R) * (c.y / MOON_R)))
		if lit_here:
			layer.draw_circle(Vector2(c.x, c.y), c.z, CRATER)
