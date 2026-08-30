extends CosmeticTrailPreset
## GOLD TRAIL. A rich additive gold ribbon behind the wearer, spilling dust and
## cut-diamond sparkles onto the floor as they go.
##
## The ribbon is additive, which on a warm palette over dark tiles is what reads
## as polished metal rather than as a yellow crayon line. The risk with additive
## on gold is that it blows straight to white, so the gradient starts at a deep
## bronze and only reaches pale gold at the very head - the brightness is spent at
## the wearer's heels, where the eye already is, and nowhere else.
##
## The dust decals matter as much as the particles. Sparkles alone hang in the air
## and vanish, and a rich cosmetic should leave the floor looking like something
## expensive passed over it. The DUST decal variant is grains only, never a solid
## disc, specifically so a dropped mark can never be mistaken for a coin pickup.

const RIBBON_WIDTH: float = 6.0
const BRONZE: Color = Color(0.55, 0.33, 0.06)
const GOLD: Color = Color(1.0, 0.78, 0.26)
const PALE_GOLD: Color = Color(1.0, 0.96, 0.78)

const DUST_LIFE_S: float = 1.4
const DUST_SIZE: float = 20.0

var _ribbon: Line2D
var _dust: CPUParticles2D
var _sparkles: CPUParticles2D


func _build() -> void:
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 0.85, 1.0])
	ramp.colors = PackedColorArray([
		Color(BRONZE, 0.0),
		Color(BRONZE, 0.5),
		Color(GOLD, 0.8),
		Color(PALE_GOLD, 0.95),
	])
	_ribbon = _add_ribbon(RIBBON_WIDTH, ramp, true)
	_build_dust()
	_build_sparkles()


## Fine gold dust settling along the path - the low, dense layer.
func _build_dust() -> void:
	var p: CPUParticles2D = _add_world_emitter(16, 1.1, VfxTextures.dot(6))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 5.0
	p.direction = Vector2(0, -1)
	p.spread = 120.0
	p.gravity = Vector2(0, 90.0) # dust has weight; it settles rather than floats
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 26.0
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.8
	p.color_ramp = _fade_ramp(GOLD, 0.85)
	p.material = _additive()
	_dust = p


## Cut diamonds: fewer, bigger, tumbling, and much brighter than the dust. They
## are the layer that catches the eye; the dust is what they are set in.
func _build_sparkles() -> void:
	var p: CPUParticles2D = _add_world_emitter(7, 1.6, VfxTextures.diamond(7))
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2(0, 40.0)
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 34.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	# Fast tumble: a facet catching the light is a flash, not a glow.
	p.angular_velocity_min = -260.0
	p.angular_velocity_max = 260.0
	var ramp: Gradient = Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.6, 1.0])
	ramp.colors = PackedColorArray([
		Color(PALE_GOLD, 0.0), Color(PALE_GOLD, 1.0), Color(GOLD, 0.7), Color(BRONZE, 0.0),
	])
	p.color_ramp = ramp
	p.material = _additive()
	_sparkles = p


func _tick(delta: float) -> void:
	super(delta)
	_ribbon.points = path_points()
	var moving: bool = is_moving()
	if _dust != null:
		_dust.emitting = moving
	if _sparkles != null:
		_sparkles.emitting = moving


func _on_step(world_pos: Vector2, _heading_dir: Vector2) -> void:
	_drop_decal(world_pos, GroundDecal.Variant.DUST, GOLD, DUST_SIZE, DUST_LIFE_S)
