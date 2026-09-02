extends Node
## Gate for how the Smithing Table and Ascended Workbench are split.
##
##   godot --path . --mode=client res://tools/verify_crafting_benches.tscn
##
## Two things here are DERIVED, never authored, so nothing complains when they
## go wrong:
##
##  * the tab a recipe lands in — computed from the output's type, path and name
##    by [CraftingCategory]. A recipe in the wrong tab is invisible until a
##    player goes looking for it.
##  * the profession a recipe gates on and pays — the station's, unless the
##    recipe overrides it. The Ascended Workbench is an `outfitting` bench that
##    hosts the metal ascension sets, which must stay Smithing. Get this wrong
##    and the recipes silently train the wrong skill.

const ANVIL := "res://source/common/gameplay/crafting/resources/anvil.tres"
const ASCENDED := "res://source/common/gameplay/crafting/resources/ascended_workbench.tres"

## Tabs each bench is allowed to surface. Anything else is a recipe that fell
## through the categoriser into a tab nobody designed.
const ALLOWED: Dictionary = {
	ANVIL: [
		&"bronze", &"iron", &"steel", &"mithril", &"adamant", &"runite", &"dragon",
		&"tools", &"jewelry", &"materials",
	],
	ASCENDED: [&"armor", &"weapons", &"cloth", &"leather", &"jewelry", &"materials"],
}
## Tabs that must actually be PRESENT — the point of the split.
const REQUIRED: Dictionary = {
	ANVIL: [&"adamant", &"runite", &"dragon"],
	ASCENDED: [&"armor", &"weapons"],
}

var _bad: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _fail(msg: String) -> void:
	_bad += 1
	print("  FAIL ", msg)
	push_error(msg)


func _go() -> void:
	var seen: Dictionary = {}
	for path: String in [ANVIL, ASCENDED]:
		_check_bench(path, seen)
	print("CRAFTING_BENCHES bad=", _bad)
	if _bad == 0:
		print("VERIFY_PASS crafting_benches")
	get_tree().quit(0)


func _check_bench(path: String, seen: Dictionary) -> void:
	var station: CraftingStationResource = load(path) as CraftingStationResource
	if station == null:
		_fail("could not load " + path)
		return

	var counts: Dictionary = {}
	var professions: Dictionary = {}
	for recipe: CraftingRecipe in station.recipes:
		if recipe == null:
			_fail("%s has a null recipe row" % path.get_file())
			continue
		if recipe.output_item == null:
			_fail("%s has a recipe with no output" % path.get_file())
			continue
		var slug: String = str(recipe.output_item.get_meta(&"slug", recipe.output_item.item_name))

		# An output authored on two benches is a duplicate the player can farm
		# at whichever one is cheaper.
		if seen.has(slug):
			_fail("%s is craftable on both %s and %s" % [slug, seen[slug], path.get_file()])
		seen[slug] = path.get_file()

		# Every ingredient must survive the move: a dropped ext_resource shows
		# up as a null item, and the craft then asks for nothing.
		for ing: CraftIngredient in recipe.required_inputs():
			if ing == null or ing.item == null:
				_fail("%s: %s has a null ingredient" % [path.get_file(), slug])

		var cat: StringName = CraftingCategory.of(recipe, station)
		counts[cat] = int(counts.get(cat, 0)) + 1
		if not (ALLOWED[path] as Array).has(cat):
			_fail("%s: %s lands in unexpected tab '%s'" % [path.get_file(), slug, cat])

		var prof: StringName = recipe.profession_for(station)
		professions[prof] = int(professions.get(prof, 0)) + 1
		_check_profession(path, slug, cat, prof)

	for cat: StringName in REQUIRED[path]:
		if not counts.has(cat):
			_fail("%s has no '%s' tab — the split did not take" % [path.get_file(), cat])

	print("ok %-24s %d recipes" % [path.get_file(), station.recipes.size()])
	for cat: StringName in ALLOWED[path]:
		if counts.has(cat):
			print("     %-10s %3d" % [CraftingCategory.label(cat), counts[cat]])
	for prof: StringName in professions:
		print("     -> %-12s %3d recipes" % [prof, professions[prof]])


## Metal and weapon work is Smithing wherever it is hosted; cloth, leather and
## their materials are the bench's own trade.
func _check_profession(path: String, slug: String, cat: StringName, prof: StringName) -> void:
	if path == ANVIL:
		if prof != &"smithing":
			_fail("anvil: %s gates on '%s', expected smithing" % [slug, prof])
		return
	if cat == &"armor" or cat == &"weapons":
		if prof != &"smithing":
			_fail("ascended: %s is %s work but gates on '%s', not smithing"
				% [slug, cat, prof])
	elif prof != &"outfitting":
		_fail("ascended: %s gates on '%s', expected outfitting" % [slug, prof])
