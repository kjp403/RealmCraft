extends CosmeticPreset
## SOLAR ECLIPSE (mythic). A pitch-black disc under the wearer, ringed by a
## blazing corona, with flares licking out of it and prominences arcing back down
## into the dark.
##
## MECHANICAL HOOK: dynamic geometry. The flares are not sprites, particles or
## arcs - they are polygons whose vertices are rebuilt every frame
## (draw_colored_polygon), so a flare has a real tapering, curling silhouette that
## whips out and retracts. Nothing else in the cosmetic set generates its own
## mesh, and it is the only way to get a shape that both bends and thins along its
## length at 64 px sprite scale.
##
## The second hook is in the particle layer: the prominences use NEGATIVE radial
## acceleration, which in CPUParticles2D means the emission origin ATTRACTS them.
## They launch off the rim, lose the fight, and curve back down into the umbra -
## which is what a real prominence does, and something no gravity setting can
## express (gravity pulls one direction; this pulls toward a point).
##
##   UMBRA       eclipse_umbra.gdshader  - opaque black disc, mix-blended.
##   CORONA      solar_corona.gdshader   - ragged streamer halo, additive.
##   FLARES      generated polygons, additive, on top of both.
##   PROMINENCES particles thrown out and pulled back in.

const UMBRA_SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/eclipse_umbra.gdshader")
const CORONA_SHADER: Shader = preload("res://source/common/gameplay/cosmetics/presets/shaders/solar_corona.gdshader")

const DISC_DIAMETER: float = 78.0
## Fraction of the quad radius where the black disc ends. MUST match the `ring`
## uniform on the corona and the umbra's own core, or the light and the shadow
## meet at different radii and the eclipse gains a bright or dark seam.
const RING_FRACTION: float = 0.58

const CORE_HOT: Color = Color(1.0, 0.97, 0.86)
const FLARE_MID: Color = Color(1.0, 0.62, 0.14)
const FLARE_DEEP: Color = Color(0.92, 0.28, 0.04)

const FLARE_COUNT: int = 5
## Seconds for one flare to whip out and retract. Each runs on its own offset.
const FLARE_PERIOD_S: float = 2.6
## Vertices sampled along a flare's spine. Few enough to stay cheap at five
## flares a frame, enough that the curl reads as a curve and not as a bent stick.
const FLARE_SEGMENTS: int = 7

var _rim_px: float = 0.0
var _prominences: CPUParticles2D


func _build() -> void:
	_rim_px = DISC_DIAMETER * 0.5 * RING_FRACTION

	var umbra: ColorRect = _add_floor_shader(UMBRA_SHADER, DISC_DIAMETER)
	var umbra_mat: ShaderMaterial = umbra.material as ShaderMaterial
	umbra_mat.set_shader_parameter(&"umbra_pixels", DISC_DIAMETER)

	var corona: ColorRect = _add_floor_shader(CORONA_SHADER, DISC_DIAMETER * 1.5)
	var corona_mat: ShaderMaterial = corona.material as ShaderMaterial
	corona_mat.set_shader_parameter(&"corona_pixels", DISC_DIAMETER * 1.5)
	# The corona quad is wider than the umbra quad, so its `ring` has to be
	# re-expressed as a fraction of ITS radius or the light starts inside the
	# shadow. This is the one number tying the two quads together.
	corona_mat.set_shader_parameter(&"ring", _rim_px / (DISC_DIAMETER * 0.75))

	# Both quads a step BELOW this node, so the generated flares (drawn by this
	# node itself) land on top of them - a child draws over its parent otherwise,
	# and the opaque umbra would swallow every flare. Still under the player: the
	# wearer sits at z 0 and the whole preset hangs below that.
	umbra.z_index = -1
	corona.z_index = -1

	# The flares are light, so this node's own drawing adds. Children keep their
	# own materials, so the two shader quads are untouched by this.
	material = _additive()
	_build_prominences()


## Plasma thrown off the rim and pulled back into the dark centre.
##
## radial_accel is NEGATIVE, which is the entire trick: in CPUParticles2D a
## negative radial acceleration accelerates a particle TOWARD the emission origin.
## Combined with a launch velocity that beats it at first, every particle traces
## an arc out and back - a prominence loop. tangential_accel leans those arcs one
## way so they sweep around the disc instead of falling straight back down the
## line they left on.
func _build_prominences() -> void:
	var p: CPUParticles2D = _add_emitter(16, 1.5, VfxTextures.dot(8))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	p.emission_points = _ring_points(14, _rim_px)
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2.ZERO # the pull below replaces it; this is not falling
	p.initial_velocity_min = 34.0
	p.initial_velocity_max = 76.0
	p.radial_accel_min = -190.0
	p.radial_accel_max = -110.0
	p.tangential_accel_min = 20.0
	p.tangential_accel_max = 65.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	# Cool and shrink on the way back down, so the loop has a direction in time.
	var cooling: Curve = Curve.new()
	cooling.add_point(Vector2(0.0, 1.0))
	cooling.add_point(Vector2(0.55, 0.85))
	cooling.add_point(Vector2(1.0, 0.15))
	p.scale_amount_curve = cooling
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.18, 0.7, 1.0])
	ramp.colors = PackedColorArray([
		Color(CORE_HOT, 0.0), Color(CORE_HOT, 1.0),
		Color(FLARE_MID, 0.8), Color(FLARE_DEEP, 0.0),
	])
	p.color_ramp = ramp
	p.material = _additive()
	_prominences = p


