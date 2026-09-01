class_name MagmaFissure
extends Node2D
## One split in the floor left by [TrailInfernalChasmPreset]: a jagged crack with
## branches, molten when it opens and cooled to black char by the time it fades.
##
## The crack is GENERATED, once, at spawn - a random walk along the direction the
## wearer was moving, plus a branch or two - and then never changes shape. That
## split is deliberate: the geometry is rolled once so the crack stays absolutely
## still in the world (a crack that re-rolls looks like it is wriggling), while
## everything about its APPEARANCE is a function of age.
##
## What sells it is that it COOLS rather than fades. A crack that simply loses
## alpha reads as a decal being switched off; running the colour down a real
## temperature ramp - white, yellow, orange, deep red, black - means the glow dies
## long before the char does, so what is left behind at the end is a scar on the
## floor and not a hole in the rendering.
##
## Not squashed onto the ground plane, unlike the aura rings. Those draw a
## conceptual circle around the wearer and have to be flattened to lie down; this
## follows the wearer's actual world-space movement vector, which is already in
## the plane of the floor. Squashing it would pull the crack off the path.

## Seconds from opening to gone.
var life: float = 2.0
## Unit direction the wearer was moving; the crack runs along it.
var heading: Vector2 = Vector2.RIGHT
## Length of the main split in px.
var length: float = 30.0

## Temperature ramp, hottest first. Sampled by age - see _heat_color.
const HEAT: Array[Color] = [
	Color(1.00, 0.97, 0.82), # white hot
	Color(1.00, 0.78, 0.22), # yellow
	Color(1.00, 0.42, 0.06), # orange
	Color(0.62, 0.10, 0.03), # deep red
	Color(0.09, 0.06, 0.06), # char
]
## Seconds the crack takes to tear open. Short and eased, so it SPLITS rather
## than appearing at full length.
const OPEN_S: float = 0.16

## Main split first, then branches.
var _cracks: Array[PackedVector2Array] = []
var _glow: VfxDrawLayer
var _elapsed: float = 0.0


func _ready() -> void:
	_build_cracks()
	# The molten core has to ADD light while the char has to DARKEN the floor, and
	# one CanvasItem gets one blend mode. Same split the Runebound rings make, for
	# the same reason - see VfxDrawLayer.
	_glow = VfxDrawLayer.new()
	_glow.painter = _paint_glow
	var additive: CanvasItemMaterial = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = additive
	add_child(_glow)


## A random walk along the heading, with branches forking off it. Walking rather
## than sampling a curve is what makes the joints hard: rock splits in short
## straights and sharp corners, and any smooth interpolation reads as a river.
func _build_cracks() -> void:
	var side: Vector2 = Vector2(-heading.y, heading.x)
	var main: PackedVector2Array = PackedVector2Array()
	const STEPS: int = 8
	var drift: float = 0.0
	for i: int in STEPS + 1:
		var k: float = float(i) / float(STEPS)
		# The walk accumulates, so the crack wanders somewhere instead of
		# oscillating around the centre line like a zigzag border.
		drift += randf_range(-2.2, 2.2)
		# Pinch both ends toward the line: a crack tapers to a point where it runs
		# out of energy, and a blunt end reads as a drawn stroke.
		var pinch: float = sin(k * PI)
		main.append(heading * (length * (k - 0.5)) + side * drift * pinch)
	_cracks.append(main)

	for _b: int in randi_range(1, 2):
		var root: int = randi_range(2, STEPS - 2)
		var branch: PackedVector2Array = PackedVector2Array()
		branch.append(main[root])
		var away: Vector2 = (side * (1.0 if randf() < 0.5 else -1.0)).rotated(randf_range(-0.5, 0.5))
		var run: float = length * randf_range(0.22, 0.42)
		for j: int in 3:
			var k: float = float(j + 1) / 3.0
			branch.append(main[root] + away * run * k + side * randf_range(-1.4, 1.4))
		_cracks.append(branch)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= life:
		queue_free()
		return
	queue_redraw()
	_glow.queue_redraw()


## 0 at spawn, 1 at death.
func _age() -> float:
	return clampf(_elapsed / maxf(0.01, life), 0.0, 1.0)


## How far the crack has torn open, 0..1.
func _open() -> float:
	return clampf(_elapsed / OPEN_S, 0.0, 1.0)


## Sample the temperature ramp. Front-loaded (age squared) because real cooling is
## fast at first: the crack should lose its white in a moment and then sit glowing
## dull red for most of its life.
func _heat_color(bias: float) -> Color:
	var heat: float = clampf(_age() * _age() * 1.25 + bias, 0.0, 1.0)
	var span: float = heat * float(HEAT.size() - 1)
	var index: int = clampi(int(span), 0, HEAT.size() - 2)
	return HEAT[index].lerp(HEAT[index + 1], span - float(index))


## The char: a dark, widening split in the stone. Drawn mixed, so it genuinely
## darkens the tiles rather than glowing on them.
func _draw() -> void:
	var open: float = _open()
	if open <= 0.0:
		return
	# Holds solid, then goes in the last quarter - the scar outlives the light.
	var alpha: float = 1.0 - smoothstep(0.72, 1.0, _age())
	for crack: PackedVector2Array in _cracks:
		var shown: PackedVector2Array = _partial(crack, open)
		if shown.size() < 2:
			continue
		draw_polyline(shown, Color(HEAT[HEAT.size() - 1], 0.85 * alpha), 3.4)


## The molten core inside the split, on the additive layer.
func _paint_glow(layer: Node2D) -> void:
	var open: float = _open()
	if open <= 0.0:
		return
	var age: float = _age()
	var col: Color = _heat_color(0.0)
	# The light dies well before the crack does. Squared so it drops away quickly
	# once cooling starts rather than dimming linearly to nothing.
	var lit: float = pow(1.0 - age, 2.2)
	if lit <= 0.01:
		return
	for i: int in _cracks.size():
		var shown: PackedVector2Array = _partial(_cracks[i], open)
		if shown.size() < 2:
			continue
		# Branches run cooler than the main split: they are thinner, so they lose
		# their heat first, and that difference is most of the depth in the shape.
		var branch_falloff: float = 1.0 if i == 0 else 0.55
		layer.draw_polyline(shown, Color(col, 0.55 * lit * branch_falloff), 2.0)
		layer.draw_polyline(shown, Color(HEAT[0], 0.75 * lit * branch_falloff), 0.8)
	# A pool of heat over the middle of the main split, so the crack lights the
	# floor around itself instead of being a bright line on a dark tile.
	var mid: Vector2 = _cracks[0][_cracks[0].size() / 2]
	layer.draw_circle(mid, 7.0 + 4.0 * lit, Color(col, 0.10 * lit))


## The first [param fraction] of a polyline, so the crack can tear open along its
## own length instead of appearing all at once.
func _partial(points: PackedVector2Array, fraction: float) -> PackedVector2Array:
	if fraction >= 1.0:
		return points
	var keep: int = maxi(2, int(ceil(float(points.size()) * fraction)))
	return points.slice(0, keep)
