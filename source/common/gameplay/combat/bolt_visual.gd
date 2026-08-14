class_name BoltVisual
extends Node2D
## The body of a magic bolt: a white-hot core inside a breathing halo, laying a soft wake
## behind it. Drop it in a [Projectile] scene where a plain Sprite2D used to sit (see
## wand/bolt.tscn) — it draws itself and owns its own trail.
##
## Drawn in WHITE on purpose. The parent Projectile carries [member BoltShootAbility.bolt_modulate],
## so the colour stays DATA (violet Magic Bolt, orange Ember Bolt, magenta Overload) and one scene
## serves them all — the same reason the old bolt sprites were white. Because the rings blend
## ADDITIVELY their alphas SUM toward the middle (0.10 → 0.34 → 1.29 → 2.29), which pushes the core
## past full brightness and reads white-hot in every tint, with the halo left carrying the colour.
##
## Client-only: on a headless world it frees itself in [method _ready], so the server pays nothing
## for the draw or the particles (the same split [method Projectile._spawn_impact] already makes).

## Soft round mote for the wake — the same texture the old bolt used as its whole body.
const MOTE_TEX: Texture2D = preload("res://assets/sprites/particles/white_circle.png")

## Radius + alpha of each ring, outermost first. Additive, so these alphas accumulate inward;
## see the class docs for why that is what makes the core burn white.
const RINGS: Array[Vector2] = [
	Vector2(9.4, 0.10), Vector2(6.3, 0.24), Vector2(3.7, 0.95), Vector2(1.9, 1.0),
]

## Overall size multiplier on [constant RINGS] — a bigger nuke can read bigger without a new scene.
@export var size: float = 1.0
## Breath of the halo: how far the rings swell (0 = a dead, static ball) and how fast.
@export var pulse_depth: float = 0.13
@export var pulse_hz: float = 2.7
## The wake. 0 motes = core only.
@export var trail_motes: int = 52
@export var trail_seconds: float = 0.34

var _t: float = 0.0
var _trail: CPUParticles2D


func _ready() -> void:
	if multiplayer.is_server():
		queue_free() # nothing to draw and no particles to tick on a headless world
		return
	material = _additive()
	_spawn_trail()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	# The wake lives on the MAP, not on us, so it has to be told where we are.
	if _trail != null and is_instance_valid(_trail):
		_trail.global_position = global_position


func _draw() -> void:
	var pulse: float = 1.0 + pulse_depth * sin(_t * TAU * pulse_hz)
	for ring: Vector2 in RINGS:
		draw_circle(Vector2.ZERO, ring.x * size * pulse, Color(1.0, 1.0, 1.0, ring.y))


## The wake is emitted in WORLD space (local_coords = false) — that is the whole trick: the motes
## stay where they were laid instead of riding along, so the bolt drags a tail instead of wearing a
## halo. It is parented to the map rather than to us so that a bolt freeing on impact does not take
## its own tail with it (see [method _exit_tree]).
func _spawn_trail() -> void:
	if trail_motes <= 0:
		return
	var p: CPUParticles2D = CPUParticles2D.new()
	p.texture = MOTE_TEX
	p.local_coords = false
	p.emitting = true
	p.amount = trail_motes
	p.lifetime = trail_seconds
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 0.0
	p.initial_velocity_max = 7.0
	p.scale_amount_min = 0.16 * size
	p.scale_amount_max = 0.29 * size
	var shrink: Curve = Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = shrink
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	ramp.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.5), Color(1.0, 1.0, 1.0, 0.4), Color(1.0, 1.0, 1.0, 0.0),
	])
	p.color_ramp = ramp
	p.material = _additive()
	p.z_index = 1 # over the floor, like the impact spark

	var host: Node = _map_host()
	if host == null:
		add_child(p) # no map to hand it to — ride along rather than lose the trail entirely
	else:
		# Off on the map it cannot inherit the bolt's modulate, so the tint is copied across.
		p.modulate = _bolt_tint()
		host.add_child(p)
		p.global_position = global_position
	_trail = p


## The bolt frees the instant it lands, and a wake that blinks out with it POPS. Stop emitting and
## let the tail burn down where it was laid — the same reason [method Projectile._spawn_impact]
## hands its spark to the map instead of keeping it.
func _exit_tree() -> void:
	if _trail == null or not is_instance_valid(_trail):
		return
	var trail: CPUParticles2D = _trail
	_trail = null
	if trail.get_parent() == self or not trail.is_inside_tree():
		return # riding along / already going away with us — nothing to hand over
	trail.emitting = false
	trail.get_tree().create_timer(trail.lifetime).timeout.connect(trail.queue_free)


## The map: one above the caster the Projectile is parented under. Same walk
## [method Projectile._spawn_impact] makes.
func _map_host() -> Node:
	var bolt: Node = get_parent()
	if bolt == null:
		return null
	var caster: Node = bolt.get_parent()
	if caster == null:
		return null
	return caster.get_parent()


func _bolt_tint() -> Color:
	var bolt: CanvasItem = get_parent() as CanvasItem
	return bolt.modulate if bolt != null else Color.WHITE


func _additive() -> CanvasItemMaterial:
	var m: CanvasItemMaterial = CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m
