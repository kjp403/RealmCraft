class_name BankInteraction
extends NPCInteraction
## NPC capability: open the personal bank vault. Capacity starts at
## [constant STARTING_SLOTS] and expands via [code]bank.upgrade[/code]
## ([constant UPGRADE_SLOTS] for [constant UPGRADE_COST] gold, no purchase cap).
## Drop a BankInteraction into any NPC's `interactions` array to make them a banker.

## Default vault size for new characters / migrated rows.
const STARTING_SLOTS: int = 50
## Slots added per [code]bank.upgrade[/code] purchase.
const UPGRADE_SLOTS: int = 50
## Gold fee per upgrade. Single source of truth for UI + server handler.
const UPGRADE_COST: int = 5000
## Cap on one [code]bank.upgrade[/code] purchase (count * UPGRADE_SLOTS slots).
const MAX_UPGRADE_COUNT: int = 99


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Bank"),
		"icon": _icon_or(""),
		"menu": &"bank",
		"arg": null,
	}
