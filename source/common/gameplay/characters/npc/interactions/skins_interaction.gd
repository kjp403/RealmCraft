class_name SkinsInteraction
extends NPCInteraction
## NPC capability: open the Vault on the Skins tab (prestige recolors). Server
## still gates vault_skins.state / vault_skins.equip to admin+.


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Skins"),
		"icon": _icon_or(""),
		"menu": &"vault",
		"arg": "skins",
	}
