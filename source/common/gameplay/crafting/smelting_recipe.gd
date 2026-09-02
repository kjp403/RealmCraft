class_name SmeltingRecipe
extends CraftingRecipe
## A furnace recipe for the post-Runite metals, which do not smelt on the
## standard [code]N x Coal + 1 x Ore = 1 x Bar[/code] formula.
##
## Bronze through Runite are a coal ladder: the only thing that changes between
## tiers is how much coal the fire needs. That reads as "more of the same" at
## exactly the point in the game where a new metal should feel like an event.
## From Dragon up, each bar is an ALLOY with its own chemistry:
##
##   Dragon    2 Dragon Ore    + 1 Dragon Scale   + 1 Runite Bar
##   Obsidian  2 Obsidian Ore  + 1 Obsidian Flux  + 1 Dragon Bar
##   Celestial 2 Celestial Ore + 1 Celestial Dust + 1 Obsidian Bar
##   Astralite 2 Astralite Ore + 1 Astralite Mote + 1 Celestial Bar
##
## ...each over an Everburning Crucible, which is held rather than spent.
##
## Two things are new, and both live here rather than in [CraftingRecipe] so
## that no existing station changes behaviour:
##
## [b]Catalysts[/b] ([member catalysts]) are required to be in the bag but are
## usually NOT consumed. A catalyst is a piece of equipment the smith owns, not
## a reagent they burn — it gates the recipe permanently after one purchase and
## then erodes slowly via [member catalyst_consume_chance]. That is a gold sink
## with a soft edge: a player is never one missing consumable away from being
## unable to smelt, but the crucible is not free forever either.
##
## [b]Tier alloying[/b] is just an ordinary entry in [member ingredients] — the
## previous tier's BAR. No new mechanism is needed for it, but it is the reason
## the coal formula had to go: a Dragon bar that costs a Runite bar cannot also
## be described as "ore plus fuel".
##
## Authored inside `furnace.tres` exactly like a [CraftingRecipe]; the station
## holds a mixed list and the server branches on the type.

## Inputs the player must HOLD but which are usually not spent. Rolled
## individually against [member catalyst_consume_chance] AFTER the ordinary
## ingredients are consumed and the craft is known to be going ahead.
##
## Perk / outfit refunds deliberately do not apply: those are tuned as a
## discount on what a craft COSTS, and a catalyst's cost is already the chance
## roll below. Stacking both would make an erosion rate that reads as 8% behave
## like 5%, invisibly.
@export var catalysts: Array[CraftIngredient]

## Per-unit chance each held catalyst is destroyed by a completed smelt.
## 0.0 = a permanent tool that only ever gates the recipe; 1.0 = an ordinary
## consumed ingredient that would be better authored in [member ingredients].
## The shipping crucible sits low — it should outlive a bar run, not a session.
@export_range(0.0, 1.0, 0.01) var catalyst_consume_chance: float = 0.0

## One line shown above the material list, naming the process rather than the
## output ("Quenched in dragon scale."). Empty = the UI shows nothing extra.
@export var flavor: String = ""


## Ingredients AND catalysts — both must be in the bag for the smelt to start.
## See [method CraftingRecipe.required_inputs].
func required_inputs() -> Array[CraftIngredient]:
	var out: Array[CraftIngredient] = ingredients.duplicate()
	out.append_array(catalysts)
	return out


## True when [param item_id] is a catalyst of this recipe, so the UI can label
## the row as held-not-spent instead of lying that it will be consumed.
func is_catalyst(item_id: int) -> bool:
	for catalyst: CraftIngredient in catalysts:
		if catalyst != null and catalyst.item != null \
				and int(catalyst.item.get_meta(&"id", 0)) == item_id:
			return true
	return false
