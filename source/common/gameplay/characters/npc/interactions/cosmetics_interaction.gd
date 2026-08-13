class_name CosmeticsInteraction
extends NPCInteraction
## NPC capability: open the cosmetics wardrobe — browse and equip VFX cosmetics
## (auras, trails, halos, flourishes, death effects).
##
## Routing only. Everything that matters is server-side: cosmetics.state returns an
## empty roster to non-staff and cosmetics.equip refuses them outright, so putting this
## interaction on an NPC never grants access by itself. Currently only the Curator in
## the admin-only VFX Vault carries it.


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Cosmetics"),
		"icon": _icon_or(""),
		"menu": &"cosmetics",
		"arg": null,
	}
