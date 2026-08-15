class_name SkillPerkResetInteraction
extends NPCInteraction
## NPC capability: refund all spent skill perk points across every job for a
## gold fee so the player can re-pick Apprentice / Frugal / etc. Opens a confirm
## dialog; the reset itself is the server-authoritative skill.perk.reset
## handler, which reads COST here so the displayed price and the charged price
## can't drift.

## Gold fee for a perk respec. Single source of truth — the server handler
## reads it too.
const COST: int = 25000


func menu_entry(_npc: Node) -> Dictionary:
	return {
		"label": _label_or("Respec skill points"),
		"icon": _icon_or(""),
		"menu": &"skill_perk_reset",
		"arg": COST,
	}
