extends CompanionPreset
## BABY GRIFFIN. Eagle at the front, lion cub at the back: a white-headed,
## golden-beaked griffin chick flapping along at the wearer's shoulder on
## brown feathered wings, lion tail swishing. When they stop it tucks its wings
## and hovers beside them - and every few seconds rears back, throws its wings
## wide with a big flap, and sheds a little flurry of feathers.
##
## DETAILED PASS. Painted on a [PixelCanvas] (wings up, wings down, wings tucked,
## wings spread): tawny lion body with a paler belly, white head and neck ruff,
## a hooked gold beak, gold talons, layered wing feathers and a tail tuft.
## Live on top: the flap timing and a feather-drift particle burst.

const FOLLOW: Vector2 = Vector2(0, -36)
const FOLLOW_PX: float = 16.0
const IDLE_AFTER_S: float = 0.8
const DISPLAY_EVERY_S: float = 4.0
const DISPLAY_S: float = 0.9

const TAWNY: Color = Color(0.86, 0.66, 0.38)
const BELLY: Color = Color(0.98, 0.86, 0.62)
const HEAD: Color = Color(0.97, 0.96, 0.92)
const BEAK: Color = Color(1.0, 0.78, 0.26)
const WING: Color = Color(0.55, 0.36, 0.22)
const WING_LIGHT: Color = Color(0.74, 0.54, 0.34)
const TUFT: Color = Color(0.46, 0.28, 0.16)

const W: int = 26
const H: int = 22

var _facing: float = 1.0
var _feathers: CPUParticles2D


func _build() -> void:
	stiffness = 65.0
	damping = 10.0
	add_body_layer(_paint_griffin, false, 0)
	var p: CPUParticles2D = CPUParticles2D.new()
	p.amount = 8
	p.lifetime = 1.2
	p.local_coords = false
	p.one_shot = false
	p.explosiveness = 0.9
	p.texture = VfxTextures.leaf(7)
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.position = Vector2(0, -12)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 6.0
	p.direction = Vector2(0, -1)
	p.spread = 120.0
	p.gravity = Vector2(0, 18.0)
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 20.0
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 0.8
	p.color_ramp = _fade_ramp(WING_LIGHT, 1.0)
	p.emitting = false
	body.add_child(p)
	_feathers = p


func target_local(_delta: float) -> Vector2:
	set_in_front(true)
	if absf(_heading.x) > 0.2:
		_facing = signf(_heading.x)
	if still_for < IDLE_AFTER_S:
		return FOLLOW - _heading * FOLLOW_PX + Vector2(0, sin(_elapsed * 7.0) * 1.5)
	return Vector2(-18.0 * _facing, -34.0 + sin(_elapsed * 2.2) * 1.5)


func _displaying() -> bool:
	if still_for < IDLE_AFTER_S + 1.0:
		return false
	return fposmod(still_for - IDLE_AFTER_S - 1.0, DISPLAY_EVERY_S) < DISPLAY_S


