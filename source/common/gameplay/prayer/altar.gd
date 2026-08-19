class_name Altar
extends Interactable
## The church altar: burn bones for Prayer xp, and top your prayer points back
## up. A plain [Interactable] preconfigured to open the altar menu, so the click
## and the walk-into-range approach are inherited.
##
## Setup: an Area2D with this script and a CollisionShape2D over the altar art,
## placed anywhere under the Map node.
##
## Unlike [CraftingStation] there is no per-altar resource and no key: every
## altar in the game does the same thing, so the server only ever needs the
## answer to "is this player standing at one" — see [method player_in_range].

## Group every altar joins, so the range check can find them without the Map
## needing its own registry dictionary for a node with no per-instance state.
const GROUP: StringName = &"altars"


func _ready() -> void:
	menu_name = &"altar"
	hover_name = "Altar"
	add_to_group(GROUP)
	super._ready()


## True when [param player] is standing close enough to any altar in THEIR
## instance to use it. Server-side gate for altar.offer / altar.recharge, and
## the reason neither handler needs a station key: the player's own scene tree
## scopes the search to their instance, so one altar can never be used from
## another map.
static func player_in_range(player: Player) -> bool:
	if player == null or not player.is_inside_tree():
		return false
	for node: Node in player.get_tree().get_nodes_in_group(GROUP):
		var altar: Altar = node as Altar
		if altar == null or not altar.is_inside_tree():
			continue
		# Same instance only. Altars in other loaded maps share the group, so
		# comparing the owning Map is what keeps this honest.
		if Map.of(altar) != Map.of(player):
			continue
		if player.global_position.distance_to(altar.global_position) <= INTERACT_RANGE:
			return true
	return false
