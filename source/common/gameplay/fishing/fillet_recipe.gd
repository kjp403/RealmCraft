class_name FilletRecipe
extends Resource
## One tuning row of the [FilletTable]: how much Fish Bait one raw fish cuts into.
## Shape mirrors [SalvageRecipe] and [ShopEntry] — an item reference plus the one
## number a designer edits inline in the table's .tres, never a hand-typed slug
## that can resolve to id 0 and silently match nothing.

## The raw fish this row tunes. Drag a .tres from items/materials/fish/.
@export var source_item: Item

## Fish Bait produced per fish. Bigger fish cut into more — this is the whole knob
## that decides whether the deep-water ladder is worth filleting or selling.
@export var bait_yield: int = 1
