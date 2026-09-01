extends CosmeticTrailPreset
## GALAXY TRAIL. A nebular ribbon of purple and blue dragged behind the wearer,
## shedding stardust, and leaving constellations hanging in the space they walked
## through.
##
## The constellations are the part worth the trouble. Stardust alone is a particle
## layer like any other: it drifts, it fades, and nothing is left. Pinning a dot
## at every step and JOINING consecutive dots with a faint line turns the path
## itself into a record - you can look back across a room and read where someone
## walked as a star chart. It costs one array of world positions and a few draw
## calls, and it is the only thing here the old strip could not have faked.
##
## Dots are drawn, not particled, for exactly that reason: a particle cannot know
## about the particle before it, so it can never be joined to one.

const RIBBON_WIDTH: float = 7.0
const NEBULA_DEEP: Color = Color(0.24, 0.10, 0.55)
const NEBULA_MID: Color = Color(0.45, 0.28, 0.92)
const NEBULA_HOT: Color = Color(0.52, 0.80, 1.0)
const STAR_TINT: Color = Color(0.86, 0.95, 1.0)

## Seconds a constellation dot hangs in space. Long - much longer than the ribbon
## - because the whole point is that the record outlives the movement.
const STAR_LIFE_S: float = 3.2
## Above this gap, consecutive dots are NOT joined. Stops a line being drawn
## across the map when the wearer warps or rounds a corner out of sample range.
const LINK_MAX_PX: float = 46.0

## Pinned dots: {"p": world Vector2, "t": birth on this preset's clock}.
var _constellation: Array[Dictionary] = []
var _ribbon: Line2D
var _dust: CPUParticles2D


func _build() -> void:
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
	ramp.colors = PackedColorArray([
		Color(NEBULA_DEEP, 0.0),
		Color(NEBULA_DEEP, 0.45),
		Color(NEBULA_MID, 0.7),
		Color(NEBULA_HOT, 0.85), # hottest at the wearer, cooling into the tail
	])
	_ribbon = _add_ribbon(RIBBON_WIDTH, ramp, true)
	# The drawn constellation is starlight, so it adds. Children keep their own
	# materials, so this only affects this node's _draw().
	material = _additive()
	_build_dust()


## Stardust shed off the ribbon: slow, weightless, twinkling out.
func _build_dust() -> void:
	var p: CPUParticles2D = _add_world_emitter(14, 2.2, VfxTextures.sparkle(9))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, -4.0) # no real weight out here
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 16.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.0
	p.angular_velocity_min = -60.0
	p.angular_velocity_max = 60.0
	p.color_ramp = _swell_ramp(NEBULA_MID, Color(STAR_TINT, 0.9), 0.2)
	p.material = _additive()
	_dust = p


func _tick(delta: float) -> void:
	super(delta)
	_ribbon.points = path_points()
	if _dust != null:
		_dust.emitting = is_moving()
	_expire_constellation()


func _on_step(world_pos: Vector2, _heading_dir: Vector2) -> void:
	# Nudge each dot off the exact path so the constellation is not a ruler-straight
	# row of pips down the middle of the ribbon.
	# Thrown well clear of the ribbon. Close in, the dots bead up along the
	# ribbon's own highlight and the constellation is never legible as a separate
	# layer - it has to hang in the space beside the path, not on it.
	var offset: Vector2 = Vector2(randf_range(-11.0, 11.0), randf_range(-16.0, 4.0))
	_constellation.append({"p": world_pos + offset, "t": _elapsed})


func _expire_constellation() -> void:
	var cutoff: float = _elapsed - STAR_LIFE_S
	var drop: int = 0
	while drop < _constellation.size() and float(_constellation[drop]["t"]) < cutoff:
		drop += 1
	if drop > 0:
		_constellation = _constellation.slice(drop)


## Dots are stored in WORLD space and converted here, because this node moves with
## the wearer. to_local is what keeps them nailed to the floor.
func _draw() -> void:
	if _constellation.size() == 0:
		return
	_use_upright_plane()
	var previous: Vector2 = Vector2.ZERO
	var previous_alpha: float = 0.0
	var has_previous: bool = false
	for entry: Dictionary in _constellation:
		var world: Vector2 = entry["p"]
		var at: Vector2 = to_local(world)
		var life: float = clampf(1.0 - (_elapsed - float(entry["t"])) / STAR_LIFE_S, 0.0, 1.0)
		# Fade in over the first moment so a dot does not pop into being at full
		# brightness right under the wearer's feet.
		var alpha: float = life * smoothstep(0.0, 0.12, 1.0 - life)
		var twinkle: float = 0.65 + 0.35 * sin(_elapsed * 5.0 + world.x * 0.3)
		alpha *= twinkle
		if has_previous and world.distance_to(previous) <= LINK_MAX_PX:
			# The joining line is much fainter than the dots: it should be
			# noticeable only once the eye has already found the stars.
			draw_line(to_local(previous), at, Color(NEBULA_MID, 0.22 * minf(alpha, previous_alpha)), 1.0)
		draw_circle(at, 1.8, Color(NEBULA_HOT, 0.11 * alpha))
		draw_rect(Rect2(at - Vector2(0.5, 0.5), Vector2(1.0, 1.0)), Color(STAR_TINT, 0.95 * alpha))
		previous = world
		previous_alpha = alpha
		has_previous = true
