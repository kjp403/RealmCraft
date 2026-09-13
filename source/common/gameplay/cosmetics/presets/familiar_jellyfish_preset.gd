extends CompanionPreset
## JELLYFISH. A glowing jellyfish drifting above the wearer's shoulder, swimming
## in soft pulses - the bell contracts, it surges a little, relaxes and sinks -
## with its tentacles trailing behind whichever way it moves.
##
## PROTOTYPE - not registered, no slot yet.
##
## THE PULSE DRIVES THE MOTION, not the other way round: each contraction nudges
## the follow target upward, so it rises on the squeeze and drifts down between,
## which is exactly how a real one swims. Tentacles lean against the body's
## velocity, so they stream out behind on a run and hang straight when it rests.

const FOLLOW: Vector2 = Vector2(0, -44)
const FOLLOW_PX: float = 12.0
const PULSE_S: float = 1.3

const BELL: Color = Color(0.78, 0.62, 1.0, 0.55)
const BELL_RIM: Color = Color(0.92, 0.82, 1.0)
const SPOTS: Color = Color(1.0, 0.75, 0.95, 0.8)
const TENTACLE: Color = Color(0.86, 0.72, 1.0)
const GLOW: Color = Color(0.70, 0.55, 1.0)

const TENTACLES: int = 4
const SEGMENTS: int = 6


func _build() -> void:
	stiffness = 30.0
	damping = 6.0
	add_body_layer(_paint_glow, true, 0)
	add_body_layer(_paint_tentacles, false, 1)
	add_body_layer(_paint_bell, false, 2)


## 0 relaxed, 1 fully contracted. A quick squeeze and a slow release.
func _contract() -> float:
	var cycle: float = fposmod(_elapsed / PULSE_S, 1.0)
	return pow(sin(PI * minf(1.0, cycle * 3.0)), 2.0) if cycle < 0.33 else 0.0


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	var cycle: float = fposmod(_elapsed / PULSE_S, 1.0)
	# Up on the squeeze, sinking gently through the rest of the cycle.
	var rise: float = -3.0 * sin(cycle * PI)
	return FOLLOW - _heading * FOLLOW_PX * float(is_moving()) + Vector2(0, rise)


func _paint_glow(layer: VfxDrawLayer) -> void:
	var c: float = _contract()
	layer.draw_circle(Vector2(0, -1), 11.0, Color(GLOW, 0.08 + 0.08 * c))
	layer.draw_circle(Vector2(0, -1), 6.0, Color(GLOW, 0.12 + 0.10 * c))


func _paint_bell(layer: VfxDrawLayer) -> void:
	var c: float = _contract()
	var w: float = 6.5 * (1.0 - 0.18 * c)
	var h: float = 5.5 * (1.0 + 0.2 * c)
	var pts: PackedVector2Array = PackedVector2Array()
	for i: int in 13:
		var a: float = PI + PI * float(i) / 12.0
		pts.append(Vector2(cos(a) * w, sin(a) * h + 1.0))
	# A scalloped skirt along the bottom edge.
	for i: int in 7:
		var x: float = w - float(i) * (w * 2.0) / 6.0
		pts.append(Vector2(x, 1.0 + (1.0 if i % 2 == 1 else 0.0)))
	layer.draw_colored_polygon(pts, BELL)
	var rim: PackedVector2Array = pts.slice(0, 13)
	layer.draw_polyline(rim, BELL_RIM, 1.0)
	layer.draw_rect(Rect2(-2.0, -h * 0.5, 1.0, 1.0), SPOTS)
	layer.draw_rect(Rect2(1.0, -h * 0.7, 1.0, 1.0), SPOTS)
	layer.draw_rect(Rect2(-0.5, -h * 0.2, 1.0, 1.0), SPOTS)


func _paint_tentacles(layer: VfxDrawLayer) -> void:
	var s: float = maxf(0.001, global_scale.x)
	# Lean against velocity: they trail behind the direction of travel.
	var drag: Vector2 = -body_velocity() / s * 0.035
	for t: int in TENTACLES:
		var base_x: float = lerpf(-4.0, 4.0, float(t) / float(TENTACLES - 1))
		var pts: PackedVector2Array = PackedVector2Array()
		for j: int in SEGMENTS + 1:
			var k: float = float(j) / float(SEGMENTS)
			var wave: float = sin(_elapsed * 3.0 - float(j) * 0.7 + float(t) * 1.3) * 1.2 * k
			pts.append(Vector2(base_x * (1.0 - 0.3 * k) + wave + drag.x * k * k * 6.0, 2.0 + float(j) * 2.2 + drag.y * k * 3.0))
		layer.draw_polyline(pts, Color(TENTACLE, 0.75), 1.0)
