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

## Steady Aim pairing (docs/bow.md): the passive already rewards a full draw
## released without moving (ChargeAbility.release_ability). Rapid Fire is a
## MOBILE channel (you can walk at half speed), so it mirrors that same
## reward: plant where you opened it and stay put for the whole barrage —
## every arrow that tick gets the passive's bonus, not just a single shot.
## Position is latched once at channel start; per-weapon-instance state
## (ability resources are duplicated on equip), same pattern as ChargeAbility.
var _channel_start_pos: Vector2


func use_ability(user: Entity, direction: Vector2) -> void:
	if user is Character:
		_channel_start_pos = (user as Character).global_position
	super.use_ability(user, direction)


## Client-visual twin of the damage check in [method channel_tick] — callers must
## also confirm the channel is actually running (e.g. LocalPlayer._channeling),
## since a stale latched position alone can't tell an idle resource from a live one.
func is_planted(entity: Entity) -> bool:
	return entity != null and entity.global_position.distance_to(_channel_start_pos) <= 6.0


func channel_tick(caster: Character) -> void:
	if not GameMode.is_world_server() or not is_instance_valid(caster):
		return
	if caster.get_parent() == null or projectile_scene == null:
		return
	var aim: Vector2 = Vector2.from_angle(caster.pivot)
	if caster.flipped:
		aim.x = -aim.x
	# caster.pivot is the HAND socket rotation: it lerps toward the cursor at
	# 17.5 rad/s and only reaches the server over a 20 Hz sync, so a real arrow
	# fired straight down that vector visibly trails a moving target — the wide
	# melee arcs (Lightning Lash) never show this because their hitbox eats the
	# error. Snap onto whatever's ALREADY fighting us — authoritative, no lag,
	# and safe: only a hostile that has targeted this caster, same rule
	# AimAssist uses client-side, so this can't drag a stray mob into the fight.
	var locked: HostileNpc = _engaged_hostile(caster)
	if locked != null:
		var to_target: Vector2 = locked.global_position - caster.global_position
		if to_target != Vector2.ZERO and absf(aim.angle_to(to_target)) <= deg_to_rad(35.0):
			aim = to_target.normalized()
	var damage: float = caster.stats_component.get_stat(Stat.AD) * ad_ratio
	if is_planted(caster):
		var steady: float = caster.stats_component.get_stat(&"steady_aim")
		if steady > 0.0:
			damage *= 1.0 + steady / 100.0
	var projectile: Projectile = projectile_scene.instantiate()
	projectile.top_level = true
	projectile.direction = aim
	projectile.speed = projectile_speed
	projectile.source = caster
	projectile.damage = damage
	projectile.global_position = AbilityResource.muzzle_position(caster, aim)
	caster.add_child(projectile)


## Nearest living hostile that has THIS caster as its target — mirrors
## AimAssist._is_eligible's "already committed to the fight" rule, just
## server-side and authoritative. Walks both buckets hostiles live in
## (CombatTargetController.find_nearest_hostile does the same client-side).
func _engaged_hostile(caster: Character) -> HostileNpc:
	var map: Node = caster.get_parent()
	if map is not Map:
		return null
	var container: ReplicatedPropsContainer = (map as Map).replicated_props_container
	if container == null:
		return null
	var best: HostileNpc = null
	var best_dist: float = 260.0
	var candidates: Array = container.get_children()
	candidates.append_array(container.dynamic_nodes.values())
	for node: Variant in candidates:
		var npc: HostileNpc = node as HostileNpc
		if npc == null or not is_instance_valid(npc) or npc.is_dead or npc.targeted_player != caster:
			continue
		var dist: float = caster.global_position.distance_to(npc.global_position)
		if dist < best_dist:
			best_dist = dist
			best = npc
	return best


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	var per_sec: float = ad_ratio / maxf(0.1, tick_interval_s)
	lines.append("%d%% AD/s" % int(round(per_sec * 100.0)))
	lines.append_array(super())
	return lines
