class_name SanctuaryRing
extends Node2D
## Client-side visual for a planted healing circle ([HealingField] / Paladin's
## Might): a soft consecrated disc on the ground with a bright rim and a slow
## inward pulse, parented to the MAP at the drop point so it stays put.
##
## The rim is the load-bearing part. Allies have to decide from a glance whether
## they are inside the heal, and a filled disc alone reads as ambient floor decor
## once a boss's own telegraphs are painted over it — the crisp edge is what makes
## "step in" an actionable instruction. The inward pulse gives the same read for
## anyone whose attention is on their own health bar rather than the floor.

## Seconds the ring lives — matches the server field exactly.
var duration: float = 8.0
var radius: float = 70.0
var color: Color = Color(1.0, 0.88, 0.55)

## Vertical squash — the shared floor-plane look of GuardAura / the heal aura.
const GROUND_SQUASH: float = 0.55
## Pulses per second travelling inward from the rim.
const PULSE_HZ: float = 0.7

var _elapsed: float = 0.0


func _ready() -> void:
	z_index = -1 # a floor marker: bodies standing in it draw on top


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		queue_free()


func _draw() -> void:
	var life: float = clampf(_elapsed / maxf(0.01, duration), 0.0, 1.0)
	# Ease in fast, then fade over the last ~1.5s so the barrier visibly EXPIRES.
	# Players need that warning: the heal stopping with no tell reads as a bug.
	var edge: float = minf(life * 6.0, minf((1.0 - life) * (duration / 1.5), 1.0))
	if edge <= 0.0:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
	draw_circle(Vector2.ZERO, radius, Color(color.r, color.g, color.b, 0.14 * edge))
	draw_arc(
		Vector2.ZERO, radius, 0.0, TAU, 48,
		Color(color.r, color.g, color.b, 0.65 * edge), 2.0, true
	)
	# Inward pulse: one travelling ring, restarting each cycle at the rim.
	var phase: float = fposmod(_elapsed * PULSE_HZ, 1.0)
	var pulse_r: float = radius * (1.0 - phase)
	if pulse_r > 2.0:
		draw_arc(
			Vector2.ZERO, pulse_r, 0.0, TAU, 40,
			Color(color.r, color.g, color.b, 0.32 * edge * phase), 1.0, true
		)
