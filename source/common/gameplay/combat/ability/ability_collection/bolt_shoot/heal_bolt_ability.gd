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
	var bolt: HealBolt = projectile_scene.instantiate()
	bolt.top_level = true
	bolt.direction = direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT
	bolt.speed = speed
	bolt.source = user
	bolt.heal_amount = _heal_amount(user)
	bolt.modulate = bolt_modulate
	bolt.global_position = _spawn_position(user)
	user.add_child(bolt)


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