static func _frame(pose: String) -> ImageTexture:
	return PixelCanvas.cached("griffin_" + pose, W, H, func(c: PixelCanvas) -> void:
		# Far wing (behind the body), darker.
		match pose:
			"up":
				c.tri(Vector2(9.0, 11.0), Vector2(4.0, 1.0), Vector2(13.0, 5.0), WING.darkened(0.2))
			"down":
				c.tri(Vector2(9.0, 12.0), Vector2(2.0, 20.0), Vector2(12.0, 17.0), WING.darkened(0.2))
			"spread":
				c.tri(Vector2(10.0, 11.0), Vector2(0.0, 2.0), Vector2(3.0, 13.0), WING.darkened(0.2))
		# Lion tail with a dark tuft.
		c.line(Vector2(5.0, 14.0), Vector2(2.0, 11.0), TAWNY.darkened(0.15))
		c.line(Vector2(5.0, 15.0), Vector2(2.0, 12.0), TAWNY.darkened(0.15))
		c.ball(2.0, 10.0, 1.8, 1.8, TUFT)
		# Hind legs and paws.
		c.rect(6.0, 16.0, 2.0, 5.0, TAWNY.darkened(0.12))
		c.rect(9.0, 16.0, 2.0, 5.0, TAWNY)
		# Body and belly.
		c.ball(11.0, 13.5, 6.4, 4.4, TAWNY)
		c.ball(12.5, 15.0, 3.6, 2.4, BELLY, 0.15, 0.1)
		# Eagle front: gold talons, white ruff and head.
		c.rect(14.0, 17.0, 1.0, 4.0, BEAK)
		c.rect(16.0, 17.0, 1.0, 4.0, BEAK)
		c.tri(Vector2(13.0, 12.0), Vector2(20.0, 11.0), Vector2(16.5, 16.0), HEAD)
		c.ball(18.0, 8.0, 4.4, 4.0, HEAD)
		# A little crest of feathers.
		c.tri(Vector2(15.0, 5.0), Vector2(17.0, 4.5), Vector2(14.0, 1.5), HEAD)
		# Hooked beak.
		c.tri(Vector2(21.0, 7.0), Vector2(25.5, 9.0), Vector2(21.0, 10.5), BEAK)
		# Near wing, over the body.
		match pose:
			"up":
				c.tri(Vector2(10.0, 12.0), Vector2(6.0, 0.0), Vector2(15.0, 6.0), WING)
				c.tri(Vector2(10.5, 12.0), Vector2(8.0, 3.0), Vector2(14.0, 7.5), WING_LIGHT)
			"down":
				c.tri(Vector2(10.0, 12.0), Vector2(4.0, 21.0), Vector2(14.0, 18.0), WING)
				c.tri(Vector2(10.5, 12.5), Vector2(6.5, 19.0), Vector2(13.0, 17.0), WING_LIGHT)
			"spread":
				c.tri(Vector2(11.0, 12.0), Vector2(1.0, 4.0), Vector2(5.0, 15.0), WING)
				c.tri(Vector2(11.0, 12.0), Vector2(3.5, 6.0), Vector2(6.0, 13.0), WING_LIGHT)
			_:
				c.ball(10.0, 12.5, 4.8, 3.0, WING)
				c.ball(9.5, 12.0, 3.2, 1.8, WING_LIGHT, 0.1, 0.1)
		c.finish(0.16, 0.24, 0.6)
		# Details.
		c.eye(18.5, 6.5, 2, 2)
		c.px(18.0, 6.5, Color(1.0, 0.75, 0.25))    # gold rim behind the pupil
		c.px(24.0, 10.0, BEAK.darkened(0.45))       # beak hook tip
		c.px(21.5, 8.0, BEAK.darkened(0.3))         # nostril
		c.px(16.5, 10.0, Color(1.0, 0.62, 0.70))
		# Primary-feather notches along the wing edge.
		match pose:
			"up":
				c.px(7.0, 2.0, WING.darkened(0.4))
				c.px(9.0, 3.0, WING.darkened(0.4))
			"down":
				c.px(5.0, 20.0, WING.darkened(0.4))
				c.px(8.0, 20.0, WING.darkened(0.4))
			"spread":
				c.px(2.0, 5.0, WING.darkened(0.4))
				c.px(3.0, 8.0, WING.darkened(0.4))
	)


func _paint_griffin(layer: VfxDrawLayer) -> void:
	var pose: String
	var display: bool = _displaying()
	if display:
		pose = "spread"
	elif still_for >= IDLE_AFTER_S:
		pose = "tuck" if fposmod(_elapsed * 0.9, 1.0) < 0.75 else "down"
	else:
		pose = "up" if fposmod(_elapsed * 2.0, 1.0) < 0.5 else "down"
	_feathers.emitting = display
	PixelCanvas.draw_sprite(layer, _frame(pose), Vector2(0.0, -2.0 if display else 0.0), _facing)
