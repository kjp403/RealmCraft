class_name WarpInteraction
extends NPCInteraction
## NPC capability: travel to a target instance (replaces Hub biome portals).
## Selecting the option fires [code]npc.warp[/code]; the server resolves this
## interaction off the NPC node, range-checks, then reuses warper travel
## ([method InstanceManager.player_switch_instance]).

@export var target_instance: InstanceResource
@export var target_id: int = 0
## Button / toast label, e.g. "Desert".
@export var destination_label: String = ""


func menu_entry(npc: Node) -> Dictionary:
	if target_instance == null:
		return {}
	var label: String = destination_label
	if label.is_empty():
		label = target_instance.display_title()
	return {
		"label": _label_or("Travel to %s" % label),
		"icon": _icon_or(""),
		"request": &"npc.warp",
		"args": {"npc": String(npc.name)},
	}
