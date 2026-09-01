extends CosmeticPreset
## GALAXY AURA. An accretion disk on the floor with a void at its centre, and
## stars in real orbits around the wearer at different radii, speeds and heights.
##
## The orbits are DRAWN, not particled, and that is the key decision. CPUParticles2D
## does have an orbit velocity, but every particle then shares one plane and one
## rate, so the result is a flat spinning halo - the exact look the old strip
## already had. Keeping a small table of stars in script means each one gets its
## own radius, its own period and its own height, which is what turns a halo into
## a system with depth.
##
## Depth cue: a star on the far side of its orbit is drawn smaller and dimmer than
## the same star on the near side. Nothing else here sells "around the player"
## rather than "in front of the player", because at this sprite size there is no
## room for perspective to do it.
##
##   DISK    accretion_disk.gdshader - logarithmic spiral arms, dark core.
##   STARS   twelve orbiters, additive, twinkling on their own phases.
##   DUST    a thin drift of motes so the space between orbits is not empty.

const DISK_SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/accretion_disk.gdshader")

const DISK_DIAMETER: float = 76.0
const STAR_CORE: Color = Color(1.0, 1.0, 1.0)
const STAR_COOL: Color = Color(0.55, 0.92, 1.0)
const DUST_TINT: Color = Color(0.62, 0.42, 0.98)

const STAR_COUNT: int = 12
## Slowest and fastest orbital periods in seconds. The spread is what makes the
## field churn; a single period would have every star locked in formation.
const PERIOD_MIN_S: float = 2.6
const PERIOD_MAX_S: float = 7.5

## Per-star orbit table, filled once in _build: radius, angular speed, height,
## phase and twinkle rate. Rolled from a seeded RNG so a star's look is stable for
## its whole life - re-rolling per frame is what makes drawn particles boil.
var _stars: Array[Dictionary] = []


func _build() -> void:
	var rect: ColorRect = _add_floor_shader(DISK_SHADER, DISK_DIAMETER)
	var mat: ShaderMaterial = rect.material as ShaderMaterial
	mat.set_shader_parameter(&"disk_pixels", DISK_DIAMETER)
	# Held well under 1. Additive dust over dark tiles climbs fast, and at full
	# strength the arms merge into one bright smear and the void stops reading -
	# which loses the only shape that makes this a galaxy and not a purple blob.
	mat.set_shader_parameter(&"strength", 0.62)
	# Stars are light, so the drawn layer adds rather than paints. Only this
	# node's own _draw() is affected - children keep their own materials.
	material = _additive()
	_roll_stars()
	_build_dust()


func _roll_stars() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for i: int in STAR_COUNT:
		var k: float = float(i) / float(STAR_COUNT)
		var period: float = lerpf(PERIOD_MIN_S, PERIOD_MAX_S, rng.randf())
		_stars.append({
			# Inner orbits stay clear of the disk's void so stars never sit in the
			# black hole, which reads as a rendering gap rather than as depth.
			"radius": lerpf(BASE_RADIUS * 0.55, BASE_RADIUS * 1.15, rng.randf()),
			"speed": TAU / period,
			# Height is what separates the orbits into planes. Ankle to head.
			"height": lerpf(2.0, 34.0, rng.randf()),
			"phase": k * TAU + rng.randf() * 0.8,
			"twinkle": lerpf(1.8, 4.6, rng.randf()),
			"cool": rng.randf(),
		})


## Nebular dust between the orbits. Very dim and very slow - if it is noticeable
## on its own it is competing with the stars, which are the point.
func _build_dust() -> void:
	var p: CPUParticles2D = _add_emitter(12, 3.4, VfxTextures.dot(6))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(12, BASE_RADIUS * 0.9)
	p.direction = Vector2(0, -1)
	p.spread = 60.0
	p.gravity = Vector2(0, -5.0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 9.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	p.color_ramp = _swell_ramp(DUST_TINT, Color(DUST_TINT, 0.42), 0.3)
	p.material = _additive()


func _draw() -> void:
	# Orbits are computed in the ground plane by hand (via _ground_point) and then
	# lifted, so the draw transform stays upright - a squashed transform would
	# flatten the lift as well as the orbit.
	_use_upright_plane()
	for star: Dictionary in _stars:
		_draw_star(star)


func _draw_star(star: Dictionary) -> void:
	var angle: float = float(star["phase"]) + _elapsed * float(star["speed"])
	var at: Vector2 = _ground_point(angle, float(star["radius"]))
	at.y -= float(star["height"])
	# sin(angle) is +1 at the near side of the ellipse and -1 at the far side.
	var nearness: float = 0.5 + 0.5 * sin(angle)
	var twinkle: float = 0.6 + 0.4 * sin(_elapsed * float(star["twinkle"]) + float(star["phase"]))
	var alpha: float = (0.30 + 0.70 * nearness) * twinkle
	var tint: Color = STAR_CORE.lerp(STAR_COOL, float(star["cool"]))
	# Halo first, then a hard core pixel on top. The pairing is what makes a 1 px
	# dot read as a bright point of light rather than as a stray pixel.
	draw_circle(at, 2.2 + nearness * 1.6, Color(tint, 0.18 * alpha))
	var core: float = 1.0 + nearness * 0.6
	draw_rect(Rect2(at - Vector2(core, core) * 0.5, Vector2(core, core)), Color(STAR_CORE, alpha))
