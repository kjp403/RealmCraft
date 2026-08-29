class_name HealingField
extends Node2D
## A PLANTED healing circle (Heavy Weapons' Paladin's Might): every
## [member tick_interval] it restores [member heal_per_tick] HP to the caster and
## to every ALLY standing inside [member radius], for [member duration] seconds,
## then frees.
##
## The mirror of [SpellField] on the friendly side, and deliberately a separate
## node rather than a flag on it: that one rides the caster and spawns damage
## hitboxes, this one stays where it was dropped and never touches a HurtBox.
## Anchored is the whole point — the tank is going to be dragged around the arena
## by the fight, and a heal zone that followed them would be a personal buff, not
## a place the group can choose to stand.
##
## Server-only (the ring visual is drawn by [SanctuaryRing] on each client).
## "Ally" is the shared [method CombatHit.are_allied] rule — spar teammates,
## dungeon group, overworld party, otherwise guildmates — so a barrier can never
## top up someone you are duelling.

var caster: Player
var radius: float = 70.0
var heal_per_tick: float = 4.0
var tick_interval: float = 1.0
var duration: float = 8.0

var _elapsed: float = 0.0
var _next_tick: float = 0.0


func _ready() -> void:
	_tick() # heal immediately on drop — the barrier is a panic button too


func _process(delta: float) -> void:
	_elapsed += delta
	_next_tick -= delta
	if _next_tick <= 0.0:
		_next_tick = tick_interval
		_tick()
	if _elapsed >= duration:
		queue_free()


func _tick() -> void:
	# A field outlives its caster's ATTENTION but not their existence: healing
	# credit, ally checks and combat-heal bookkeeping all read off the caster.
	if not is_instance_valid(caster) or caster.is_dead or get_parent() == null:
		queue_free()
		return
	if caster.global_position.distance_to(global_position) <= radius:
		caster.apply_heal(heal_per_tick, caster, true)
	for node: Node in get_parent().get_children():
		var target: Player = node as Player
		if target == null or target == caster or target.is_dead:
			continue
		if not CombatHit.are_allied(caster, target):
			continue
		if global_position.distance_to(target.global_position) <= radius:
			target.apply_heal(heal_per_tick, caster, true)
