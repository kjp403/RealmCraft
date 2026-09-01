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
