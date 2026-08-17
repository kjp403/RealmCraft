class_name BossHuntInteraction
extends NPCInteraction
## NPC capability: opens the Boss Hunt contract board. The NPC IS the station —
## the server resolves it by NODE NAME (no manual id) and range-checks against
## the NPC's position, exactly like DungeonInteraction. Drop one into a broker
## NPC's interactions array to let players buy hunts from them.
##
## The roster itself is global data (BossHuntCatalog scans boss_hunt/targets/),
## so there is nothing to configure here beyond the button label.


func menu_entry(npc: Node) -> Dictionary:
	return {
		"label": _label_or("Boss contracts"),
		"icon": _icon_or(""),
		"menu": &"boss_hunt",
		"arg": String(npc.name), # the station id is the node name (auto, no manual id)
	}
