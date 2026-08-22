class_name BankInteraction
extends NPCInteraction
## NPC capability: open the personal bank vault. Capacity starts at
## [constant STARTING_SLOTS] and expands via [code]bank.upgrade[/code]
## ([constant UPGRADE_SLOTS] for [constant UPGRADE_COST] gold, up to
## [constant MAX_BANK_SLOTS] total).
## Drop a BankInteraction into any NPC's `interactions` array to make them a banker.

## Default vault size for new characters / migrated rows.
const STARTING_SLOTS: int = 50
## Slots added per [code]bank.upgrade[/code] purchase.
const UPGRADE_SLOTS: int = 50
## Gold fee per upgrade. Single source of truth for UI + server handler.
const UPGRADE_COST: int = 5000
## Cap on one [code]bank.upgrade[/code] purchase (count * UPGRADE_SLOTS slots).
const MAX_UPGRADE_COUNT: int = 99
## Lifetime cap on total vault size. An unbounded vault can grow past the
## WebSocket message buffer and make bank.get silently fail to deliver — see
## the buffer-size fix in base_multiplayer_endpoint.gd. Multiple of
## UPGRADE_SLOTS so capacity always lands on it exactly.
const MAX_BANK_SLOTS: int = 500


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Bank"),
		"icon": _icon_or(""),
		"menu": &"bank",
		"arg": null,
	}
