class_name CraftingRecipe
extends Resource
## One craftable output and its inputs. Authored inside a CraftingStationResource's
## recipe list (not a registry content type itself — the station carries it).

@export var output_item: Item
@export var output_amount: int = 1
@export var ingredients: Array[CraftIngredient]
## Crafting-profession level required to craft this (0 = no requirement).
@export var required_level: int = 0
@export var xp_reward: int = 10
## Profession this recipe gates on and pays XP to, when it is NOT the station's
## own [member CraftingStationResource.profession]. Empty (the default) means
## "use the station's", which is every recipe except where a bench deliberately
## hosts more than one trade.
##
## The Ascended Workbench is that case: it is an `outfitting` bench holding the
## cloth and leather ascension sets, and it also hosts the METAL ascension sets
## and weapons, which are Smithing work and must stay Smithing work. Without
## this, moving a recipe between benches silently re-gates it onto a different
## skill and pays that skill's XP.
##
## Read it through [method profession_for] rather than directly — the fallback
## is the whole point, and a caller that forgets it re-introduces the bug.
@export var profession_override: StringName = &""
## Reserved for a future "learned recipes" system. v1 treats every recipe as known,
## so this is currently ignored — kept so recipes can become unlockable later.
@export var learnable: bool = false


## Every input the player must HOLD for this craft to be allowed: the plain
## [member ingredients], plus any inputs a subclass gates on without always
## consuming (see [SmeltingRecipe] catalysts).
##
## Availability checks and the crafting UI read THIS, not [member ingredients],
## so a subclass that adds a new kind of input is shown and gated correctly
## without touching every call site. Only the consumption path distinguishes
## the two, because only it needs to.
func required_inputs() -> Array[CraftIngredient]:
	return ingredients


## The profession that gates this recipe and receives its XP: the recipe's own
## [member profession_override] when set, otherwise the station's.
##
## Every level check, perk lookup, XP award and daily-task credit for a single
## craft must agree on ONE answer, so they all come through here rather than
## reading [member CraftingStationResource.profession] directly.
func profession_for(station: CraftingStationResource) -> StringName:
	if not profession_override.is_empty():
		return profession_override
	return station.profession if station != null else &""
