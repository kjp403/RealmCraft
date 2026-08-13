class_name CraftingStation
extends Interactable
## World-space click target that opens a crafting station (workbench, anvil, ...) —
## shown as the station's sprite. Just an Interactable preconfigured to open the
## crafting menu for its station; the click + walk-into-range approach are inherited.
## The server resolves the station from the player's map by this node's name, so no
## registry id is needed.
##
## Setup: an Area2D with this script, a CollisionShape2D over the station, and a
## CraftingStationResource assigned. Place as a direct child of the Map.
## Range uses [constant Interactable.INTERACT_RANGE] (do not redeclare — Godot 4.7
## treats duplicate const members as a parse error and the station script fails to load).

@export var station: CraftingStationResource


func _ready() -> void:
	if station != null:
		menu_name = &"crafting"
		# Set before Interactable._ready so the hover NameLabel can be built.
		hover_name = station.station_name
		# Self-register with the owning map, keyed by node name (what the client
		# sends and craft.item resolves). Registers the NODE so the server can
		# range-check against our world position at any nesting depth.
		var map: Map = Map.of(self)
		if map != null:
			map.register_keyed(map.crafting_stations, StringName(name), self, "crafting station")
	super._ready()


## Hand the crafting menu the station's catalog directly (rendered client-side) plus
## this node's name as the key the server resolves the station by.
func _build_menu_arg() -> Variant:
	return {"key": String(name), "station": station}
