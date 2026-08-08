class_name BattleFormState
extends Node
## Server-side Battle Form runtime: raises the caster's MAX + CURRENT health by
## [member bonus_hp] and scales their HURTBOX for [member duration], then reverts.
## Also exposes [member reach_mult] so melee/bolt abilities can keep pace with the
## larger body (fixed-range hitboxes otherwise feel tiny in titan form).
##
## Manual (not BuffService) because we grant CURRENT hp + must clamp it on revert.

var caster: Character
var bonus_hp: float = 180.0
var scale_factor: float = 1.35
## Multiplier applied to melee/bolt reach while this form is live.
var reach_mult: float = 1.75
var duration: float = 8.0
var _active: bool = true


func _ready() -> void:
	name = &"BattleFormState"
	if not is_instance_valid(caster) or caster.stats_component == null:
		queue_free()
		return
	caster.stats_component.modify_stat(Stat.HEALTH_MAX, bonus_hp)
	caster.stats_component.modify_stat(Stat.HEALTH, bonus_hp)
	# Scale the whole root so the HURTBOX grows with the body (the bigger-target tradeoff).
	# Server has no camera child, so scaling the root here is safe; the client compensates
	# its own camera (InstanceClient._on_battleform). Scale isn't synced, so no double-scale.
	caster.scale *= scale_factor
	await get_tree().create_timer(duration).timeout
	_revert()


## Early end (weapon unequip / swap). Safe to call more than once.
func cancel() -> void:
	_revert()


static func cancel_on(character: Character) -> void:
	if character == null:
		return
	var state: BattleFormState = character.get_node_or_null(^"BattleFormState") as BattleFormState
	if state != null:
		state.cancel()


static func reach_multiplier(character: Character) -> float:
	if character == null:
		return 1.0
	var state: BattleFormState = character.get_node_or_null(^"BattleFormState") as BattleFormState
	return state.reach_mult if state != null else 1.0


func _revert() -> void:
	if not _active:
		return
	_active = false
	if is_instance_valid(caster) and caster.stats_component != null:
		caster.stats_component.modify_stat(Stat.HEALTH_MAX, -bonus_hp)
		var new_max: float = caster.stats_component.get_stat(Stat.HEALTH_MAX)
		var cur: float = caster.stats_component.get_stat(Stat.HEALTH)
		if cur > new_max:
			caster.stats_component.set_stat(Stat.HEALTH, new_max)  # lose the temp buffer
		caster.scale /= scale_factor
		_push_end()
	queue_free()


func _push_end() -> void:
	if not GameMode.is_world_server() or WorldServer.curr == null:
		return
	if caster is not Player or (caster as Player).player_resource == null:
		return
	var map: Node = caster.get_parent()
	if map == null or map.get_parent() == null:
		return
	WorldServer.curr.propagate_rpc(
		WorldServer.curr.data_push.bind(&"battleform.end", {
			"p": int((caster as Player).player_resource.current_peer_id),
		}),
		map.get_parent().name
	)
