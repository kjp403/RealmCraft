extends CompanionPreset
## EMBER IMP. A living flame with eyes that bounces along at the wearer's
## shoulder throwing sparks - and when they stand around long enough, it dozes
## off, shrinking to a sleepy glowing coal, then flares back up the moment they
## move.
##
## PROTOTYPE - not registered, no slot yet.
##
## The flame is three stacked polygons (red, orange, yellow core) sharing one
## teardrop shape at three sizes, with the tip flickering sideways. Additive
## glow sits behind it; the eyes are normal-blend so they stay dark.

const FOLLOW: Vector2 = Vector2(0, -34)
const FOLLOW_PX: float = 15.0
const DOZE_AFTER_S: float = 2.2
const DOZE_SCALE: float = 0.55

const RED: Color = Color(1.0, 0.28, 0.10)
const ORANGE: Color = Color(1.0, 0.58, 0.14)
const YELLOW: Color = Color(1.0, 0.92, 0.45)
const GLOW: Color = Color(1.0, 0.5, 0.15)
const EYE: Color = Color(0.25, 0.05, 0.02)

## Current size multiplier; springs toward awake (1) or dozing.
var _size: float = 1.0
var _size_vel: float = 0.0
var _dozing: bool = false
var _sparks: CPUParticles2D


func _build() -> void:
	stiffness = 90.0
	damping = 9.0
	add_body_layer(_paint_glow, true, 0)
	add_body_layer(_paint_flame, false, 1)

	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = 10
	p.lifetime = 0.6
	p.local_coords = false
	p.texture = VfxTextures.dot(4)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.position = Vector2(0, -6)
	p.direction = Vector2(0, -1)
	p.spread = 35.0
	p.gravity = Vector2(0, -25.0)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 20.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.7
	p.color_ramp = _fade_ramp(ORANGE, 1.0)
	p.material = _additive()
	body.add_child(p)
	_sparks = p


func target_local(delta: float) -> Vector2:
	_dozing = still_for >= DOZE_AFTER_S
	# Size on its own little spring, so waking up overshoots into a flare.
	var want: float = DOZE_SCALE if _dozing else 1.0
	_size_vel += ((want - _size) * 60.0 - _size_vel * 7.0) * delta
	_size += _size_vel * delta
	_sparks.emitting = not _dozing
	set_in_front(true)
	if _dozing:
		return Vector2(-10.0, -22.0 + sin(_elapsed * 1.2) * 1.0)
	return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 5.0) * 2.0)


func _paint_glow(layer: VfxDrawLayer) -> void:
	var flick: float = 0.85 + 0.15 * sin(_elapsed * 17.0) * sin(_elapsed * 7.0)
	var dim: float = 0.5 if _dozing else 1.0
	layer.draw_circle(Vector2(0, -3), 10.0 * _size, Color(GLOW, 0.10 * flick * dim))
	layer.draw_circle(Vector2(0, -3), 6.0 * _size, Color(GLOW, 0.18 * flick * dim))


func _flame(r: float, height: float, sway: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	# Bottom arc of the teardrop, then up to the flickering tip.
	for i: int in 9:
		var a: float = -0.3 + (PI + 0.6) * float(i) / 8.0
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	pts.append(Vector2(-r * 0.7 + sway * 0.3, -r * 1.2))
	pts.append(Vector2(sway, -height))
	pts.append(Vector2(r * 0.7 + sway * 0.3, -r * 1.2))
	return pts


func _paint_flame(layer: VfxDrawLayer) -> void:
	var s: float = _size
	var sway: float = sin(_elapsed * 9.0) * 1.6 + sin(_elapsed * 23.0) * 0.6
	var lick: float = 1.0 + 0.12 * sin(_elapsed * 13.0)
	if _dozing:
		sway *= 0.3
		lick = 0.8
	layer.draw_colored_polygon(_flame(5.0 * s, 13.0 * s * lick, sway * s), RED)
	layer.draw_colored_polygon(_flame(3.6 * s, 9.5 * s * lick, sway * 0.8 * s), ORANGE)
	layer.draw_colored_polygon(_flame(2.2 * s, 6.0 * s * lick, sway * 0.6 * s), YELLOW)
	for side: float in [-1.0, 1.0]:
		var at: Vector2 = Vector2(side * 1.6 * s + signf(_heading.x) * 0.5, -2.5 * s)
		if _dozing:
			layer.draw_rect(Rect2(at.x - 0.5, at.y + 0.5, 1.5, 1.0), EYE)
		else:
			layer.draw_rect(Rect2(at.x - 0.5, at.y - 0.5, 1.0, 2.0), EYE)
