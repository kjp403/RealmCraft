class_name RapidFireAbility
extends ChannelAbility
## RAPID FIRE: the bow's answer to Lightning Lash — hold and it keeps loosing arrows in
## your aim direction at a fixed interval, rather than one armed shot. Replaces Arrow
## Storm, which was a wider-cone reskin of Multishot; this is a genuinely different verb
## (spam) instead of another "arm one big volley" pick. Domination, bow.
##
## Each tick spawns a real Projectile (arrow.tscn) along the live aim, AD-scaled — no
## charge/hold curve, no ammo consumption (matches Multishot/Deadeye: the mastery pick
## itself is the cost, not the arrow).


## Damage per arrow = caster AD × this.
@export var ad_ratio: float = 0.45
@export var projectile_scene: PackedScene = preload("res://source/common/gameplay/items/weapons/bow/arrow.tscn")
@export var projectile_speed: float = 500.0


func channel_tick(caster: Character) -> void:
	if not GameMode.is_world_server() or not is_instance_valid(caster):
		return
	if caster.get_parent() == null or projectile_scene == null:
		return
	var aim: Vector2 = Vector2.from_angle(caster.pivot)
	if caster.flipped:
		aim.x = -aim.x
	var projectile: Projectile = projectile_scene.instantiate()
	projectile.top_level = true
	projectile.direction = aim
	projectile.speed = projectile_speed
	projectile.source = caster
	projectile.damage = caster.stats_component.get_stat(Stat.AD) * ad_ratio
	projectile.global_position = AbilityResource.muzzle_position(caster, aim)
	caster.add_child(projectile)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var per_sec: float = ad_ratio / maxf(0.1, tick_interval_s)
	lines.append("%d%% AD/s" % int(round(per_sec * 100.0)))
	lines.append_array(super())
	return lines
