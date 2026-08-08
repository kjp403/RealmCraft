class_name MeleeAttack
extends MobAttack
## The classic swing, extracted verbatim from HostileNpc (refactor P2): flash
## the range circle on every client (rp_attack) and damage every living
## hostile player inside it — a small AoE, each hit mitigated by the target's
## armor in take_damage. The swing always happens (telegraph included) even if
## everyone stepped out; whiffing IS the counterplay.

## Strike radius. 0 = the mob's engagement range (distance_to_attack), which
## is what every existing melee mob used.
@export var radius: float = 0.0


func _fire(npc) -> bool:
	var strike_radius: float = radius if radius > 0.0 else float(npc.distance_to_attack)
	npc.replicate_visual(&"rp_attack", [strike_radius])
	# Play a skin "attack" clip when authored (Mecha Golem, etc.); no-op for
	# skins that only ship idle/run/death.
	npc.replicate_visual(&"rp_play_skin_anim", [&"attack"])
	var damage: float = npc.stats_component.get_stat(Stat.AD)
	for candidate: Player in npc._strike_candidates():
		if npc._is_target_valid(candidate) and npc._is_hostile_to(candidate) \
				and npc.global_position.distance_to(candidate.global_position) <= strike_radius:
			candidate.take_damage(damage, npc)
	return true
