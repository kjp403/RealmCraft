class_name ShieldWard
extends Node2D
## Client-side "I am warded" indicator for Heavy Weapons' Spectral Ward — a ring of
## semi-translucent spectral shields ORBITING the tank, plus a faint containment
## circle. Frees itself after [member duration] (the client times it from the cast
## echo, same as [GuardAura] — there is no "buff ended" RPC).
##
## Deliberately an orbiting BUBBLE and not a floor aura, and deliberately distinct
## from [GuardAura]: Last Stand buffs armor (a stance, so a ground ring reads
## honestly), while the ward is a flat damage cut plus a reflect that is ON or
## OFF — and an attacker needs to be able to see that hitting this target hurts.
## Players need
## to read "that tank is mitigating right now" from across an arena at a glance,
## and a spinning object above the floor is the only part of this HUD-less
## vocabulary that survives standing in a boss's own ground telegraph.
##
## Drawn rather than sprited so the shield COUNT and colour can carry the tier
## (one shield at rank 1, three at the capstone) with no new art per rank.

## Node name on the caster. One ward at a time: a re-cast replaces this node
## rather than leaving two orbits spinning out of phase on one body.
const NODE_NAME: StringName = &"ShieldWard"

## Seconds the ward lasts — matches the server-side buff exactly.
var duration: float = 6.0
## How many shields orbit. The cheapest tier tell there is: you can count them.
var shield_count: int = 3
## Orbit radius in px, measured from the body origin (which sits at the feet).
var radius: float = 20.0
## Full orbits per second.
var spin_speed: float = 0.55
var color: Color = Color(0.55, 0.78, 1.0)

## Height above the feet the orbit plane sits at, so the shields ring the TORSO
## rather than scraping the ground the character stands on.
const ORBIT_HEIGHT: float = -9.0
## Vertical squash of the orbit — the same 0.55 the floor auras use, so the ward
## reads as lying in the game's ground plane instead of facing the camera.
const ORBIT_SQUASH: float = 0.45
## Half-width / half-height of one drawn shield, in px.
const SHIELD_W: float = 4.5
const SHIELD_H: float = 6.5

var _elapsed: float = 0.0


func _ready() -> void:
	# Above the floor auras but below the body, so a ward and a Last Stand ring
	# can be up at once and still read as two separate things.
	z_index = -1


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()
	if _elapsed >= duration:
		queue_free()


func _draw() -> void:
	var life: float = clampf(_elapsed / maxf(0.01, duration), 0.0, 1.0)
	# Ease in over the first ~0.2s and out over the last ~0.4s, so the ward
	# never pops in or vanishes on a frame boundary.
	var edge: float = minf(life * 5.0, minf((1.0 - life) * 2.5, 1.0))
	if edge <= 0.0:
		return

	# Containment circle: a faint squashed ring the shields ride on. Sells the
	# orbit as one object rather than N unrelated floating icons.
	draw_set_transform(Vector2(0.0, ORBIT_HEIGHT), 0.0, Vector2(1.0, ORBIT_SQUASH))
	draw_arc(
		Vector2.ZERO, radius, 0.0, TAU, 40,
		Color(color.r, color.g, color.b, 0.22 * edge), 1.0, true
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var spin: float = _elapsed * spin_speed * TAU
	for i: int in maxi(1, shield_count):
		var angle: float = spin + TAU * float(i) / float(maxi(1, shield_count))
		var pos: Vector2 = Vector2(
			cos(angle) * radius,
			ORBIT_HEIGHT + sin(angle) * radius * ORBIT_SQUASH
		)
		# Shields on the FAR side of the orbit (sin < 0 = behind the body) fade
		# and shrink. Without that the ring reads as a flat wheel pasted on the
		# sprite instead of something going around it.
		var depth: float = (sin(angle) + 1.0) * 0.5 # 0 = behind, 1 = in front
		var scale_f: float = 0.78 + 0.32 * depth
		var alpha: float = edge * (0.34 + 0.46 * depth)
		_draw_shield(pos, scale_f, alpha)


## One heater-shield silhouette: a filled translucent body plus a brighter rim,
## centred on [param at]. Kept as a polygon (not a texture) so tinting it per
## tier costs nothing.
func _draw_shield(at: Vector2, scale_f: float, alpha: float) -> void:
	var w: float = SHIELD_W * scale_f
	var h: float = SHIELD_H * scale_f
	var points: PackedVector2Array = PackedVector2Array([
		at + Vector2(-w, -h),
		at + Vector2(w, -h),
		at + Vector2(w, h * 0.15),
		at + Vector2(0.0, h),
		at + Vector2(-w, h * 0.15),
	])
	draw_colored_polygon(points, Color(color.r, color.g, color.b, 0.38 * alpha))
	# Closed outline — draw_polyline does not close the loop on its own, and an
	# open shield silhouette reads as a broken shard.
	var rim: PackedVector2Array = points.duplicate()
	rim.append(points[0])
	draw_polyline(rim, Color(color.r, color.g, color.b, 0.95 * alpha), 1.0, true)
