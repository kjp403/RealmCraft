class_name TimedDebuff
extends Node
## A server-side timed weakening attached to its VICTIM as a child node, the
## same shape as [DamageOverTime]: it dies with the victim and needs no manager,
## and re-applying the same kind REFRESHES rather than stacking.
##
## WHY THIS EXISTS AND NOT [BuffService]
## BuffService stores its entries on [PlayerResource], so it can only ever touch
## a Player. Arrows are mostly shot at NPCs, and a slow or an armour shred that
## silently does nothing to a mob is not a debuff, it is a bug that looks like
## balance. This works on anything that is a [Character].
##
## Two of the three things it can weaken are not stats at all on an NPC:
## [member HostileNpc.move_speed] and [member HostileNpc.attack_cooldown] are
## plain fields, not entries in a StatsComponent, so they are scaled and
## restored directly. ARMOR is a real stat on both sides and goes through
## `modify_stat`.
##
## EVERY FIELD RECORDS WHAT IT ACTUALLY APPLIED. Reverting a change that was
## never applied silently drains the victim's stat block — the same trap
## BuffService documents for suppressed buffs.

## Armour removed for the duration. 0 = untouched.
var armor_shred: float = 0.0
## Fraction of movement removed, 0-1. 0 = untouched.
var move_slow: float = 0.0
## Fraction of attack SPEED removed, 0-1 — implemented as a longer cooldown.
var attack_slow: float = 0.0
## Effect family, for the status HUD and the refresh lookup.
var kind: StringName

var _remaining_ticks: int = 0
## What was actually taken, so expiry gives back exactly that and never more.
var _applied_armor: float = 0.0
var _applied_move: float = 0.0
var _applied_attack: float = 0.0
var _reverted: bool = false


## Attach (or refresh) a debuff on [param victim]. Server-side only.
static func apply(
	victim: Character,
	effect_kind: StringName,
	duration_s: float,
	armor: float = 0.0,
	move: float = 0.0,
	attack: float = 0.0
) -> void:
	if victim == null or not victim.multiplayer.is_server() or duration_s <= 0.0:
		return
	if armor <= 0.0 and move <= 0.0 and attack <= 0.0:
		return
	var node_name: String = "Debuff_%s" % effect_kind
	var existing: TimedDebuff = victim.get_node_or_null(NodePath(node_name)) as TimedDebuff
	if existing != null:
		# Refresh the clock, keep the ORIGINAL magnitudes. Re-applying the
		# weakening on top of itself would let arrow spam stack a mob to zero
		# armour, which is exactly what "refresh, never stack" exists to stop.
		existing._remaining_ticks = maxi(existing._remaining_ticks, ceili(duration_s))
		return
	var debuff := TimedDebuff.new()
	debuff.name = node_name
	debuff.kind = effect_kind
	debuff.armor_shred = armor
	debuff.move_slow = clampf(move, 0.0, 0.9)
	debuff.attack_slow = clampf(attack, 0.0, 0.9)
	debuff._remaining_ticks = ceili(duration_s)
	victim.add_child(debuff)


## Whole seconds left, for the status-icon countdown.
func remaining_seconds() -> int:
	return maxi(0, _remaining_ticks)


func _ready() -> void:
	_apply_to_victim()
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_tick)
	add_child(timer)
	timer.start()


func _apply_to_victim() -> void:
	var victim: Character = get_parent() as Character
	if victim == null:
		return
	if armor_shred > 0.0 and victim.stats_component != null:
		# Never shred past zero — a negative armour value would turn mitigation
		# into amplification further down the damage formula.
		var have: float = victim.stats_component.get_stat(Stat.ARMOR)
		_applied_armor = minf(armor_shred, maxf(0.0, have))
		if _applied_armor > 0.0:
			victim.stats_component.modify_stat(Stat.ARMOR, -_applied_armor)

	if move_slow > 0.0:
		var npc: HostileNpc = victim as HostileNpc
		if npc != null:
			# NPC move speed is a plain int field, not a stat.
			_applied_move = float(npc.move_speed) * move_slow
			npc.move_speed = maxi(1, npc.move_speed - int(round(_applied_move)))
		elif victim.stats_component != null:
			_applied_move = victim.stats_component.get_stat(Stat.MOVE_SPEED) * move_slow
			victim.stats_component.modify_stat(Stat.MOVE_SPEED, -_applied_move)

	if attack_slow > 0.0:
		var npc2: HostileNpc = victim as HostileNpc
		if npc2 != null:
			# Slowing attack SPEED means lengthening the cooldown: a 0.25 slow
			# is 1/(1-0.25) = 1.33x the wait, not 0.75x.
			var base: float = npc2.attack_cooldown
			_applied_attack = base / maxf(0.1, 1.0 - attack_slow) - base
			npc2.attack_cooldown = base + _applied_attack


func _revert() -> void:
	if _reverted:
		return
	_reverted = true
	var victim: Character = get_parent() as Character
	if victim == null:
		return
	if _applied_armor > 0.0 and victim.stats_component != null:
		victim.stats_component.modify_stat(Stat.ARMOR, _applied_armor)
	if _applied_move > 0.0:
		var npc: HostileNpc = victim as HostileNpc
		if npc != null:
			npc.move_speed += int(round(_applied_move))
		elif victim.stats_component != null:
			victim.stats_component.modify_stat(Stat.MOVE_SPEED, _applied_move)
	if _applied_attack > 0.0:
		var npc2: HostileNpc = victim as HostileNpc
		if npc2 != null:
			npc2.attack_cooldown = maxf(0.1, npc2.attack_cooldown - _applied_attack)


func _tick() -> void:
	var victim: Character = get_parent() as Character
	if victim == null or victim.is_dead or _remaining_ticks <= 0:
		_revert()
		queue_free()
		return
	_remaining_ticks -= 1
	if _remaining_ticks <= 0:
		_revert()
		queue_free()


## Covers the paths a timer never reaches: the victim dying, the instance being
## torn down, or the node being freed from under us. Reverting twice is a no-op.
func _exit_tree() -> void:
	_revert()
