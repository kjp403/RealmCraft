class_name HuntChestInteraction
extends NPCInteraction
## NPC capability: open the character's Hunt Chest — the persistent Guild Hall
## stash that Boss Hunt loot is banked into. Everything a hunt drops lands here,
## so this is where a party goes after their 30 minutes are up.
##
## A capability rather than a world prop so the hall keeper can hold it
## alongside their other services; the chest itself is per-character storage on
## PlayerResource, not a placed container.


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Hunt Chest"),
		"icon": _icon_or(""),
		"menu": &"hunt_chest",
		"arg": null,
	}
