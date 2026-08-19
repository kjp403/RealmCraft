class_name BackpackInteraction
extends NPCInteraction
## NPC capability: open the inventory so the player can buy an extra bag tab.
## The actual purchase is handled by inventory.upgrade_bag from the bag tabs.


## The key MUST be "menu": npc_menu._on_entry dispatches on "lines" / "request" /
## "menu" only, and reads "open_menu" solely inside the "request" branch. An
## entry with neither "request" nor "menu" is silently inert.
func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Buy backpack"),
		"icon": _icon_or(""),
		"menu": &"inventory",
		"arg": null,
	}
