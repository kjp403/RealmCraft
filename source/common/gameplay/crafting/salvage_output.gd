class_name SalvageOutput
extends Resource
## One item a [SalvageRecipe] yields, as a RANGE. A fixed yield is just
## min == max, so "1 Blightspore" and "1-3 Iron Bars" are the same shape and the
## UI has one thing to render.
##
## Not [CraftIngredient]: that is a fixed {item, amount} and crafting INPUTS must
## stay fixed — a recipe whose cost rolled would be unusable. Only the output
## side gets to be random.

@export var item: Item
@export_range(0, 999, 1) var min_amount: int = 1
@export_range(0, 999, 1) var max_amount: int = 1


## True when this output rolls rather than paying a fixed amount.
func is_random() -> bool:
	return max_amount > min_amount


## Roll the yield for ONE unit broken down. Server-side only — the client shows
## the range and learns the actual roll from the response, so a hand-rolled
## client cannot pick its own number.
func roll() -> int:
	if not is_random():
		return maxi(0, min_amount)
	return randi_range(maxi(0, min_amount), max_amount)


## "1-3x Iron Bar" / "2x Bone". Used by the Break Down confirm prompt, which has
## to describe a yield that has not been rolled yet.
func describe() -> String:
	if item == null:
		return ""
	if is_random():
		return "%d-%dx %s" % [min_amount, max_amount, item.item_name]
	return "%dx %s" % [min_amount, item.item_name]
