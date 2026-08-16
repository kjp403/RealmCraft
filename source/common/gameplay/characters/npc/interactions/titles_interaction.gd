class_name TitlesInteraction
extends NPCInteraction
## NPC capability: open the staff Titles shelf in the VFX Vault. Premium title
## VFX only — does not touch the Cosmetics wardrobe. Server still gates
## titles.state / titles.equip to admin+.


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Titles"),
		"icon": _icon_or(""),
		"menu": &"vault",
		"arg": "titles",
	}
