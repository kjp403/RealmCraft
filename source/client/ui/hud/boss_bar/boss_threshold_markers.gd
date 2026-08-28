extends Control
## Permanent phase notches drawn over the boss health bar.
##
## A scripted fight like Ossuran is gated at 75% and 50%, and a player who cannot
## SEE those gates experiences the fight as arbitrary — damage stops working and
## nobody knows why. Drawing them on the bar from the first second turns the
## encounter's structure into something you can read at a glance: two walls
## ahead of you, and you can watch the fill approach one.
##
## Purely presentational and entirely client-side. It never decides anything —
## [BossStateMachine] owns when a gate actually fires. The notches come from
## [member EnemyTypeResource.hp_thresholds], so any future boss gets them by
## declaring the fractions on its resource and changing no code.
##
## Sits over the bars with `mouse_filter = MOUSE_FILTER_IGNORE`, so it is a pure
## overlay and never eats a click.

## Notch geometry. Two texels wide so it survives the game's integer scaling
## without turning into a grey smear.
const NOTCH_WIDTH: float = 2.0
## How far the tick overhangs the bar, top and bottom.
const OVERHANG: float = 3.0

## Ahead of the fill — this gate is still to come.
const COLOR_PENDING: Color = Color(1.0, 0.86, 0.45, 0.95)
## Already passed. Dimmed rather than removed, so the bar keeps a record of the
## fight's progress instead of silently losing a landmark.
const COLOR_CROSSED: Color = Color(0.55, 0.52, 0.48, 0.5)
## Thin dark edging so a notch stays legible on both the bright fill and the
## empty track behind it.
const COLOR_EDGE: Color = Color(0.05, 0.04, 0.06, 0.8)

## HP fractions to mark, 0-1.
var thresholds: Array[float] = []
## Current HP fraction, used only to decide pending vs crossed.
var fill_fraction: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Replace the marked fractions. Out-of-range values are dropped rather than
## clamped — a 0 or 1 "threshold" would draw a notch on the bar's own end cap,
## which reads as a rendering fault, not a phase gate.
func set_thresholds(values: Array) -> void:
	thresholds.clear()
	for value: float in values:
		if value > 0.0 and value < 1.0:
			thresholds.append(value)
	queue_redraw()


## Tell the overlay where the fill currently is, so notches behind it dim.
func set_fill_fraction(value: float) -> void:
	var next: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(next, fill_fraction):
		return
	fill_fraction = next
	queue_redraw()


func _draw() -> void:
	if thresholds.is_empty():
		return
	var full: Vector2 = size
	if full.x <= 0.0 or full.y <= 0.0:
		return

	for fraction: float in thresholds:
		# The bar fills left to right, so a fraction maps straight to an x.
		# Rounded to a whole pixel: a notch on a half-pixel is what makes a
		# crisp 2px line render as a 3px blur.
		var x: float = round(full.x * fraction)
		var crossed: bool = fill_fraction <= fraction
		var color: Color = COLOR_CROSSED if crossed else COLOR_PENDING

		var top: float = -OVERHANG
		var height: float = full.y + OVERHANG * 2.0
		# Edging first, then the notch centred inside it.
		draw_rect(
			Rect2(x - NOTCH_WIDTH * 0.5 - 1.0, top, NOTCH_WIDTH + 2.0, height),
			COLOR_EDGE,
			true
		)
		draw_rect(
			Rect2(x - NOTCH_WIDTH * 0.5, top, NOTCH_WIDTH, height),
			color,
			true
		)
