extends CosmeticPreset
## TOXIC AURA. A pool of sludge on the floor, biohazard mist climbing out of it,
## and droplets condensing and falling back at head height.
##
## The idea the whole effect hangs on is a CYCLE: the pool feeds the mist, the
## mist climbs, and at the top it condenses into droplets that fall. That loop is
## why it reads as something happening to the ground rather than as a green filter
## over the character - each layer is visibly caused by the one below it.
##
##   FLOOR   toxic_sludge.gdshader - swirling, bubbling, ringed.
##   MIST    a slow, wide, very transparent column rising off the pool's rim.
##   STEAM   faster, tighter, brighter wisps - the corrosive edge on top of the
##           soft mist, which alone would look like fog.
##   POP     a repeating burst at head height whose particles fall back down.

const SLUDGE_SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/toxic_sludge.gdshader")

const POOL_DIAMETER: float = 68.0
## Deep, sickly green. Sampled to stay clearly distinct from the Verdant aura's
## leaf green - the two must never be confused at a glance in a crowd.
const MIST_TINT: Color = Color(0.45, 0.85, 0.20)
const STEAM_TINT: Color = Color(0.72, 1.0, 0.42)
const DROPLET_TINT: Color = Color(0.55, 0.95, 0.22)

## Seconds between condensation pops. Prime-ish against the pool's own ring cycle
## so the two layers drift in and out of phase instead of locking together.
const POP_PERIOD_S: float = 0.7

var _pool: ShaderMaterial


func _build() -> void:
	var rect: ColorRect = _add_floor_shader(SLUDGE_SHADER, POOL_DIAMETER)
	_pool = rect.material as ShaderMaterial
	_pool.set_shader_parameter(&"pool_pixels", POOL_DIAMETER)
	_build_mist()
	_build_steam()
	_build_condensation()


## The broad, slow layer. Emitted from the pool's RIM, not from its middle, so it
## climbs around the wearer instead of straight up through them.
func _build_mist() -> void:
	var p: CPUParticles2D = _add_emitter(10, 2.6, VfxTextures.puff(16))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(12, BASE_RADIUS * 0.85)
	p.direction = Vector2(0, -1)
	p.spread = 18.0
	p.gravity = Vector2(0, -9.0) # buoyant, not launched
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 13.0
	p.scale_amount_min = 1.4
	p.scale_amount_max = 3.0
	# Swells as it climbs, the way a real gas plume expands as it cools.
	var growth: Curve = Curve.new()
	growth.add_point(Vector2(0.0, 0.45))
	growth.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = growth
	p.color_ramp = _swell_ramp(MIST_TINT, Color(MIST_TINT, 0.24), 0.3)


## Corrosive wisps: faster, smaller, brighter. Without these the mist alone is
## just fog, and fog is not poisonous.
func _build_steam() -> void:
	var p: CPUParticles2D = _add_emitter(8, 1.5, VfxTextures.puff(16))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(9, BASE_RADIUS * 0.55)
	p.direction = Vector2(0, -1)
	p.spread = 26.0
	p.gravity = Vector2(0, -30.0)
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 30.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	# A slow tumble so the wisps are not all the same silhouette.
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.color_ramp = _swell_ramp(STEAM_TINT, Color(STEAM_TINT, 0.45), 0.22)


## Condensation at head height: a batch pops into being together and rains back
## down. explosiveness 1.0 on a looping emitter is what makes it a repeating POP
## rather than a drizzle - see [method CosmeticPreset._add_burst].
func _build_condensation() -> void:
	var p: CPUParticles2D = _add_burst(7, POP_PERIOD_S, VfxTextures.droplet(8))
	p.position = Vector2(0.0, HEAD_Y)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = BASE_RADIUS * 0.55
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 150.0) # they fall back toward the pool that made them
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 26.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.1
	p.color_ramp = _fade_ramp(DROPLET_TINT, 0.95)


func _tick(_delta: float) -> void:
	# Breathe the pool very slightly. Tied to the same clock as everything else so
	# a wearer who equips mid-fight starts at the bottom of the swell, not part way
	# through a bright one.
	if _pool != null:
		_pool.set_shader_parameter(&"strength", 0.92 + 0.08 * sin(_elapsed * 1.1))
