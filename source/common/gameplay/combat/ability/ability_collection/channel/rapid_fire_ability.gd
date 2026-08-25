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

## Deadeye pairing (docs/bow.md): charging Deadeye then opening Rapid Fire consumes
## the armed shot to buff the WHOLE barrage instead of a single arrow — a real payoff
## for setting it up first. Consumed once at channel start; reset every use_ability
## so an un-armed Rapid Fire is unaffected. Per-weapon-instance (ability resources
## are duplicated on equip), mirrors ChargeAbility's own instance state.
var _armed_damage_mult: float = 1.0
var _armed_pierce: int = 0
var _armed_speed_mult: float = 1.0


func use_ability(user: Entity, direction: Vector2) -> void:
	_armed_damage_mult = 1.0
	_armed_pierce = 0
	_armed_speed_mult = 1.0
	if user is Character:
		var armed: Dictionary = ShotOverrideAbility.take_armed(user as Character)
		if not armed.is_empty():
			_armed_damage_mult = float(armed.get("mult", 1.0))
			_armed_pierce = int(armed.get("pierce", 0))
			_armed_speed_mult = float(armed.get("speed", 1.0))
	super.use_ability(user, direction)


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
	projectile.speed = projectile_speed * _armed_speed_mult
	projectile.source = caster
	projectile.damage = caster.stats_component.get_stat(Stat.AD) * ad_ratio * _armed_damage_mult
	if _armed_pierce > 0:
		projectile.piercing = true
		projectile.pierce_left = _armed_pierce
	projectile.global_position = AbilityResource.muzzle_position(caster, aim)
	caster.add_child(projectile)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var per_sec: float = ad_ratio / maxf(0.1, tick_interval_s)
	lines.append("%d%% AD/s" % int(round(per_sec * 100.0)))
	lines.append_array(super())
	return lines
