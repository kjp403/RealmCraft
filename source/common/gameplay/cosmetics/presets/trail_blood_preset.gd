extends CosmeticTrailPreset
## BLOOD TRAIL. A jagged crimson streak dragged along the wearer's path, with
## splatter bursting onto the tiles along the direction they were moving.
##
## The streak is a Line2D fed from the sampled path, but every point is pushed
## SIDEWAYS off that path by a fixed amount before it is drawn. That jitter is the
## whole character of the effect: a smooth ribbon reads as magic or as speed,
## while a torn edge reads as something being dragged and torn. The offsets are
## derived from each point's own world position rather than rolled per frame, so
## the tear stays put on the floor while the wearer runs on - re-rolling would
## make the whole streak boil, which reads as a rendering fault.
##
## The splatter uses the decal shader's heading-biased variant, so droplets are
## thrown FORWARD along the step rather than blooming in a circle. A symmetric
## splash looks like something fell straight down; a biased one looks like
## something moving fast flung it.

const STREAK_TINT: Color = Color(0.55, 0.05, 0.07)
const STREAK_BRIGHT: Color = Color(0.80, 0.13, 0.14)
const SPLAT_TINT: Color = Color(0.66, 0.07, 0.09)

const STREAK_WIDTH: float = 5.0
## Peak sideways tear, in px. Big enough to be obviously ragged at 64 px art,
## small enough that the streak still traces a recognisable path.
const JITTER_PX: float = 2.6
const SPLAT_LIFE_S: float = 1.6
const SPLAT_SIZE: float = 24.0

var _streak: Line2D
var _spray: CPUParticles2D


func _build() -> void:
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	ramp.colors = PackedColorArray([
		Color(STREAK_TINT, 0.0),   # the tail has already soaked in
		Color(STREAK_TINT, 0.65),
		Color(STREAK_BRIGHT, 0.9), # freshest at the wearer's heels
	])
	_streak = _add_ribbon(STREAK_WIDTH, ramp)
	_build_spray()


## Fine spray thrown off the streak. World-space, so it lands and stays put.
func _build_spray() -> void:
	var p: CPUParticles2D = _add_world_emitter(10, 0.8, VfxTextures.pip(6))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0
	p.spread = 65.0
	p.gravity = Vector2(0, 260.0)
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 60.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	p.color_ramp = _fade_ramp(STREAK_BRIGHT, 0.9)
	_spray = p


func _tick(delta: float) -> void:
	super(delta)
	_update_streak()
	if _spray != null:
		_spray.emitting = is_moving()
		# Thrown BACKWARD from the direction of travel, the way anything shed by a
		# moving body is. direction is in world space because the emitter is.
		_spray.direction = -_heading


## Rebuild the torn streak from the current path. Cheap enough to do every frame:
## the path is capped by PATH_LIFE, so this is a couple of dozen points at most.
func _update_streak() -> void:
	var path: PackedVector2Array = path_points()
	if path.size() < 2:
		_streak.clear_points()
		return
	var torn: PackedVector2Array = PackedVector2Array()
	for i: int in path.size():
		var at: Vector2 = path[i]
		# Perpendicular to the local direction of travel, so the tear is across
		# the streak rather than along it.
		var ahead: Vector2 = path[mini(i + 1, path.size() - 1)]
		var behind: Vector2 = path[maxi(i - 1, 0)]
		var along: Vector2 = (ahead - behind)
		var side: Vector2 = Vector2(-along.y, along.x).normalized()
		torn.append(at + side * _tear_at(at))
	_streak.points = torn


## A stable pseudo-random offset for a world position. Hashing the POSITION, not
## the index, is what pins the tear to the floor: as points age out of the front
## of the path their indices shift, and an index hash would slide the whole tear
## along the streak every frame.
func _tear_at(at: Vector2) -> float:
	var h: float = sin(at.x * 12.9898 + at.y * 78.233) * 43758.5453
	return (fposmod(h, 1.0) - 0.5) * 2.0 * JITTER_PX


func _on_step(world_pos: Vector2, _heading_dir: Vector2) -> void:
	# _drop_decal stamps the current heading onto the decal, and the shader throws
	# its droplets along it - that is what puts the splash on the movement vector
	# instead of in a ring.
	_drop_decal(
		world_pos, GroundDecal.Variant.SPLATTER, SPLAT_TINT,
		SPLAT_SIZE * randf_range(0.8, 1.25), SPLAT_LIFE_S
	)
