class_name PotionMixer
## The RULES of combination brewing: what a mix requires, what it consumes, and
## what glassware it gives back.
##
## Static-only, like [BuffService], [CoatingService] and [StatusService] — there
## is no per-instance state to hold, so it needs no autoload entry and is
## globally reachable through its class_name alone. (Registering a stateless
## static class as an autoload would add a node to every scene tree for nothing,
## which is why none of its sibling services are autoloads either.)
##
## WHAT THIS IS NOT
##
## It is not a second crafting path. `craft.item.gd` remains the ONE server
## handler that mutates a bag: it owns the walk-up range check, the anti-spam
## pacing floor, the atomic consume-with-rollback, the perk refund roll, the
## bag-full guard and the XP payout. A mixer that consumed items itself would
## have to re-earn every one of those, and the first one it got wrong would be a
## duplication exploit rather than a bug.
##
## So this module answers questions and the handler acts on the answers:
##   [method verify]          — may this player mix this recipe right now?
##   [method reclaimed_glass] — how many empty vials does this mix hand back?
##   [method byproducts_for]  — every extra item to grant, glass included.
##
## THE VIAL ECONOMY
##
## Every potion in the game arrives in a vial. A combination draught consumes two
## finished potions (two vials) and produces one (one vial), so one vial is left
## over — and it has to go somewhere, or brewing would quietly destroy glass and
## the Vial of Water price would drift upward forever as the only sink.
##
## The count is DERIVED, never authored: an item carries the [constant VIAL_TAG]
## in its [member Item.tags], the mixer counts tagged inputs and subtracts tagged
## outputs, and the difference is returned as Empty Vials. An author adding a
## seventh combination draught gets the accounting for free and cannot get it
## wrong by hand.

## Items carrying this tag occupy one glass vial per unit. Set on every potion,
## on the Vial of Water, and on nothing else. Uses [member Item.tags], which the
## base class already documents as being for exactly this — free-form tags for
## filters and crafting — so no schema change was needed.
const VIAL_TAG: String = "vial"

## Slug of the item handed back when a mix frees a vial. Resolved through the
## content registry rather than preloaded: a preload here would form an
## Item <-> crafting dependency cycle of the kind [Item] already warns about.
const EMPTY_VIAL_SLUG: StringName = &"empty_vial"

## How many vials [param item] occupies per unit. 0 for a herb, a bone, an ore.
static func vial_count(item: Item) -> int:
	if item == null:
		return 0
	return 1 if item.tags.has(VIAL_TAG) else 0


## Net vials freed by one craft of [param recipe]: tagged inputs minus tagged
## outputs, floored at zero.
##
## Floored because a recipe may legitimately consume MORE glass than it returns
## (a Vial of Water plus a herb makes one potion: one vial in, one vial out, zero
## freed). It can never be negative, and a recipe that somehow produced glass out
## of nothing would be an authoring error, not a windfall.
static func reclaimed_glass(recipe: CraftingRecipe) -> int:
	if recipe == null:
		return 0
	var mixing: MixingRecipe = recipe as MixingRecipe
	if mixing != null and not mixing.reclaim_glass:
		return 0
	var vials_in: int = 0
	for ingredient: CraftIngredient in recipe.ingredients:
		if ingredient == null:
			continue
		vials_in += vial_count(ingredient.item) * ingredient.amount
	var vials_out: int = vial_count(recipe.output_item) * recipe.output_amount
	return maxi(0, vials_in - vials_out)


## Every extra item one craft of [param recipe] grants beyond its output, as
## {item_id: amount}. Ids rather than [Item]s because the caller is an inventory
## handler that works in ids, and resolving here keeps the registry lookup in one
## place.
##
## Returns an EMPTY dictionary for an ordinary recipe, so `craft.item.gd` can
## call this unconditionally instead of type-testing the recipe.
static func byproducts_for(recipe: CraftingRecipe) -> Dictionary[int, int]:
	var out: Dictionary[int, int] = {}
	if recipe == null:
		return out
	var mixing: MixingRecipe = recipe as MixingRecipe
	if mixing != null:
		for byproduct: CraftIngredient in mixing.byproducts:
			if byproduct == null or byproduct.item == null or byproduct.amount <= 0:
				continue
			var id: int = int(byproduct.item.get_meta(&"id", 0))
			if id > 0:
				out[id] = out.get(id, 0) + byproduct.amount
	var glass: int = reclaimed_glass(recipe)
	if glass > 0:
		var vial_id: int = empty_vial_id()
		# A missing Empty Vial item must not silently swallow the reclaim — but it
		# must not block the craft either, or one bad content edit would take the
		# whole alchemy table offline. Loud in the log, harmless in the bag.
		if vial_id > 0:
			out[vial_id] = out.get(vial_id, 0) + glass
		else:
			push_warning(
				"PotionMixer: '%s' not in the items registry — %d vial(s) not returned."
				% [EMPTY_VIAL_SLUG, glass]
			)
	return out


## Registry id of the Empty Vial, or 0 if it is not indexed.
##
## Only a SUCCESSFUL lookup is cached. Caching a miss would be permanent for the
## life of the process, so one server that happened to ask before the registry
## was warm would return empty vials to nobody for the rest of the day — and the
## warning it logs would fire once and never again to say so.
static var _empty_vial_id: int = 0


static func empty_vial_id() -> int:
	if _empty_vial_id > 0:
		return _empty_vial_id
	var item: Item = ContentRegistryHub.load_by_slug(&"items", EMPTY_VIAL_SLUG) as Item
	if item != null:
		_empty_vial_id = int(item.get_meta(&"id", 0))
	return _empty_vial_id


## May [param player] craft [param recipe] at [param station] right now?
##
## Returns the same {"ok": bool, "reason": String, ...} shape `craft.item.gd`
## already answers the client in, so the handler can forward a refusal
## unchanged and the crafting UI needs no new cases.
##
## Checks only the rules that are the MIXER's business — the profession level and
## the availability of every input. Walk-up range, craft pacing and the bag-full
## guard stay with the handler, which is the only thing that knows about peers,
## timing and slots.
static func verify(
	recipe: CraftingRecipe, station: CraftingStationResource, resource: PlayerResource
) -> Dictionary:
	if recipe == null or recipe.output_item == null or resource == null:
		return {"ok": false, "reason": "recipe"}

	var profession: StringName = recipe.profession_for(station)
	var skill: Dictionary = resource.skills.get(profession, {})
	var level: int = int(skill.get("level", 1))
	if level < recipe.required_level:
		return {
			"ok": false,
			"reason": "level",
			"required_level": recipe.required_level,
			"profession": String(profession),
		}

	# Every input must be HELD before any is taken — the atomic-craft rule. This
	# reads `required_inputs()` rather than `ingredients` so a subclass that gates
	# on something it does not always consume (a [SmeltingRecipe] catalyst) is
	# covered here too, without this function knowing what a catalyst is.
	for ingredient: CraftIngredient in recipe.required_inputs():
		if ingredient == null or ingredient.item == null:
			continue
		var id: int = int(ingredient.item.get_meta(&"id", 0))
		if Inventory.count(resource.inventory, id) < ingredient.amount:
			return {
				"ok": false,
				"reason": "ingredients",
				"missing": String(ingredient.item.item_name),
			}

	return {"ok": true, "reason": "", "glass": reclaimed_glass(recipe)}


