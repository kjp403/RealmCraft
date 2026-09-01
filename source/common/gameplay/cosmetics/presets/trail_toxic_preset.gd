extends CosmeticTrailPreset
## TOXIC TRAIL. Dripping pools left on the tiles at every step, dissolving away
## behind the wearer, under a low-clinging bank of acrid haze.
##
## No ribbon on this one, and that is the design. A ribbon says the wearer is
## moving fast and leaving light behind them; sludge says something is DRIPPING
## off them and eating the floor. Those are different fictions, and mixing a
## bright streak into this would have made it read as a generic green speed trail
## - which is exactly what the old strip did.
##
## The haze is emitted in WORLD space (local_coords off), so it is left behind
## rather than carried. That single flag is the difference between a trail and a
## cloud stapled to the wearer's feet.

const POOL_TINT: Color = Color(0.36, 0.80, 0.14)
const HAZE_TINT: Color = Color(0.44, 0.86, 0.22)

## Seconds a dripped pool survives before it has fully dissolved.
const POOL_LIFE_S: float = 1.2
const POOL_SIZE: float = 20.0

var _haze: CPUParticles2D


func _build() -> void:
	_build_haze()


## Acrid haze hugging the floor. Deliberately near-zero vertical velocity: toxic
## fumes here are heavier than air, and haze that climbs reads as steam, which is
## the Emberfrost aura's language and must not be borrowed.
func _build_haze() -> void:
	var p: CPUParticles2D = _add_world_emitter(14, 1.8, VfxTextures.puff(16))
	_haze = p
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 7.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0    # spills sideways rather than rising
	p.gravity = Vector2(0, -3.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 11.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.6
	var spread: Curve = Curve.new()
	spread.add_point(Vector2(0.0, 0.5))
	spread.add_point(Vector2(1.0, 1.25)) # thins as it flattens out over the floor
	p.scale_amount_curve = spread
	p.color_ramp = _swell_ramp(HAZE_TINT, Color(HAZE_TINT, 0.30), 0.25)


func _on_step(world_pos: Vector2, _heading_dir: Vector2) -> void:
	# Behind the foot that made it, and off to one side. Steps land on a fixed
	# cadence, so drops on the exact path at a fixed size read as a dotted line
	# someone drew - the size and offset roll is what makes it look dripped.
	var beside: Vector2 = Vector2(-_heading.y, _heading.x) * randf_range(-3.5, 3.5)
	_drop_decal(
		world_pos - _heading * 3.0 + beside, GroundDecal.Variant.SLUDGE,
		POOL_TINT, POOL_SIZE * randf_range(0.7, 1.3), POOL_LIFE_S
	)


func _tick(delta: float) -> void:
	super(delta)
	# Stop producing when the wearer stops. Particles already emitted keep living
	# out their lifetime in world space, so the haze thins away behind them rather
	# than vanishing the instant they stand still.
	if _haze != null:
		_haze.emitting = is_moving()
