extends Node
## Gate for the Outfitting XP rule: a workbench recipe's xp_reward is the tier's
## per-unit rate times the ingredient units it consumes — the same shape the
## anvil prices armour in bars.
##
## Before this rule the workbench was authored by eye and drifted badly: a
## Studded Cap paid 180 xp per leather where an Apprentice Robe of the same
## mastery tier paid 43, and the level 45/50 tiers paid one flat number no
## matter how much cloth went in, so the cheapest piece was always the best xp
## per material. This check is what stops that coming back.
##
## Runs as a SCENE, not `-s`: a headless script run has no autoloads, so item
## scripts that reach ClientState fail to compile and every output loads null.
## See verify_herblore.gd for the same note.
##
##   godot --headless --path . --mode=client res://tools/verify_outfitting_xp.tscn

const STATION_PATH: String = "res://source/common/gameplay/crafting/resources/workbench.tres"

## Recipe level -> xp per unit of material. Each rate is the material-weighted
## average of what that band already paid, so the tier's total throughput is
## unchanged and only the distribution inside it moved. Documented in
## CONTENT_AUTHORING.md under "Crafting XP is priced per unit of material".
const RATE_BY_LEVEL: Dictionary = {
	1: 36,    # Forest cloth / leather
	5: 54,    # Cave cloth / leather, including Studded
	10: 72,   # Bandit cloth / leather
	15: 180,  # Enchanted / Phantom
	30: 200,  # Ancient / Sirenic
	45: 240,  # Wraithsilk / Runewoven
	50: 290,  # Nightglass / Astral
}

## Tanning and weaving (hide -> leather, fibre -> cloth) are the "smelting" step:
## one output, one flat per-craft rate, already proportionate among themselves.
## They are deliberately NOT rebased, so they are skipped here — an output that
## lives under items/materials/ is one of them.
const MATERIAL_MARKER: String = "/items/materials/"

var _fails: Array[String] = []


func _ready() -> void:
	var station: CraftingStationResource = load(STATION_PATH) as CraftingStationResource
	if station == null:
		_fails.append("workbench.tres failed to load as a CraftingStationResource")
		_finish()
		return
	if station.profession != &"outfitting":
		_fails.append("workbench profession is %s, expected outfitting" % station.profession)

	var checked: int = 0
	for recipe: CraftingRecipe in station.recipes:
		if recipe == null or recipe.output_item == null:
			_fails.append("a workbench recipe has no output item")
			continue
		var out_path: String = recipe.output_item.resource_path
		if out_path.contains(MATERIAL_MARKER):
			continue
		if not RATE_BY_LEVEL.has(recipe.required_level):
			_fails.append("%s sits at level %d, which has no authored xp rate" % [
				recipe.output_item.item_name, recipe.required_level
			])
			continue
		var units: int = 0
		for ingredient: CraftIngredient in recipe.ingredients:
			if ingredient == null or ingredient.item == null:
				_fails.append("%s has a broken ingredient" % recipe.output_item.item_name)
				continue
			units += ingredient.amount
		if units <= 0:
			_fails.append("%s consumes nothing" % recipe.output_item.item_name)
			continue
		var want: int = units * int(RATE_BY_LEVEL[recipe.required_level])
		checked += 1
		if recipe.xp_reward != want:
			_fails.append("%s pays %d xp for %d units at level %d, want %d" % [
				recipe.output_item.item_name, recipe.xp_reward, units,
				recipe.required_level, want
			])
			continue
		print("  ok  lv%-3d %-22s %2d units  %5d xp" % [
			recipe.required_level, recipe.output_item.item_name, units, recipe.xp_reward
		])

	if checked == 0:
		_fails.append("no armour recipes were checked — the station shape changed")
	else:
		print("armour recipes checked: ", checked)
	_finish()


func _finish() -> void:
	if _fails.is_empty():
		print("VERIFY_PASS outfitting_xp")
		get_tree().quit(0)
		return
	for f: String in _fails:
		print("VERIFY_FAIL ", f)
	get_tree().quit(1)
