extends CosmeticPreset
## BLOOD AURA. A dark crimson pool rippling on the floor, sanguine droplets
## falling UPWARD out of it, and a slow heartbeat vignette on the wearer's own
## screen.
##
## The upward droplets are the whole idea. Blood pooling on the ground is only a
## mess; blood LEAVING the ground against gravity is unnatural, and unnatural is
## the read this cosmetic is bought for. Everything else exists to support that
## one inversion:
##
##   POOL      blood_pool.gdshader - dark, heavy, ringed with slow ripples. It has
##             to look like the source the droplets are being drawn out of.
##   RISE      droplets lifting off the pool, decelerating as they climb.
##   BURST     at KNEE height they lose the fight and shatter into micro-droplets
##             that fall back. That reversal is what makes the rise look like an
##             effort rather than like particles configured with negative gravity.
##   VIGNETTE  a heartbeat in the corners of the owner's screen. See
##             [BloodVignette] for why it is owner-only and why it is that faint.

const POOL_SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/blood_pool.gdshader")

const POOL_DIAMETER: float = 66.0
const BLOOD_TINT: Color = Color(0.62, 0.06, 0.09)
const BRIGHT_BLOOD: Color = Color(0.85, 0.17, 0.18)

## Seconds between shatter bursts at knee height.
const BURST_PERIOD_S: float = 0.55
## How long to keep re-checking whether this wearer turned out to be the local
## player. A cosmetic can be applied during spawn, BEFORE ClientState.local_player
## is assigned, so a single check at build time would silently drop the vignette
## for the one player who is supposed to see it.
const OWNER_CHECK_WINDOW_S: float = 6.0

var _pool: ShaderMaterial
var _vignette: BloodVignette


func _build() -> void:
	var rect: ColorRect = _add_floor_shader(POOL_SHADER, POOL_DIAMETER)
	_pool = rect.material as ShaderMaterial
	_pool.set_shader_parameter(&"pool_pixels", POOL_DIAMETER)
	_build_rising_droplets()
	_build_knee_burst()
	_build_vignette()


## Droplets drawn up out of the pool. damping is doing the important work here:
## they launch, slow, and stall around knee height, which is exactly where the
## burst layer catches them.
func _build_rising_droplets() -> void:
	var p: CPUParticles2D = _add_emitter(11, 1.3, VfxTextures.droplet(8))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(12, BASE_RADIUS * 0.8)
	p.direction = Vector2(0, -1)
	p.spread = 14.0
	p.gravity = Vector2(0, -22.0)
	p.initial_velocity_min = 26.0
	p.initial_velocity_max = 46.0
	p.damping_min = 18.0
	p.damping_max = 30.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4
	# Droplets fall nose-first, so they must hang the other way up when rising.
	p.angle_min = 180.0
	p.angle_max = 180.0
	p.color_ramp = _swell_ramp(BLOOD_TINT, Color(BRIGHT_BLOOD, 0.95), 0.15)


## The shatter. A batch bursting together at knee height, thrown outward and
## downward - the moment the rise fails.
func _build_knee_burst() -> void:
	var p: CPUParticles2D = _add_burst(9, BURST_PERIOD_S, VfxTextures.pip(6))
	p.position = Vector2(0.0, KNEE_Y)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = BASE_RADIUS * 0.7
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 220.0)
	p.initial_velocity_min = 16.0
	p.initial_velocity_max = 48.0
	p.scale_amount_min = 0.45
	p.scale_amount_max = 0.9
	p.color_ramp = _fade_ramp(BRIGHT_BLOOD, 0.9)


## Owner-only screen layer. Gated on [method CosmeticPreset._is_local_wearer]
## because a cosmetic must never be able to tint a bystander's screen.
func _build_vignette() -> void:
	if _vignette != null or not _is_local_wearer():
		return
	_vignette = BloodVignette.new()
	add_child(_vignette)


func _tick(_delta: float) -> void:
	if _pool != null:
		# The pool swells on the same slow beat as the vignette, so the floor and
		# the screen edge pulse together and read as one effect.
		_pool.set_shader_parameter(&"strength", 0.90 + 0.10 * sin(_elapsed * 4.65))
	# Keep looking for a short while — see OWNER_CHECK_WINDOW_S. After the window
	# this stops costing anything at all.
	if _vignette == null and _elapsed < OWNER_CHECK_WINDOW_S:
		_build_vignette()
