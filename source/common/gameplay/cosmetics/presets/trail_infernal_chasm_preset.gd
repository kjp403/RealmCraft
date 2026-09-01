extends CosmeticTrailPreset
## INFERNAL CHASM (hellfire). Splits the floor open along the wearer's path and
## throws embers up out of the cracks.
##
## MECHANICAL HOOK: the floor marks are generated GEOMETRY with a lifetime of
## their own, not stamped quads. Every other trail in the set drops a decal - a
## square with a shader on it - which is fine for a puddle or a scorch but cannot
## produce a branching line. A [MagmaFissure] rolls its own crack shape at spawn,
## tears open along its length, cools down a temperature ramp, and frees itself.
##
## No ribbon on this one. A trailing streak would say "something bright went past
## here"; the read wanted is "the ground could not take it", so everything is
## either in the floor or coming out of it, and nothing is attached to the wearer.
##
##   FISSURES  one per step, pinned to world coordinates, alive for 2 s.
##   EMBERS    world-space and left behind, so they rise out of the cracks the
##             wearer has already made rather than following their feet.
##   HEAT      a low, dark orange haze that hangs in the broken air.

const FISSURE_SCRIPT: GDScript = preload("res://source/common/gameplay/cosmetics/presets/magma_fissure.gd")

const EMBER_HOT: Color = Color(1.0, 0.92, 0.62)
const EMBER_MID: Color = Color(1.0, 0.45, 0.06)
const EMBER_DEEP: Color = Color(0.72, 0.10, 0.02)

## Seconds a fissure lives, per the brief.
const FISSURE_LIFE_S: float = 2.0
const FISSURE_LENGTH: float = 30.0

var _embers: CPUParticles2D
var _heat: CPUParticles2D


func _build() -> void:
	_build_embers()
	_build_heat()


## Embers erupting out of the cracks: fast, hot, and thrown almost straight up,
## because they are being forced out of a vent rather than drifting off a fire.
func _build_embers() -> void:
	var p: CPUParticles2D = _add_world_emitter(18, 1.0, VfxTextures.dot(6))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 9.0
	p.direction = Vector2(0, -1)
	p.spread = 24.0
	p.initial_velocity_min = 55.0
	p.initial_velocity_max = 125.0
	# Real gravity, unlike the buoyant embers on Emberfrost: these are thrown, so
	# they have to arc over and come back down or they read as floating sparks.
	p.gravity = Vector2(0, 190.0)
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.9
	var cooling: Curve = Curve.new()
	cooling.add_point(Vector2(0.0, 1.0))
	cooling.add_point(Vector2(1.0, 0.15))
	p.scale_amount_curve = cooling
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
	ramp.colors = PackedColorArray([
		Color(EMBER_HOT, 0.0), Color(EMBER_HOT, 1.0),
		Color(EMBER_MID, 0.85), Color(EMBER_DEEP, 0.0),
	])
	p.color_ramp = ramp
	p.material = _additive()
	_embers = p


## Hot air over the broken ground. Very dim: it exists to stop the space between
## the cracks and the embers being empty, and the moment it is noticeable on its
## own it is competing with the fissures.
func _build_heat() -> void:
	var p: CPUParticles2D = _add_world_emitter(8, 1.6, VfxTextures.puff(16))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 10.0
	p.direction = Vector2(0, -1)
	p.spread = 40.0
	p.gravity = Vector2(0, -26.0)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 24.0
	p.scale_amount_min = 0.9
	p.scale_amount_max = 2.0
	p.color_ramp = _swell_ramp(EMBER_DEEP, Color(EMBER_MID, 0.20), 0.3)
	p.material = _additive()
	_heat = p


func _tick(delta: float) -> void:
	super(delta)
	# Emit only while moving AND only while someone can see it. Fissures already
	# in the world keep burning down on their own clocks either way - the gate is
	# on the source, never on what has already been left behind.
	var producing: bool = is_moving() and _viewer_in_range()
	if _embers != null:
		_embers.emitting = producing
	if _heat != null:
		_heat.emitting = producing


func _on_step(world_pos: Vector2, heading_dir: Vector2) -> void:
	if not _viewer_in_range():
		return
	var fissure: MagmaFissure = FISSURE_SCRIPT.new()
	fissure.life = FISSURE_LIFE_S
	fissure.heading = heading_dir
	fissure.length = FISSURE_LENGTH * randf_range(0.75, 1.25)
	# top_level detaches it from the wearer, so it stays on the tiles that broke.
	fissure.top_level = true
	add_child(fissure)
	# After add_child: a top_level node has no meaningful global transform until
	# it is in the tree.
	fissure.global_position = world_pos
