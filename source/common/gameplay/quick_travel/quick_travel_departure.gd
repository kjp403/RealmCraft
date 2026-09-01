class_name QuickTravelDeparture
extends Node2D
## Client-only "you are being pulled away" burst played the instant a Wayfarer
## ride is booked. Motes spiral INWARD and up into the traveller while a pink
## ring collapses around their feet — the visual inverse of [SpawnEffect]'s
## materialise, which is what makes it read as leaving rather than arriving.
##
## Standalone Node2D that draws itself and frees itself, for the same reason
## SpawnEffect is: a tween on a replicated character's own modulate/scale does
## not reach its displayed sprite. Add it at a point and forget it.
##
## CPUParticles2D (not GPU) so the web export renders it. It is expected to be
## cut short — the map swaps out from under it mid-animation — so nothing here
## may depend on reaching the end of its own lifetime.

const DURATION: float = 0.55
## Radius the collapsing ring starts at.
const RADIUS: float = 30.0
## Hot pink, matching the Wayfarer's robes and the window's accent.
const ACCENT: Color = Color(1.0, 0.41, 0.71, 0.95)
const ACCENT_DEEP: Color = Color(1.0, 0.08, 0.58, 0.0)

var _elapsed: float = 0.0


func _ready() -> void:
	z_index = 1 # just above the character, still below HUD/menus
	var p: CPUParticles2D = CPUParticles2D.new()
	p.emitting = true
	p.one_shot = true
	p.amount = 18
	p.lifetime = DURATION
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = RADIUS
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	# Negative radial accel pulls the motes back toward the emitter, so they
	# converge on the traveller instead of scattering.
	p.radial_accel_min = -140.0
	p.radial_accel_max = -80.0
	p.gravity = Vector2(0, -70.0)
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 40.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var ramp: Gradient = Gradient.new()
	ramp.set_color(0, ACCENT)
	ramp.set_color(1, ACCENT_DEEP)
	p.color_ramp = ramp
	add_child(p)


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= DURATION:
		queue_free()


func _draw() -> void:
	var t: float = clampf(_elapsed / DURATION, 0.0, 1.0)
	# Ring collapses inward and fades — the mirror of a spawn ring expanding.
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	var r: float = lerpf(RADIUS, 2.0, eased)
	var alpha: float = (1.0 - t) * 0.9
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(ACCENT.r, ACCENT.g, ACCENT.b, alpha), 2.0, true)
	# A short vertical flare that brightens as the ring closes.
	var flare: float = sin(t * PI)
	draw_line(
		Vector2(0, 4.0),
		Vector2(0, -18.0 - 16.0 * flare),
		Color(1.0, 0.75, 0.9, flare * 0.55),
		2.0
	)
