class_name ThemeAuraPreset
extends CosmeticPreset
## Base for the eight COLOUR-MATCHED auras - the ones that pair with a themed
## title and a body dye of the same hex. See [CosmeticThemes].
##
## WHAT THIS CLASS IS FOR is the colour, not the look. Every subclass builds its
## own layers and draws its own floor: embers do not look like petals and must
## not. What they share is that NONE of them may contain a colour literal - each
## one asks [method core] / [method accent] / [method pale] / [method deep] and
## gets the wearer's dye back. That is the whole point of the set: buy the Frost
## title, the Frost aura and the Frost dye and the three are the same colour,
## because there is only one place the colour is written down.
##
## The one thing worth sharing beyond the palette is the floor ring, because a
## ring is how an aura says "this is a set" at a glance - eight auras with eight
## unrelated ground treatments would read as eight unrelated purchases. So
## [method draw_theme_ring] is here and the interesting half of each look sits on
## top of it.
##
## Every subclass overrides [method theme] and nothing else about this file.

## Seconds per rotation of the shared floor ring. Slow and stately: a fast spin
## reads as a cooldown timer, which is a HUD idiom and wrong on a cosmetic. Same
## reasoning, same ballpark, as [AuraGoldPreset]'s.
const RING_PERIOD_S: float = 8.0

## Which [CosmeticThemes] key this aura wears. Override in every subclass; a
## preset that forgets renders white, which is loud enough that somebody reports
## it rather than shipping a beige aura nobody notices is wrong.
func theme() -> StringName:
	return &""


func core() -> Color:
	return CosmeticThemes.core(theme())


func accent() -> Color:
	return CosmeticThemes.accent(theme())


func pale() -> Color:
	return CosmeticThemes.pale(theme())


## The shadow end of the theme. NEVER hand this to an additive layer: additive
## blending of a dark colour adds nothing, so the layer costs frame time and draws
## no pixels at all.
func deep() -> Color:
	return CosmeticThemes.deep(theme())


## Where the ring is in its turn, in radians. Positive is clockwise on screen
## (screen y is down). Subclasses that place things ON the ring take this so their
## marks travel with it instead of sliding across it.
func ring_spin() -> float:
	return _elapsed * TAU / RING_PERIOD_S


## THE SHARED FLOOR RING: a wide dim wash, two arcs and a band of ticks, all in
## the theme's own colours.
##
## Call it from _draw(), first, with the ground plane already set - it does not
## set the plane itself, because a subclass usually wants to keep drawing on the
## same plane afterwards and flipping back and forth costs a transform each way.
##
## [param weight] scales every alpha, for the two quiet auras (Verdant, Lotus)
## that want the ring present but barely there.
func draw_theme_ring(weight: float = 1.0) -> void:
	var spin: float = ring_spin()
	var breathe: float = 0.5 + 0.5 * sin(_elapsed * 1.1)
	# Three stacked discs rather than one: a single low-alpha circle has a visible
	# edge, and stacked falloffs do not.
	draw_circle(Vector2.ZERO, BASE_RADIUS * 1.4, Color(deep(), (0.05 + 0.015 * breathe) * weight))
	draw_circle(Vector2.ZERO, BASE_RADIUS * 1.0, Color(core(), (0.055 + 0.02 * breathe) * weight))
	draw_circle(Vector2.ZERO, BASE_RADIUS * 0.5, Color(pale(), (0.04 + 0.02 * breathe) * weight))
	draw_arc(Vector2.ZERO, BASE_RADIUS, spin, spin + TAU, 40, Color(core(), 0.6 * weight), 1.0, false)
	draw_arc(
		Vector2.ZERO, BASE_RADIUS * 0.72, -spin * 1.3, -spin * 1.3 + TAU * 0.8, 30,
		Color(accent(), 0.4 * weight), 1.0, false
	)
	for i: int in 12:
		var angle: float = spin + float(i) * TAU / 12.0
		# Ticks catch the light as they come round the near side, which is what
		# stops a ring of identical marks reading as a progress bar.
		var lit: float = 0.4 + 0.6 * (0.5 + 0.5 * sin(angle))
		var inner: Vector2 = _ground_point(angle, BASE_RADIUS * 0.9)
		var outer: Vector2 = _ground_point(angle, BASE_RADIUS * 1.05)
		draw_line(inner, outer, Color(pale(), 0.3 * lit * weight), 1.0)
