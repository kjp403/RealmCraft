class_name BattleFormAbility
extends AbilityResource
## The Archon / Renekton-R ult: grow bigger (body sprite + hurtbox) with a HUGE temp HP
## wall for a few seconds. Reach is also boosted ([member reach_mult]) so book Arc Strike
## and melee swings still connect against NPCs while enlarged. Resolve branch, book.
##
## Server-authoritative HP + hurtbox scale + revert live in BattleFormState; this spawns
## it and broadcasts the client-side body grow (InstanceClient._on_battleform). Unequipping
## the tome cancels the form early.


## Temp max + current HP granted for the duration (clamped back on expiry).
@export var bonus_hp: float = 180.0
## How much bigger you get. Kept modest so fixed-range hitboxes stay usable.
@export var scale_factor: float = 1.35
## Melee/bolt reach multiplier while formed (Arc Strike is only 80px base).
@export var reach_mult: float = 1.75
## How long you're a free titan AFTER the transformation finishes.
@export var buff_duration_s: float = 8.0
## The transformation is SEQUENCED (a channeled colossus entrance): first the rune builds
## on the ground for [member rune_build_s], THEN the body grows over [member grow_s] (rune
## at full), then the rune fades. You're FROZEN for the whole wind-up — its own counterplay,
## since enemies see it coming. HP + hurtbox apply at once on the server (you're a wall
## while vulnerable). The total form lasts wind-up + buff_duration_s.
@export var rune_build_s: float = 1.0
@export var grow_s: float = 1.2


func use_ability(user: Entity, _direction: Vector2) -> void:
	if not GameMode.is_world_server() or user is not Player:
		return
	var caster: Player = user as Player
	# Replace any live form instead of stacking.
	BattleFormState.cancel_on(caster)
	# Total form time = the wind-up (rune build + grow) + the free-titan duration.
	var total: float = rune_build_s + grow_s + buff_duration_s
	var state: BattleFormState = BattleFormState.new()
	state.caster = caster
	state.bonus_hp = bonus_hp
	state.scale_factor = scale_factor
	state.reach_mult = reach_mult
	state.duration = total
	caster.add_child(state)
	# Tell every client to run the transformation + grow for the total time.
	if WorldServer.curr == null or caster.player_resource == null:
		return
	var map: Node = caster.get_parent()
	if map == null or map.get_parent() == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"battleform.start", {
			"p": int(caster.player_resource.current_peer_id),
			"d": total,
			"sc": scale_factor,
			"rb": rune_build_s,
			"g": grow_s,
		}),
		map.get_parent().name
	)


func extra_stat_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("+%d max health" % int(bonus_hp))
	lines.append("+%d%% size" % int(round((scale_factor - 1.0) * 100.0)))
	lines.append("+%d%% reach" % int(round((reach_mult - 1.0) * 100.0)))
	lines.append("%ss" % fmt_num(buff_duration_s))
	return lines
