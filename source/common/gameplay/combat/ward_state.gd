class_name WardState
extends Node
## Server-side owner of a self-cast damage ward ([WardAbility] / Heavy Weapons'
## Spectral Ward): it holds [member Character.ward_damage_mult] down and
## [member Character.ward_reflect_ratio] up for its lifetime, and restores both
## on free.
##
## A node rather than a bare `create_timer` callback because the ward has to be
## RE-CASTABLE. Two overlapping timers would each "restore" 1.0, so the first one
## to fire would cancel a ward the player had just re-paid for. One node named
## [constant NODE_NAME] per character makes that impossible: a new cast frees the
## old node (which restores), then installs its own.
##
## Also not a [BuffService] entry: that service only carries STAT bonuses, and a
## damage-taken multiplier is not a stat (see [member Character.damage_taken_mult]).

const NODE_NAME: StringName = &"WardState"

var caster: Character
## Multiplier applied while this ward is up (0.7 = taking 30% less).
var damage_mult: float = 1.0
## Share of the absorbed damage thrown back at the attacker (0 = no reflect).
var reflect_ratio: float = 0.0
var duration_s: float = 6.0

var _elapsed: float = 0.0


## Installs a ward on [param character], replacing any ward already running.
## Returns the new state, or null off the server / on a dead body.
static func install(
	character: Character, damage_mult: float, reflect_ratio: float, duration_s: float
) -> WardState:
	if character == null or not character.is_inside_tree() or character.is_dead:
		return null
	if not character.multiplayer.is_server():
		return null
	var existing: WardState = character.get_node_or_null(NodePath(NODE_NAME)) as WardState
	if existing != null:
		# free() and not queue_free(): the replacement sets ward_damage_mult in
		# this same frame, and a deferred restore would land AFTER it and wipe
		# the new ward back to 1.0.
		existing.free()
	var state: WardState = WardState.new()
	state.name = NODE_NAME
	state.caster = character
	state.damage_mult = damage_mult
	state.reflect_ratio = reflect_ratio
	state.duration_s = duration_s
	character.add_child(state)
	return state


func _ready() -> void:
	if caster != null:
		caster.ward_damage_mult = damage_mult
		caster.ward_reflect_ratio = reflect_ratio


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration_s:
		queue_free()


func _exit_tree() -> void:
	# Restore on ANY exit — expiry, a replacement ward, or the caster despawning
	# mid-ward. Leaving the multiplier stuck low would make a player permanently
	# tankier than the game thinks they are, which is far worse than a lost ward.
	if caster != null and is_instance_valid(caster):
		caster.ward_damage_mult = 1.0
		caster.ward_reflect_ratio = 0.0
