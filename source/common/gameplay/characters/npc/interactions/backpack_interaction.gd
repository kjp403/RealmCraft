class_name BackpackInteraction
extends NPCInteraction
## NPC capability: open the inventory so the player can buy an extra bag tab.
## The actual purchase is handled by inventory.upgrade_bag from the bag tabs.


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Buy backpack"),
		"icon": _icon_or(""),
		"open_menu": &"inventory",
		"arg": null,
	}
