class_name BarrierAbility
extends AbilityResource
## Conjures a temporary [Barrier] (projectile wall) a short distance ahead of
## the caster, facing the way they aim. Generic — future barriers (ice wall,
## stone shield, ...) just retune the exports + the Barrier colors.
##
## Runs on EVERY peer (no is_world_server gate): the server's wall blocks the
## real damage-dealing projectiles, each client's wall is the visual that also
## stops local projectile visuals. The wall is parented to the MAP (the
## caster's parent), not the caster, so it stays put instead of trailing them.


## How far ahead of the caster the wall appears.
@export var distance: float = 34.0
## Wall span (perpendicular to aim) and depth (along aim).
@export var length: float = 64.0
@export var thickness: float = 10.0
## Seconds the wall persists. Short by design — "blocks a few volleys", not a
## permanent fort.
@export var duration_s: float = 3.0
## Damage the wall absorbs before shattering (overflow punches through). 0 =
## an invincible wall that only expires on time.
@export var block_hp: float = 0.0
## Shatter blast = caster AP × this (fires when the wall breaks or times out).
@export var shatter_ap_ratio: float = 0.0
## Radius of the shatter blast around the wall's centre.
@export var shatter_radius: float = 70.0
@export var cast_animation: StringName


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if block_hp > 0.0:
		lines.append("blocks %s damage" % fmt_num(block_hp))
	if shatter_ap_ratio > 0.0:
		lines.append("%d%% AP shatter" % int(round(shatter_ap_ratio * 100.0)))
	lines.append("%ss wall" % fmt_num(duration_s))
	lines.append("%dpx wide" % int(length))
	return lines


func use_ability(user: Entity, direction: Vector2) -> void:
	if user is Character:
		(user as Character).play_action_animation(cast_animation)
	if user == null:
		return
	var parent: Node = user.get_parent()
	if parent == null:
		return
	var dir: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT

	var barrier: Barrier = Barrier.new()
	barrier.length = length
	barrier.thickness = thickness
	barrier.lifetime_s = duration_s
	barrier.block_hp = block_hp
	barrier.source = user
	barrier.shatter_radius = shatter_radius
	if shatter_ap_ratio > 0.0 and user is Character \
			and (user as Character).stats_component != null:
		barrier.shatter_damage = (user as Character).stats_component.get_stat(Stat.AP) * shatter_ap_ratio
	parent.add_child(barrier)
	barrier.global_position = user.global_position + dir * distance
	barrier.rotation = dir.angle()
