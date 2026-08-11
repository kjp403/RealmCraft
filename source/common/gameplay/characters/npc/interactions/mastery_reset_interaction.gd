class_name MasteryResetInteraction
extends NPCInteraction
## NPC capability: refund all spent weapon-mastery points across every tree for
## a gold fee so the player can rebuild subclasses. Opens a confirm dialog; the
## reset itself is the server-authoritative mastery.respec handler, which reads
## COST here so the displayed price and the charged price can't drift.

## Gold fee for a mastery respec. Single source of truth — the server handler
## reads it too.
const COST: int = 25000


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Respec mastery"),
		"icon": _icon_or(""),
		"menu": &"mastery_reset",
		"arg": COST,
	}
