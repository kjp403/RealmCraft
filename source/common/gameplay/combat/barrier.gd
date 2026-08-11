class_name Barrier
extends StaticBody2D
## A temporary conjured wall that blocks PROJECTILES from any side but never
## movement. The trick is the physics layer: it sits on layer 1, which every
## combat hitbox masks (CombatHit.TARGET_MASK = 7 → layers 1/2/3), while player
## MOVEMENT masks only layers 2-3 — so arrows and bolts stop dead on it
## (CombatHit.try_damage returns BLOCKED for a non-Character body) while
## players, allies and enemies all walk through it untouched.
##
## Spawned on EVERY peer by BarrierAbility (the propagated action.perform path):
## the server copy stops real damage-dealing projectiles, each client copy stops
## its own visual projectiles and draws the wall. Self-destructs after its
## lifetime — no manager needed.

const FILL: Color = Color(0.42, 0.62, 1.0, 0.42)
const EDGE: Color = Color(0.72, 0.86, 1.0, 0.9)

## Set by BarrierAbility before add_child (so _ready builds the right shape).
var length: float = 64.0
var thickness: float = 10.0
var lifetime_s: float = 3.0
## Damage the wall absorbs before it shatters. A projectile carrying MORE than
## the remaining pool is reduced by it and punches through (so a big nuke isn't
## fully eaten by a cheap cast — see absorb / arrow.gd). 0 = invincible wall.
var block_hp: float = 0.0
## Caster who conjured the wall (for shatter damage attribution).
var source: Entity = null
## AoE magic damage dealt when the wall shatters (HP break or timeout). 0 = none.
var shatter_damage: float = 0.0
var shatter_radius: float = 70.0
var arc_scene: PackedScene = preload("res://source/common/gameplay/combat/melee_arc_centered.tscn")

var _hp_left: float = 0.0
var _shattered: bool = false


## Absorbs [param incoming] damage, returns the OVERFLOW that should still pass
## through (0 when the wall ate it all). Called on EVERY peer by arrow.gd — the
## pool drains deterministically because every peer runs the same projectiles
## with the same synced damage, so all walls shatter at the same point with no
## explicit replication. block_hp <= 0 = invincible (always returns 0).
func absorb(incoming: float) -> float:
	if block_hp <= 0.0:
		return 0.0
	var eaten: float = minf(incoming, _hp_left)
	_hp_left -= eaten
	queue_redraw() # weaken the visual as the pool drops
	if _hp_left <= 0.0:
		_shatter()
	return incoming - eaten


func _ready() -> void:
	_hp_left = block_hp
	# On the WORLD layer (like real walls) so projectile hitboxes (which mask world) still
	# stop on it; empty mask so the wall itself never initiates a collision.
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0
	z_index = -1 # behind characters

	var shape: CollisionShape2D = CollisionShape2D.new()
	var rect: RectangleShape2D = RectangleShape2D.new()
	# Thickness runs along local X (the aim axis), length along local Y, so after
	# BarrierAbility rotates us by the aim angle the broad face points back at
	# the shooter — a wall, not a needle.
	rect.size = Vector2(thickness, length)
	shape.shape = rect
	add_child(shape)

	var timer: Timer = Timer.new()
	timer.wait_time = lifetime_s
	timer.one_shot = true
	timer.timeout.connect(_shatter)
	add_child(timer)
	timer.start()
	queue_redraw()


## Shatter pulse: server deals AoE magic damage, then the wall frees itself.
## Idempotent so HP-break and timeout can't double-fire.
func _shatter() -> void:
	if _shattered:
		return
	_shattered = true
	if GameMode.is_world_server() and shatter_damage > 0.0 and source != null \
			and is_instance_valid(source) and arc_scene != null and get_parent() != null:
		var arc: MeleeArc = arc_scene.instantiate()
		arc.source = source
		var shape_node: CollisionShape2D = arc.get_node_or_null(^"CollisionShape2D") as CollisionShape2D
		if shape_node != null and shape_node.shape is CircleShape2D:
			var circle: CircleShape2D = shape_node.shape.duplicate()
			circle.radius = shatter_radius
			shape_node.shape = circle
		arc.damage = shatter_damage
		arc.damage_type = CombatHit.DAMAGE_MAGIC
		get_parent().add_child(arc)
		arc.global_position = global_position
	queue_free()


func _draw() -> void:
	# Fade toward transparent as the pool drains so a near-dead wall reads as
	# fragile. Full alpha when invincible (block_hp <= 0).
	var strength: float = 1.0 if block_hp <= 0.0 else clampf(_hp_left / block_hp, 0.15, 1.0)
	var rect: Rect2 = Rect2(-thickness * 0.5, -length * 0.5, thickness, length)
	draw_rect(rect, Color(FILL, FILL.a * strength))
	draw_rect(rect, Color(EDGE, EDGE.a * strength), false, 2.0)
