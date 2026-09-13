class_name GroundCompanionPreset
extends CompanionPreset
## Base for companions that live ON THE FLOOR and hop after the wearer (Slime,
## Mimic) rather than flying.
##
## Two things differ from a flyer, and both are handled here so each hopper is
## only its drawing:
##
##   HOPS     the body slides along the floor on the usual spring; the hop is a
##            purely visual lift ([member hop_height]) and squash/stretch
##            ([member squash]) layered on top, driven by how fast it is going.
##            Faking the hop in the drawing keeps the floor position honest, so
##            the shadow never leaves the ground.
##   DEPTH    a floor companion is in front of the wearer when it is lower on
##            screen than their feet and behind when higher - the same rule as
##            any two things standing on a floor.
##
## Subclasses draw with their feet on (0, 0) of the body, and apply
## [method apply_hop] first so the lift and squash come for free.

## Where it sits relative to the feet: behind the wearer's heading, on the floor.
const FOLLOW_PX: float = 20.0
## Idle spot beside the wearer, on the side they last came from.
const SIT_PX: Vector2 = Vector2(16.0, 3.0)
## Hops per second; a frog leaps slowly, a slime bounces quickly.
var hop_rate: float = 3.0
## Hop height in px; a subclass can lower it (a duckling waddles, a slime bounces).
var hop_peak: float = 6.0
## Below this body speed it stops hopping and settles.
const HOP_SPEED: float = 10.0

## Px above the floor this frame.
var hop_height: float = 0.0
## Horizontal scale this frame; vertical is its inverse, so volume looks kept.
var squash: float = 1.0
## 0 at take-off, 0.5 at the top, 1 at landing, while hopping.
var hop_phase: float = 0.0
## Which way it faces: +1 right, -1 left.
var facing: float = 1.0

var _hopping: bool = false
var _side: float = -1.0


func _ready() -> void:
	# Before super(): that runs the subclass _build, which may retune these.
	stiffness = 45.0
	damping = 11.0
	super()


## Hide behind the owner's legs, on the side they are not facing, a touch further
## from the camera so their body covers the pet.
func hide_spot() -> Vector2:
	return Vector2(7.0 * _away_side(), -3.0)


func target_local(_delta: float) -> Vector2:
	if is_moving():
		if absf(_heading.x) > 0.2:
			_side = -signf(_heading.x)
		var behind: Vector2 = -_heading * FOLLOW_PX
		return Vector2(behind.x, behind.y * GROUND_SQUASH + 2.0)
	return Vector2(SIT_PX.x * _side, SIT_PX.y)


func _tick(delta: float) -> void:
	super(delta)
	var vel: Vector2 = body_velocity()
	var speed: float = vel.length() / maxf(0.001, global_scale.x)
	if absf(vel.x) > 4.0:
		facing = signf(vel.x)
	if speed > HOP_SPEED:
		_hopping = true
	if _hopping:
		hop_phase += delta * hop_rate
		if hop_phase >= 1.0:
			# Always finish the hop in the air before settling: stopping mid-hop
			# would snap it to the floor.
			hop_phase = fposmod(hop_phase, 1.0)
			if speed <= HOP_SPEED:
				_hopping = false
				hop_phase = 0.0
	if _hopping:
		hop_height = sin(hop_phase * PI) * hop_peak
		# Stretch tall in the air, squash flat at both ends of the hop.
		var air: float = sin(hop_phase * PI)
		squash = lerpf(1.25, 0.85, air)
	else:
		hop_height = 0.0
		squash = 1.0 + 0.06 * sin(_elapsed * 4.0)
	# Floor depth: lower on screen than the feet means in front.
	set_in_front(body.global_position.y > global_position.y)


func is_hopping() -> bool:
	return _hopping


## Call first in a draw: shadow on the floor, then the transform that lifts and
## squashes everything drawn after it. Shapes should sit with their base on y=0.
func apply_hop(layer: VfxDrawLayer, shadow_w: float) -> void:
	## [param shadow_w] 0 skips the shadow - for the second and later layers of
	## one companion, which want the transform but must not stack shadows.
	if shadow_w > 0.0:
		layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, GROUND_SQUASH))
		var shrink: float = 1.0 - hop_height / 18.0
		layer.draw_circle(Vector2.ZERO, shadow_w * shrink, Color(0.0, 0.0, 0.0, 0.28))
	layer.draw_set_transform(Vector2(0.0, -hop_height), 0.0, Vector2(squash, 1.0 / squash))
