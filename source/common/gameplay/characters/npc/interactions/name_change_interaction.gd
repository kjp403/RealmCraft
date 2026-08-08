class_name NameChangeInteraction
extends NPCInteraction
## Character renames are disabled. Kept as a class so old scene resources that
## still reference this script don't break; menu_entry is empty so the option
## never appears.

## Historical gold fee (unused — renames are off). Kept so any leftover dialog
## code that reads COST still resolves.
const COST: int = 20


func menu_entry(_npc: Node) -> Dictionary:
	return {}
