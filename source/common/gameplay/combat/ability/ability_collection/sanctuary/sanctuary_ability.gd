class_name SanctuaryAbility
extends AbilityResource
## PALADIN'S MIGHT — hold the key, aim with the cursor, release to plant a
## consecrated circle that heals the caster and every ally standing in it, every
## tick, for a few seconds.
##
## Deliberately PLACED and not channeled, which is what separates it from the
## book's [HealingAuraAbility]: a channel roots you and dies the moment you move,
## and a tank holding a boss cannot stand still or stop pressing buttons. Dropping
## a zone costs one global cooldown and then keeps working while you go back to
## being hit, which is the only shape of group heal a tank can actually deliver.
##
## Hold-to-aim / release-to-cast (see [member AbilityResource.ground_aimed]);
## falls back to a fixed distance along the aim direction when no cursor point is
## set (AI, gamepad, legacy echoes). Server owns the healing ([HealingField]);
## every peer draws the ring from the action.perform echo, so allies can see the
## circle they are supposed to stand in.


## HP restored to each valid target per tick.
@export var heal_per_tick: float = 4.0
@export var tick_interval_s: float = 1.0
## Seconds the circle lasts once planted.
@export var duration_s: float = 8.0
## Circle size — both the heal reach and the drawn ring.
@export var radius: float = 70.0
## Max cursor distance from the caster when placing (also the no-cursor fallback).
@export var cast_range: float = 120.0
@export var ring_color: Color = Color(1.0, 0.88, 0.55)


func _init() -> void:
	ground_aimed = true


func get_ground_aim_range() -> float:
	return cast_range


func use_ability(user: Entity, direction: Vector2) -> void:
	if user is not Character:
		return
	var caster: Character = user as Character
	var map: Node = caster.get_parent()
	if map == null:
		return
	var target: Vector2
	if has_aim_point:
		target = _clamp_aim(caster.global_position, aim_point)
		# Consume it: the flag is per-CAST state on a shared resource instance, so
		# leaving it set would make the next cast reuse this cast's cursor point.
		has_aim_point = false
	else:
		var dir: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
		target = caster.global_position + dir * cast_range

	if GameMode.is_client():
		var ring: SanctuaryRing = SanctuaryRing.new()
		ring.duration = duration_s
		ring.radius = radius
		ring.color = ring_color
		map.add_child(ring)
		ring.global_position = target

	if not GameMode.is_world_server() or caster is not Player:
		return
	var field: HealingField = HealingField.new()
	field.caster = caster as Player
	field.radius = radius
	field.heal_per_tick = heal_per_tick
	field.tick_interval = tick_interval_s
	field.duration = duration_s
	map.add_child(field)
	field.global_position = target


func _clamp_aim(origin: Vector2, point: Vector2) -> Vector2:
	var offset: Vector2 = point - origin
	if offset.length() > cast_range:
		return origin + offset.normalized() * cast_range
	return point


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("+%s HP/s to allies inside" % fmt_num(heal_per_tick / maxf(0.05, tick_interval_s)))
	lines.append("%ss circle" % fmt_num(duration_s))
	lines.append("%dpx radius" % int(radius))
	return lines
