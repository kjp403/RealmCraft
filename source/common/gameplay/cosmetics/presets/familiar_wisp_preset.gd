extends CompanionPreset
## WISP FAMILIAR. A small glowing companion with eyes: it trails at the wearer's
## shoulder while they move, looks where they are going, blinks, and drifts in a
## lazy orbit round them when they stand still.
##
## PROTOTYPE - not registered, no slot yet.
##
##   ORB     additive glow on the companion body.
##   EYES    normal-blend pips over the glow, offset toward where it is looking.
##   MOTES   world-space sparkles shed as it flies.

const SHOULDER: Vector2 = Vector2(0, -34)
const FOLLOW_PX: float = 16.0
const ORBIT_RX: float = 20.0
## Idle orbit sits above head height so the near pass clears the face.
const ORBIT_CENTRE: Vector2 = Vector2(0, -40)
const ORBIT_PERIOD_S: float = 5.5
const IDLE_BEFORE_ORBIT_S: float = 0.8
const BLINK_PERIOD_S: float = 3.1

const GLOW: Color = Color(0.45, 0.85, 1.0)
const CORE: Color = Color(0.92, 0.99, 1.0)
const EYE: Color = Color(0.05, 0.10, 0.20)

var _look: Vector2 = Vector2.RIGHT


func _build() -> void:
	add_body_layer(_paint_orb, true, 0)
	add_body_layer(_paint_eyes, false, 1)

	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = 12
	p.lifetime = 0.7
	p.local_coords = false
	p.texture = VfxTextures.sparkle(7)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.0
	p.gravity = Vector2(0, 14.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 8.0
	p.spread = 180.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.9
	p.color_ramp = _fade_ramp(GLOW, 0.9)
	p.material = _additive()
	body.add_child(p)


func target_local(delta: float) -> Vector2:
	var target: Vector2
	if still_for < IDLE_BEFORE_ORBIT_S:
		target = SHOULDER - _heading * FOLLOW_PX
		set_in_front(true)
		_look = _look.lerp(_heading, clampf(delta * 10.0, 0.0, 1.0))
	else:
		var a: float = (still_for - IDLE_BEFORE_ORBIT_S) * TAU / ORBIT_PERIOD_S + PI
		target = ORBIT_CENTRE + Vector2(cos(a) * ORBIT_RX, sin(a) * ORBIT_RX * 0.35)
		# Behind the body on the far half of the orbit, in front on the near half.
		set_in_front(sin(a) > 0.0)
		# Idle, it watches its owner rather than the road.
		_look = _look.lerp((Vector2(0, -20) - target).normalized(), clampf(delta * 4.0, 0.0, 1.0))
	target.y += sin(_elapsed * 2.6) * 2.0
	return target


func _paint_orb(layer: VfxDrawLayer) -> void:
	var pulse: float = 0.85 + 0.15 * sin(_elapsed * 5.0)
	layer.draw_circle(Vector2.ZERO, 9.0, Color(GLOW, 0.10 * pulse))
	layer.draw_circle(Vector2.ZERO, 6.0, Color(GLOW, 0.25 * pulse))
	layer.draw_circle(Vector2.ZERO, 4.0, Color(GLOW, 0.7))
	layer.draw_circle(Vector2.ZERO, 3.0, Color(CORE, 0.95))


func _paint_eyes(layer: VfxDrawLayer) -> void:
	var open: bool = fposmod(_elapsed, BLINK_PERIOD_S) > 0.12
	var look: Vector2 = _look.normalized() if _look.length() > 0.01 else Vector2.ZERO
	for side: float in [-1.0, 1.0]:
		var at: Vector2 = Vector2(side * 1.5, -0.5) + look
		if open:
			layer.draw_rect(Rect2(at.round() - Vector2(0.5, 1.0), Vector2(1.0, 2.0)), EYE)
		else:
			layer.draw_rect(Rect2(at.round() - Vector2(0.5, 0.0), Vector2(1.0, 1.0)), EYE)
