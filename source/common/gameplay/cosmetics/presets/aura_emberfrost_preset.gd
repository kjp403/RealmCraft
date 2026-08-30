extends CosmeticPreset
## EMBERFROST AURA. One ground ring split down the middle: frost on the left half,
## fire on the right, and steam bursting where the two meet.
##
## The old version cross-faded an ember palette into a frost palette over time, so
## the aura was only ever ONE element at a time and the name did not read. Here
## both are on screen at once and the interesting part is the SEAM. Everything is
## arranged around making that seam legible:
##
##   FROST HALF  a cold ring with crystal ticks growing inward, and shards lifting
##               off it slowly - cold things are slow and rigid.
##   EMBER HALF  a hot ring with embers rising fast and flickering, under a haze
##               of rising warm air (see REFRACTIVE_HEAT for why that layer adds
##               light rather than refracting the screen behind it).
##   THE SEAM    at the top and bottom of the ellipse, where the halves touch,
##               steam bursts pop on a repeating cycle. Without them the ring is
##               two unrelated semicircles that happen to share a centre; with
##               them it reads as one reaction.
##
## The split is LEFT/RIGHT rather than front/back because a radial cosmetic never
## mirrors with the body (see [CosmeticVfx.set_facing]), so the halves stay put
## when the wearer turns around - a split that swapped sides on every turn would
## look like a rendering fault.

const HAZE_SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/heat_haze.gdshader")
const SHIMMER_SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/heat_shimmer.gdshader")

const FROST_TINT: Color = Color(0.55, 0.82, 1.0)
const FROST_DEEP: Color = Color(0.16, 0.42, 0.85)
const EMBER_TINT: Color = Color(1.0, 0.58, 0.16)
const EMBER_HOT: Color = Color(1.0, 0.88, 0.52)
const STEAM_TINT: Color = Color(0.86, 0.90, 0.95)

## Radians. The ember half runs -PI/2..+PI/2 (screen right); frost takes the rest.
const SEAM_TOP: float = -PI * 0.5
const SEAM_BOTTOM: float = PI * 0.5
## Seconds between steam pops at each seam.
const STEAM_PERIOD_S: float = 0.75
const CRYSTAL_COUNT: int = 7


func _build() -> void:
	_build_frost_shards()
	_build_embers()
	_build_heat()
	# One burst emitter per seam. Two nodes rather than one wide emitter so each
	# seam pops on its own offset - simultaneous pops read as a single ring flash.
	_build_steam(_ground_point(SEAM_TOP, BASE_RADIUS), 0.0)
	_build_steam(_ground_point(SEAM_BOTTOM, BASE_RADIUS), STEAM_PERIOD_S * 0.5)


## Ice lifting off the cold half: slow, rigid, barely spreading.
func _build_frost_shards() -> void:
	var p: CPUParticles2D = _add_emitter(8, 2.0, VfxTextures.shard(9))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _arc_points(9, BASE_RADIUS * 0.92, SEAM_BOTTOM, SEAM_BOTTOM + PI)
	p.direction = Vector2(0, -1)
	p.spread = 8.0 # crystals rise straight; a wide spread reads as sparks
	p.gravity = Vector2(0, -12.0)
	p.initial_velocity_min = 9.0
	p.initial_velocity_max = 20.0
	p.damping_min = 6.0
	p.damping_max = 12.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.5
	# A slight, slow tilt so they read as solid objects catching light.
	p.angular_velocity_min = -18.0
	p.angular_velocity_max = 18.0
	p.color_ramp = _swell_ramp(FROST_DEEP, Color(FROST_TINT, 0.9), 0.2)
	p.material = _additive()


## Embers off the hot half: fast, scattered, short-lived, and flickering.
func _build_embers() -> void:
	var p: CPUParticles2D = _add_emitter(14, 1.1, VfxTextures.dot(6))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _arc_points(9, BASE_RADIUS * 0.92, SEAM_TOP, SEAM_TOP + PI)
	p.direction = Vector2(0, -1)
	p.spread = 32.0
	p.gravity = Vector2(0, -46.0) # hot air carries them up hard
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 44.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	# Shrink as they cool, so they burn out instead of merely fading.
	var cooling: Curve = Curve.new()
	cooling.add_point(Vector2(0.0, 1.0))
	cooling.add_point(Vector2(1.0, 0.2))
	p.scale_amount_curve = cooling
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	ramp.colors = PackedColorArray([
		Color(EMBER_HOT, 0.0), Color(EMBER_HOT, 1.0), Color(EMBER_TINT, 0.0),
	])
	p.color_ramp = ramp
	p.material = _additive()


## Rising air over the ember half: warm bands that climb, widen and thin out.
##
## This SHOULD have been true refraction, and heat_haze.gdshader is that shader,
## kept and wired up behind the constant below. It is off because it does not work
## on what this project actually renders with:
##
##   * The project runs the GL Compatibility renderer (for the web export). Godot
##     only inserts the back-buffer copy that hint_screen_texture needs on
##     Forward+; here the sampler reads an empty buffer and the quad paints a
##     solid BLACK RECTANGLE over the aura. Adding an explicit BackBufferCopy in
##     front of it (COPY_MODE_RECT, sized to the quad) did not fix it either -
##     verified with tools/render_cosmetic_presets.tscn, both ways.
##   * Even working, it would cost a back-buffer copy per wearer per frame, which
##     a crowded town on the web build cannot absorb.
##   * And it sits at z -1, under the bodies, so the only thing it could ever bend
##     is the floor behind the ring - not the wearer.
##
## The shimmer keeps the motion cue that does the real work at this sprite size -
## warm columns rising and thinning - and costs one additive quad. Flip
## REFRACTIVE_HEAT if this project ever moves to Forward+; the two shaders share
## an envelope and a noise field so the swap is like-for-like.
const REFRACTIVE_HEAT: bool = false


