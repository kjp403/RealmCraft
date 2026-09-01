class_name MysterySeedBloom
extends Node2D
## The Mystery Seed's sprout: a short, loud burst of growth at the planter's
## feet, replicated so bystanders see it too.
##
## A replicated prop rather than a client-side burst on the user, because the
## seed is a thing that happens in the WORLD — the point of planting it at the cart is that other players look over.
##
## Draws itself and expires on its own clock at both ends. The server also
## despawns it after [constant LIFETIME_S] so a client that joined mid-bloom
## does not inherit a prop nobody will ever clean up.
##
## CPUParticles2D (not GPU) so the web export renders it — same constraint every
## other effect in the game is built against.

const LIFETIME_S: float = 2.2
## How tall the stalk climbs, in pixels.
const HEIGHT: float = 34.0
## Radius the leaf motes scatter to.
const SPREAD: float = 22.0
const STALK: Color = Color(0.42, 0.78, 0.36, 0.95)
const LEAF: Color = Color(0.62, 0.92, 0.45, 0.9)
const LEAF_FADE: Color = Color(0.35, 0.70, 0.30, 0.0)
const BLOSSOM: Color = Color(1.0, 0.88, 0.55, 0.9)

var _elapsed: float = 0.0


func _ready() -> void:
	z_index = 1 # above the ground, below HUD
	if multiplayer.is_server():
		# Server carries no visuals; it only owns the despawn clock.
		var timer: Timer = Timer.new()
		timer.wait_time = LIFETIME_S
		timer.one_shot = true
		timer.timeout.connect(_despawn)
		add_child(timer)
		timer.start()
		return

	var motes: CPUParticles2D = CPUParticles2D.new()
	motes.emitting = true
	motes.one_shot = true
	motes.amount = 22
	motes.lifetime = LIFETIME_S * 0.7
	motes.explosiveness = 0.5
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 6.0
	motes.direction = Vector2(0, -1)
	motes.spread = 55.0
	motes.gravity = Vector2(0, 40.0)
	motes.initial_velocity_min = 40.0
	motes.initial_velocity_max = 95.0
	motes.scale_amount_min = 1.0
	motes.scale_amount_max = 2.2
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, LEAF)
	ramp.set_color(1, LEAF_FADE)
	motes.color_ramp = ramp
	add_child(motes)


func _process(delta: float) -> void:
	_elapsed += delta
	if multiplayer.is_server():
		return
	queue_redraw()
	if _elapsed >= LIFETIME_S:
		# Client-side self-clean. The authoritative despawn still comes from the
		# server; this just stops a dropped despawn packet leaving a stalk behind.
		queue_free()


func _draw() -> void:
	var t: float = clampf(_elapsed / LIFETIME_S, 0.0, 1.0)
	# Fast out, slow settle — the "rapid growth" beat is the first third.
	var grow: float = clampf(t / 0.35, 0.0, 1.0)
	var eased: float = 1.0 - pow(1.0 - grow, 3.0)
	var top: Vector2 = Vector2(0, -HEIGHT * eased)
	var alpha: float = 1.0 - clampf((t - 0.6) / 0.4, 0.0, 1.0)
	draw_line(Vector2.ZERO, top, Color(STALK.r, STALK.g, STALK.b, STALK.a * alpha), 2.0)
	# Two leaves that unfurl once the stalk is most of the way up.
	var leaf_t: float = clampf((eased - 0.4) / 0.6, 0.0, 1.0)
	if leaf_t > 0.0:
		var span: Vector2 = Vector2(SPREAD * 0.5 * leaf_t, -HEIGHT * 0.55 * eased)
		var leaf_color: Color = Color(LEAF.r, LEAF.g, LEAF.b, LEAF.a * alpha)
		draw_line(Vector2(0, span.y), Vector2(span.x, span.y - 6.0), leaf_color, 2.0)
		draw_line(Vector2(0, span.y), Vector2(-span.x, span.y - 6.0), leaf_color, 2.0)
	# Blossom pops at the tip as the stalk tops out.
	if eased > 0.85:
		var pop: float = sin(clampf((t - 0.3) / 0.7, 0.0, 1.0) * PI)
		draw_circle(top, 3.0 + 2.5 * pop, Color(BLOSSOM.r, BLOSSOM.g, BLOSSOM.b, pop * alpha))


func _despawn() -> void:
	var container: ReplicatedPropsContainer = get_meta(&"rp_container", null) as ReplicatedPropsContainer
	if container == null:
		container = get_parent() as ReplicatedPropsContainer
	if container == null:
		queue_free()
		return
	var prop_id: int = container.child_id_of_node(self)
	if prop_id < 0:
		queue_free()
		return
	container.despawn_dynamic(prop_id)


## Server: sprout a bloom at [param global_pos] inside [param instance]. Silently
## does nothing when the map has no props container — a decorative burst must
## never be able to fail a use that already paid out.
static func plant(instance: ServerInstance, global_pos: Vector2) -> void:
	if instance == null or instance.instance_map == null:
		return
	var container: ReplicatedPropsContainer = instance.instance_map.replicated_props_container
	if container == null:
		return
	container.spawn_dynamic(
		ReplicatedPropsContainer.SCENE_MYSTERY_SEED_BLOOM,
		container.to_local(global_pos)
	)
