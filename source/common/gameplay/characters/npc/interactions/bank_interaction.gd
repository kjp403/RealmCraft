class_name BankInteraction
extends NPCInteraction
## NPC capability: open the personal bank vault. Storage is unlimited and
## persisted on the player (`bank_json`). Drop a BankInteraction into any NPC's
## `interactions` array to make them a banker.


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Bank"),
		"icon": _icon_or(""),
		"menu": &"bank",
		"arg": null,
	}