func _build_heat() -> void:
	var area: Rect2 = Rect2(2.0, -34.0, 42.0, 40.0)
	if REFRACTIVE_HEAT:
		var copy: BackBufferCopy = BackBufferCopy.new()
		copy.copy_mode = BackBufferCopy.COPY_MODE_RECT
		copy.rect = area
		add_child(copy) # added first so it runs BEFORE the quad that samples it
	var haze: ColorRect = ColorRect.new()
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = HAZE_SHADER if REFRACTIVE_HEAT else SHIMMER_SHADER
	mat.set_shader_parameter(&"glow", EMBER_TINT)
	haze.material = mat
	# Standing UP over the hot half, and deliberately NOT squashed - this is air
	# above the ring, not another mark on the floor.
	haze.size = area.size
	haze.position = area.position
	haze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(haze)


## Steam at one seam: a batch popping together, thrown mostly upward and fading
## fast. Short-lived on purpose - lingering steam turns the seam into a smoke
## column and hides the split that the whole aura is built around.
func _build_steam(at: Vector2, phase_offset: float) -> void:
	var p: CPUParticles2D = _add_burst(6, STEAM_PERIOD_S, VfxTextures.puff(16))
	p.position = at
	# preprocess runs the system forward before its first frame, which is how the
	# two seams end up half a cycle out of step with each other.
	p.preprocess = phase_offset
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 3.0
	p.direction = Vector2(0, -1)
	p.spread = 45.0
	p.gravity = Vector2(0, -34.0)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 42.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	var growth: Curve = Curve.new()
	growth.add_point(Vector2(0.0, 0.4))
	growth.add_point(Vector2(1.0, 1.3))
	p.scale_amount_curve = growth
	p.color_ramp = _swell_ramp(STEAM_TINT, Color(STEAM_TINT, 0.34), 0.2)


func _draw() -> void:
	_use_ground_plane()
	_draw_half(SEAM_BOTTOM, PI, FROST_TINT, FROST_DEEP, false)
	_draw_half(SEAM_TOP, PI, EMBER_TINT, EMBER_HOT, true)
	_draw_seam_glow()
	_use_upright_plane()
	_draw_crystals()


## One half of the dual ring: an outer arc, an inner arc turning the other way,
## and a moving bright band along the outer one.
##
## The two arcs are what make it a DUAL ring rather than a thick one, and running
## them in opposite directions is what stops the halves looking like a single hoop
## someone painted two colours.
func _draw_half(start: float, length: float, tint: Color, hot: Color, ember: bool) -> void:
	var drift: float = _elapsed * (0.9 if ember else 0.35)
	var pulse: float = 0.5 + 0.5 * sin(_elapsed * (5.0 if ember else 1.6))
	draw_arc(
		Vector2.ZERO, BASE_RADIUS, start, start + length, 32,
		Color(tint, 0.55 + 0.25 * pulse), 2.0, false
	)
	draw_arc(
		Vector2.ZERO, BASE_RADIUS * 0.66, start - drift * 0.5, start - drift * 0.5 + length * 0.8,
		24, Color(tint, 0.35), 1.0, false
	)
	# A bright band chasing around the half. Fire's runs fast and flickers; frost's
	# creeps, because the same motion at the same speed on both halves would
	# undo the whole hot/cold contrast.
	var head: float = start + fposmod(drift, length)
	draw_arc(
		Vector2.ZERO, BASE_RADIUS, head, head + length * 0.18, 12,
		Color(hot, 0.75 * (0.55 + 0.45 * pulse)), 2.0, false
	)


## A soft flare exactly on each seam, under the steam. It ties the two arcs
## together at the join; without it the arcs visibly end.
func _draw_seam_glow() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_elapsed * 4.2)
	for angle: float in [SEAM_TOP, SEAM_BOTTOM]:
		var at: Vector2 = _ground_point(angle, BASE_RADIUS)
		draw_circle(at, 4.0 + pulse * 2.0, Color(STEAM_TINT, 0.20 + 0.15 * pulse))


## Ice growing UP out of the frost half of the ring. Upright, and drawn rather
## than particled, because these have to stay anchored to the ring: a crystal that
## drifts is a shard, and shards are already the particle layer's job.
func _draw_crystals() -> void:
	for i: int in CRYSTAL_COUNT:
		var k: float = float(i) / float(CRYSTAL_COUNT - 1)
		var angle: float = lerpf(SEAM_BOTTOM, SEAM_BOTTOM + PI, k)
		var base: Vector2 = _ground_point(angle, BASE_RADIUS * 0.95)
		# Each crystal grows and melts on its own offset cycle.
		var phase: float = fposmod(_elapsed * 0.35 + k * 0.9, 1.0)
		var grow: float = smoothstep(0.0, 0.3, phase) * (1.0 - smoothstep(0.65, 1.0, phase))
		var height: float = (4.0 + 7.0 * sin(k * PI)) * grow
		if height <= 0.5:
			continue
		var tip: Vector2 = base + Vector2(0.0, -height)
		draw_line(base, tip, Color(FROST_TINT, 0.75 * grow), 1.0)
		# A single bright pixel at the tip: the catch-light that reads as ice.
		draw_rect(Rect2(tip - Vector2(0.5, 0.5), Vector2(1.5, 1.5)), Color(Color.WHITE, 0.8 * grow))
