class_name SalvageRecipe
extends Resource
## One "break this down" conversion: a source item and what a single unit of it
## yields. The mirror image of [CraftingRecipe] — authored inside the
## [SalvageTable] rather than being a registry content type of its own.
##
## Outputs are [SalvageOutput], not [CraftIngredient], because a yield may be a
## RANGE (rustic weapons pay 1-3 iron bars). Crafting inputs must stay fixed, so
## the two deliberately do not share a class.

@export var source_item: Item
@export var outputs: Array[SalvageOutput]
## Profession level required to break this down (0 = no requirement).
@export var required_level: int = 0
## Profession xp per unit broken down. Deliberately a fraction of what BREWING
## with the yield pays — salvage is a material tap, not an xp route.
@export var xp_reward: int = 0
