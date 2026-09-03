class_name MixingRecipe
extends CraftingRecipe
## A COMBINATION recipe: an alchemy craft whose inputs include finished potions,
## and which therefore hands glassware back.
##
## Subclasses [CraftingRecipe] the same way [SmeltingRecipe] does, and for the
## same reason: the craft transaction — the pacing floor, the level gate, the
## atomic consume-and-rollback, the perk refund, the XP payout — is already
## correct in `craft.item.gd` and must not be forked. All this adds is a second
## OUTPUT list, which the handler grants alongside the main one.
##
## Byproducts are deliberately NOT part of [member CraftingRecipe.ingredients]
## or the refund roll: a refund is a chance to keep an input, while a byproduct
## is a guaranteed second product. Folding them together would let a Herblore
## perk quietly multiply the world's glass supply.


## Guaranteed extra items granted on a successful craft, on top of
## [member CraftingRecipe.output_item].
##
## Leave EMPTY on a potion-combining recipe: the empty vials are worked out from
## the recipe itself by [method PotionMixer.reclaimed_glass], so an author cannot
## forget them and cannot get the count wrong. Use this field only for a
## byproduct that is not glass.
@export var byproducts: Array[CraftIngredient] = []
## Set false on the rare recipe that should destroy its glassware (a draught
## whose vial is consumed by the reaction). Every combination draught we ship
## leaves it true — see the vial-economy note on [PotionMixer].
@export var reclaim_glass: bool = true
