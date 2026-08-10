class_name CraftingStation
extends Interactable
## World-space click target that opens a crafting station (workbench, anvil, ...) —
## shown as the station's sprite. Just an Interactable preconfigured to open the
## crafting menu for its station; the click is inherited. The server resolves the
## station from the player's map by this node's name, so no registry id is needed.
##
## Setup: an Area2D with this script, a CollisionShape2D over the station, and a
## CraftingStationResource assigned. Place as a direct child of the Map.

## Match [constant NPC.INTERACT_RANGE] — walk up to craft; no remote clicks.
const INTERACT_RANGE: float = 90.0

@export var station: CraftingStationResource


func _ready() -> void:
	if station != null:
		menu_name = &"crafting"
		# Set before Interactable._ready so the hover NameLabel can be built.
		hover_name = station.station_name
		# Self-register with the owning map, keyed by node name (what the client
		# sends and craft.item resolves).
		var map: Map = Map.of(self)
		if map != null:
			map.register_keyed(map.crafting_stations, StringName(name), station, "crafting station")
	super._ready()


## Hand the crafting menu the station's catalog directly (rendered client-side) plus
## this node's name as the key the server resolves the station by.
func _build_menu_arg() -> Variant:
	return {"key": String(name), "station": station}


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	var clicked: bool = (
		(event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if not clicked or menu_name == &"":
		return
	if not _player_in_range():
		var who: String = hover_name if not hover_name.is_empty() else "the station"
		Toaster.toast("Too far from %s." % who)
		return
	ClientState.open_menu_requested.emit(menu_name, _build_menu_arg())


func _player_in_range() -> bool:
	var lp: LocalPlayer = ClientState.local_player
	if lp == null or not is_instance_valid(lp):
		return false
	return global_position.distance_to(lp.global_position) <= INTERACT_RANGE