func _tick(_delta: float) -> void:
	# Distance gate: a wearer this far off camera cannot be seen, and five
	# polygons plus sixteen particles a frame each is not worth spending on them.
	if _prominences != null:
		_prominences.emitting = _viewer_in_range()


func _draw() -> void:
	# Flares are built in ground space by _ground_point and then drawn upright, so
	# their WIDTH is not squashed a second time - a flare flattened twice reads as
	# a smear lying on the floor rather than as a tongue of fire.
	_use_upright_plane()
	if not _viewer_in_range():
		return
	for i: int in FLARE_COUNT:
		_draw_flare(i)


## One flare, as two stacked polygons: a wide deep-orange tongue with a narrower
## hot one inside it. Stacking is how a flat-shaded polygon gets a gradient -
## draw_colored_polygon takes exactly one colour.
func _draw_flare(index: int) -> void:
	var offset: float = float(index) / float(FLARE_COUNT)
	var phase: float = fposmod(_elapsed / FLARE_PERIOD_S + offset * 0.83, 1.0)
	# Whip OUT fast, retract slowly. The asymmetry is what makes it lick rather
	# than pulse; a symmetric curve reads as breathing.
	var extend: float = smoothstep(0.0, 0.16, phase) * (1.0 - smoothstep(0.35, 0.95, phase))
	# Each flare leaves from its own point on the rim and drifts slowly around it.
	var base_angle: float = offset * TAU + _elapsed * 0.11
	# Curl direction alternates, so the corona does not appear to spin.
	var curl: float = (0.85 if index % 2 == 0 else -0.85) * extend
	var length: float = (14.0 + 20.0 * sin(offset * 7.3 + 1.1)) * extend
	if length < 3.0:
		return # too short to be worth a polygon, and see the width note below

	# Width is a FRACTION OF LENGTH, never a constant. A fixed width looks right
	# at full extension and is a bug at the start and end of the cycle: the spine
	# collapses toward a point while the sides stay wide, the two cross-sections
	# cross over each other, and the result is a self-intersecting bow tie that
	# Godot's triangulator rejects ("Invalid polygon data, triangulation failed").
	# Tying width to length keeps the flare's proportions fixed at every size, so
	# it can never fold through itself however short it gets.
	var width: float = length * 0.17

	var spine: PackedVector2Array = PackedVector2Array()
	for s: int in FLARE_SEGMENTS:
		var k: float = float(s) / float(FLARE_SEGMENTS - 1)
		# k*k on the curl: a flare leaves the surface nearly straight and bends
		# harder the further it gets, which is what following a field line looks
		# like. A linear curl gives a uniform arc, which reads as a drawn crescent.
		var angle: float = base_angle + curl * k * k
		spine.append(_ground_point(angle, _rim_px + length * k))

	draw_colored_polygon(_ribbon_polygon(spine, width), Color(FLARE_DEEP, 0.50 * extend))
	draw_colored_polygon(_ribbon_polygon(spine, width * 0.45), Color(FLARE_MID, 0.85 * extend))
	# A hot pip where the flare leaves the surface, tying it to the corona.
	draw_circle(spine[0], 2.0 + extend * 1.6, Color(CORE_HOT, 0.55 * extend))


## Turn a spine into a closed polygon that tapers to a point at the tip: walk out
## along one side, come back along the other.
##
## The taper is (1-k) squared rather than linear - a flare is thick at the base
## and needle-fine for most of its length, and a linear taper gives a wedge.
##
## The TIP is emitted exactly once. Walking both sides over every spine point
## looks right and is not: the taper reaches zero width at the last point, so both
## sides land on the identical vertex, and a polygon with a repeated consecutive
## vertex has a zero-area sliver in it that Godot's triangulator rejects outright
## ("Invalid polygon data, triangulation failed") - so the flare simply does not
## draw. The return walk therefore starts one point back from the tip.
func _ribbon_polygon(spine: PackedVector2Array, width: float) -> PackedVector2Array:
	var last: int = spine.size() - 1
	var left: PackedVector2Array = PackedVector2Array()
	var right: PackedVector2Array = PackedVector2Array()
	for i: int in spine.size():
		var k: float = float(i) / float(last)
		var ahead: Vector2 = spine[mini(i + 1, last)]
		var behind: Vector2 = spine[maxi(i - 1, 0)]
		var along: Vector2 = ahead - behind
		if along.length_squared() < 0.0001:
			along = Vector2.RIGHT
		var side: Vector2 = Vector2(-along.y, along.x).normalized() * width * pow(1.0 - k, 2.0)
		left.append(spine[i] + side)
		if i < last:
			right.append(spine[i] - side)
	# Reverse the return side so the ring winds consistently; a self-crossing
	# polygon triangulates into a bow tie.
	right.reverse()
	return left + right
