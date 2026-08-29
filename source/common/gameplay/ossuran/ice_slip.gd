class_name IceSlip
extends RefCounted
## Surface-aware velocity smoothing: momentum on ice, instant response on stone.
##
## Player movement in this project is INSTANT — `velocity = input_direction *
## move_speed` every physics frame, with no acceleration curve anywhere. That is
## the feel the whole game is tuned around, so the single most important property
## of this helper is that it is a NO-OP on every surface but ice: [method step]
## returns the desired velocity unchanged, byte for byte, and no existing map
## changes handling because this file exists.
##
## HOW IT COMPOSES WITH THE COLD. The phase-3 chill reduces MOVE_SPEED, a stat,
## which is already baked into the `desired` vector handed in here. Slip only
## governs how fast you REACH that vector. So the two stack the way they read:
## the cold decides your top speed, the ice decides how long it takes to get
## there and how far you overshoot — and slip can never give back speed the cold
## took away, because it only ever interpolates toward an already-slowed target.
##
## FRAME-RATE INDEPENDENCE. The tuning values are lerp weights "per frame at
## 60fps", which is how they are usually authored and how the brief specifies
## them. Used raw against a variable delta they would make ice grippier on a slow
## machine and slicker on a fast one — a physics difference caused by hardware.
## [method _weight] converts them to the exponential form, so 0.05 means the same
## thing at 30fps, 60fps and 144fps.

## Approach rate toward the input direction while a key is held.
## Low = a long, floaty run-up before you reach full speed.
const ICE_ACCELERATION: float = 0.05
## Decay rate once input stops. Lower than acceleration on purpose: on ice you
## coast for longer than you take to get going, which is what makes stopping the
## dangerous part rather than starting.
const ICE_FRICTION: float = 0.02
## Below this speed a coasting slide is over. Without it the exponential decay
## leaves a fraction of a pixel per frame forever, which reads as a character
## that never quite settles and keeps nudging its own collision.
const REST_SPEED: float = 4.0
## The weights above are authored against this frame rate.
const REFERENCE_FPS: float = 60.0


## The velocity to move with this frame.
##
## [param current] is the body's velocity now, [param desired] is what the input
## asks for (already scaled by MOVE_SPEED, so already carrying any slow), and
## [param surface] comes from [method SurfaceQuery.surface_at].
static func step(
	current: Vector2, desired: Vector2, surface: StringName, delta: float
) -> Vector2:
	if not SurfaceQuery.is_slippery(surface):
		# Every other surface in the game: unchanged, instant, exactly as before.
		return desired

	# Accelerating and coasting are different rates, so which one applies is
	# decided by whether the player is actually asking to move.
	var holding_input: bool = desired.length_squared() > 0.0001
	var rate: float = ICE_ACCELERATION if holding_input else ICE_FRICTION
	var next: Vector2 = current.lerp(desired, _weight(rate, delta))

	# Settle a coast rather than asymptote toward zero forever.
	if not holding_input and next.length() < REST_SPEED:
		return Vector2.ZERO
	return next


## Convert a per-frame-at-60fps lerp weight into one correct for [param delta].
##
## The identity is that surviving fraction compounds: holding (1 - w) per frame
## for N frames leaves (1 - w)^N, so the weight for an arbitrary timestep is
## 1 - (1 - w)^(delta * 60). Anything simpler (w * delta * 60) diverges badly at
## low frame rates and can overshoot past 1.0, which inverts the lerp.
static func _weight(rate: float, delta: float) -> float:
	var frames: float = maxf(0.0, delta) * REFERENCE_FPS
	return clampf(1.0 - pow(1.0 - clampf(rate, 0.0, 1.0), frames), 0.0, 1.0)
