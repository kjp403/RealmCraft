class_name QuickTravelDestination
extends Resource
## ONE row in the Wayfarer's quick-travel window: where it goes and what the
## base ride costs. Authored inline in the Wayfarer's NPCResource, the same way
## a shop authors its stock, so adding a sixth destination is a .tres edit and
## not a code change.
##
## The fee here is the BASE fare. What a player is actually charged is this
## scaled by their frequency surge (see [QuickTravelService]) and is computed
## SERVER-side only — this resource is shipped to clients as display data.

## Where the ride ends up.
@export var target_instance: InstanceResource
## Warper id to land on inside the target map (0 = that map's default spawn).
## Resolved through [method Map.get_spawn_position], which falls back to the home
## spawn if the id is missing — so a bad id lands the player somewhere valid
## rather than at (0, 0) inside a wall.
@export var target_id: int = 0
## Row title. Empty = the target instance's own zone title ("Guild Hall").
@export var label: String = ""
## Short "what/where is this" line under the title.
@export var blurb: String = ""
## Base fare in gold, before any surge.
@export var fee: int = 0


## Player-facing name for this stop.
func display_label() -> String:
	if not label.is_empty():
		return label
	return target_instance.display_title() if target_instance != null else "Unknown"
