class_name HealBoltAbility
extends BoltShootAbility
## Support twin of BoltShootAbility: fires a bolt that HEALS the first ally it
## hits instead of damaging enemies (see HealBolt for the ally rules). Heal
## amount = [member flat_heal] when set (> 0), otherwise AP × ap_ratio. Flat
## heals keep the mastery panel honest about how much allies actually recover.


## Fixed heal on hit. > 0 replaces the AP × ap_ratio formula so the tooltip can
## show a concrete number (Mending Bolt Power 1 = 25, Power 2 = 50, …).
@export var flat_heal: float = 0.0


func use_ability(user: Entity, direction: Vector2) -> void:
	if user is Character:
		(user as Character).play_action_animation(cast_animation)
	if projectile_scene == null or user == null:
		return
	var aim: Vector2 = _steer_to_ally(user, direction)
	var bolt: HealBolt = projectile_scene.instantiate()
	bolt.top_level = true
	bolt.direction = aim.normalized() if aim != Vector2.ZERO else Vector2.RIGHT
	bolt.speed = speed
	bolt.source = user
	bolt.heal_amount = _heal_amount(user)
	bolt.modulate = bolt_modulate
	bolt.global_position = _spawn_position(user, bolt.direction)
	user.add_child(bolt)


## Prefer a wounded ALLY in radius over raw cursor aim so heals land on your team
## without having to click them. Falls back to the original aim.
##
## "Ally" is the FULL CombatHit.are_allied set (spar teammate, dungeon group,
## overworld party, else guildmate) — the same rule HealBolt uses to decide who
## the heal may land on. It used to be the overworld PARTY only, so healing a
## guildmate never steered and fell back to raw aim — and raw aim is wherever the
## caster is facing, which with a combat lock running is pinned to the monster
## being fought (CombatTargetController.tick drives look_direction every frame).
## That is how heals ended up flying into mobs and scenery instead of allies.
func _steer_to_ally(user: Entity, direction: Vector2) -> Vector2:
	if user is not Player:
		return direction
	var caster: Player = user as Player
	var target: Player = _most_wounded_ally(caster)
	if target == null:
		return direction
	var to_target: Vector2 = target.global_position - caster.global_position
	if to_target == Vector2.ZERO:
		return direction
	return to_target


## Most-wounded living ally within HEAL_STEER_RADIUS, or null when there is none.
## The server resolves allegiance authoritatively through CombatHit.are_allied;
## the client mirrors it via HealBolt.client_is_ally, because player_resource is
## server-only and are_allied would answer "not allied" for every remote player.
func _most_wounded_ally(caster: Player) -> Player:
	var container: Node = caster.get_parent()
	if container == null:
		return null
	var on_server: bool = GameMode.is_world_server()
	var best: Player = null
	var best_missing: float = 0.0
	for node: Node in container.get_children():
		if node == caster or node is not Player:
			continue
		var other: Player = node as Player
		if other.is_dead:
			continue
		if on_server:
			if not CombatHit.are_allied(caster, other):
				continue
		elif not HealBolt.client_is_ally(other):
			continue
		if caster.global_position.distance_to(other.global_position) > PartyService.HEAL_STEER_RADIUS:
			continue
		var sc: StatsComponent = other.stats_component
		if sc == null:
			continue
		var missing: float = sc.get_stat(Stat.HEALTH_MAX) - sc.get_stat(Stat.HEALTH)
		if missing > best_missing:
			best_missing = missing
			best = other
	return best


func _heal_amount(user: Entity) -> float:
	if flat_heal > 0.0:
		return flat_heal
	return maxf(0.0, _wielder_ap(user) * ap_ratio)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if flat_heal > 0.0:
		lines.append("heals allies for %s" % fmt_num(flat_heal))
	else:
		lines.append("heals allies for %d%% AP" % int(round(ap_ratio * 100.0)))
	return lines
