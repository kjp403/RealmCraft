@tool
extends SceneTree
## Gate on the setting half of the Crafting gem line: a cut stone set into
## Smithing-made jewellery at the Workbench.
##
## Every check here is a silent failure in game. A recipe on the wrong skill
## pays the wrong XP; a missing base piece makes a recipe uncraftable with no
## error; a guide row out of step mislabels every recipe after it; and a gem
## stat past its Slayer ceiling out-classes gear bought with points.
##
##   godot --headless --path . -s tools/verify_gem_jewelry.gd

const JEWELRY: String = "res://source/common/gameplay/items/gears/jewelry"
const RINGS: String = "res://source/common/gameplay/items/gears/rings"
const GEMS_DIR: String = "res://source/common/gameplay/items/materials/gems"
const ICONS: String = "res://assets/sprites/items/icons"

const METALS: Array[String] = ["silver", "gold"]
const PIECES: Array[String] = ["ring", "necklace", "amulet"]
## gem -> [cut level, set level, set xp]. Set xp approved by Kyle 2026-09-10.
const LADDER: Dictionary = {
	"sapphire": [1, 5, 40],
	"emerald": [27, 32, 70],
	"ruby": [43, 48, 110],
	"diamond": [60, 65, 180],
}
## Each gem adds ONE stat, colour-matched to the Slayer gem standing for it...
const GEM_STAT: Dictionary = {
	"ruby": "health_max", "emerald": "move_speed",
	"sapphire": "mana_max", "diamond": "armor",
}
## ...and the SILVER Slayer ring for that stat is the most a gem may add, so
## crafted jewellery never reaches the gold Slayer ring bought with points.
## Read live, so retuning a Slayer ring moves the ceiling with it.
const CEILING_RING: Dictionary = {
	"health_max": "ring_vital_silver", "move_speed": "ring_agile_silver",
	"mana_max": "ring_focus_silver", "armor": "ring_guard_silver",
}
## Base vendor values after halving (Kyle, 2026-09-10). A second halving by a
## careless re-run would still satisfy the piece formula below, so the bases
## are pinned outright.
const BASE_VENDOR: Dictionary = {
	"silver_ring": 75, "silver_necklace": 150, "silver_amulet": 225,
	"gold_ring": 150, "gold_necklace": 300, "gold_amulet": 450,
}

var bad: int = 0


func _fail(msg: String) -> void:
	printerr(msg)
	bad += 1


func _init() -> void:
	var bench: CraftingStationResource = load(
		"res://source/common/gameplay/crafting/resources/workbench.tres"
	) as CraftingStationResource
	var anvil: CraftingStationResource = load(
		"res://source/common/gameplay/crafting/resources/anvil.tres"
	) as CraftingStationResource
	if bench == null or anvil == null:
		_fail("could not load workbench / anvil")
		quit(1)
		return

	_check_bases()
	_check_gold_amulet(anvil)
	var sets: int = _check_setting(bench)
	_check_guides()

	print("setting recipes: %d   problems: %d" % [sets, bad])
	# run_verify.sh greps for this exact string and ignores the exit code,
	# because a gate that dies before its first check also exits 0.
	if bad == 0:
		print("VERIFY_PASS")
	quit(1 if bad else 0)


func _load_gear(dir: String, slug: String) -> GearItem:
	var gear: GearItem = load("%s/%s.tres" % [dir, slug]) as GearItem
	if gear == null:
		_fail("ITEM MISSING  " + slug)
		return null
	if int(gear.get_meta(&"id", 0)) <= 0:
		_fail("ITEM UNINDEXED " + slug + " - run update_items_index.gd")
	if gear.item_icon == null:
		_fail("ITEM NO ICON  " + slug)
	if gear.slot == null:
		_fail("ITEM NO SLOT  " + slug)
		return null
	if gear.base_modifiers.is_empty():
		_fail("ITEM NO STATS " + slug)
	return gear


## Summed per stat, read through the resource: health_max is elided from .tres
## text, so nothing here may look at the file.
func _stats(gear: GearItem) -> Dictionary:
	var out: Dictionary = {}
	for mod: StatModifier in gear.base_modifiers:
		if mod != null:
			var key: String = str(mod.stat_name)
			out[key] = float(out.get(key, 0.0)) + mod.value
	return out


func _find_recipe(station: CraftingStationResource, slug: String) -> Array[CraftingRecipe]:
	var out: Array[CraftingRecipe] = []
	for recipe: CraftingRecipe in station.recipes:
		if recipe != null and recipe.output_item != null \
				and str(recipe.output_item.get_meta(&"slug", &"")) == slug:
			out.append(recipe)
	return out


## Silver and gold bars repriced to 2x their ore (Kyle, 2026-09-10), so that
## jewellery -- not the bar -- is what a smith sells.
const BAR_VENDOR: Dictionary = {"silver_bar": 16, "gold_bar": 24}


func _check_bases() -> void:
	var anvil: CraftingStationResource = load(
		"res://source/common/gameplay/crafting/resources/anvil.tres"
	) as CraftingStationResource
	for bar_slug: String in BAR_VENDOR:
		var bar: Item = load(
			"res://source/common/gameplay/items/materials/metals/%s.tres" % bar_slug) as Item
		if bar == null:
			_fail("BAR MISSING " + bar_slug)
		elif bar.vendor_value != int(BAR_VENDOR[bar_slug]):
			_fail("BAR VENDOR %s is %d, want %d" % [bar_slug, bar.vendor_value,
				BAR_VENDOR[bar_slug]])
	for slug: String in BASE_VENDOR:
		var gear: GearItem = _load_gear(JEWELRY, slug)
		if gear == null:
			continue
		if gear.vendor_value != int(BASE_VENDOR[slug]):
			_fail("BASE VENDOR %s is %d, want %d" % [slug, gear.vendor_value,
				BASE_VENDOR[slug]])
		# The selling point: a piece must sell for more than the bars it was
		# smithed from, or a smith vendors the bars and skips the jewellery.
		for recipe: CraftingRecipe in _find_recipe(anvil, slug):
			var inputs: int = 0
			for ing: CraftIngredient in recipe.ingredients:
				if ing != null and ing.item != null:
					inputs += ing.item.vendor_value * ing.amount
			if gear.vendor_value <= inputs:
				_fail("BASE %s sells for %d, not above its bars (%d)" % [slug,
					gear.vendor_value, inputs])


## Silver had an amulet and gold did not, so four gem pieces had no base.
func _check_gold_amulet(anvil: CraftingStationResource) -> void:
	var gear: GearItem = _load_gear(JEWELRY, "gold_amulet")
	if gear != null and gear.slot.resource_path.get_file() != "amulet.tres":
		_fail("GOLD AMULET WRONG SLOT " + gear.slot.resource_path)
	var found: Array[CraftingRecipe] = _find_recipe(anvil, "gold_amulet")
	if found.size() != 1:
		_fail("GOLD AMULET RECIPES: expected 1 on the anvil, found %d" % found.size())
		return
	var recipe: CraftingRecipe = found[0]
	if recipe.profession_for(anvil) != &"smithing":
		_fail("GOLD AMULET PAYS " + str(recipe.profession_for(anvil)))
	if recipe.ingredients.size() != 1 or recipe.ingredients[0].item == null \
			or str(recipe.ingredients[0].item.get_meta(&"slug", &"")) != "gold_bar":
		_fail("GOLD AMULET INGREDIENTS are not gold bars")
	if CraftingCategory.of(recipe, anvil) != &"jewelry":
		_fail("GOLD AMULET TAB " + str(CraftingCategory.of(recipe, anvil)))


func _check_setting(bench: CraftingStationResource) -> int:
	var sets: int = 0
	for gem: String in LADDER:
		var cut_lvl: int = int(LADDER[gem][0])
		var set_lvl: int = int(LADDER[gem][1])
		var set_xp: int = int(LADDER[gem][2])
		var cut: Item = load("%s/%s.tres" % [GEMS_DIR, gem]) as Item
		if cut == null:
			_fail("CUT GEM MISSING " + gem)
			continue
		# The cut has to come first, or a player can unlock a setting recipe
		# for a stone they are not yet allowed to make.
		if set_lvl <= cut_lvl:
			_fail("SET %s AT %d IS NOT AFTER ITS CUT AT %d" % [gem, set_lvl, cut_lvl])

		for metal: String in METALS:
			for piece: String in PIECES:
				var slug: String = "%s_%s_%s" % [gem, metal, piece]
				var base_slug: String = "%s_%s" % [metal, piece]
				var gear: GearItem = _load_gear(JEWELRY, slug)
				var base: GearItem = _load_gear(JEWELRY, base_slug)
				if gear == null or base == null:
					continue
				if gear.item_icon.resource_path != "%s/jewelry_%s.png" % [ICONS, slug]:
					_fail("ICON MISMATCH " + slug + " " + gear.item_icon.resource_path)
				if gear.slot.resource_path != base.slot.resource_path:
					_fail("SLOT DIFFERS FROM BASE " + slug)
				_check_piece_balance(slug, gem, gear, base, cut)

				var found: Array[CraftingRecipe] = _find_recipe(bench, slug)
				if found.size() != 1:
					_fail("SET RECIPES %s: expected 1, found %d" % [slug, found.size()])
					continue
				var recipe: CraftingRecipe = found[0]
				sets += 1
				if recipe.profession_for(bench) != &"outfitting":
					_fail("SET PAYS WRONG SKILL " + slug)
				if recipe.required_level != set_lvl or recipe.xp_reward != set_xp:
					_fail("SET %s is L%d/%dxp, want L%d/%dxp" % [slug,
						recipe.required_level, recipe.xp_reward, set_lvl, set_xp])
				if CraftingCategory.of(recipe, bench) != &"jewelry":
					_fail("SET TAB %s -> %s" % [slug, CraftingCategory.of(recipe, bench)])
				var want: Dictionary = {base_slug: 1, gem: 1}
				var got: Dictionary = {}
				for ing: CraftIngredient in recipe.ingredients:
					if ing == null or ing.item == null:
						_fail("SET NULL INGREDIENT " + slug)
						continue
					got[str(ing.item.get_meta(&"slug", &""))] = ing.amount
				if got != want:
					_fail("SET %s INGREDIENTS %s, want %s" % [slug, got, want])
	if sets != 24:
		_fail("SET RECIPES: expected 24, found %d" % sets)
	return sets


## A gem piece keeps the base piece's stats exactly and adds one of its own,
## within the Slayer ceiling; and it sells for the OLD base price (twice the
## halved one) plus half the stone.
func _check_piece_balance(slug: String, gem: String, gear: GearItem,
		base: GearItem, cut: Item) -> void:
	var stat: String = GEM_STAT[gem]
	var mine: Dictionary = _stats(gear)
	var theirs: Dictionary = _stats(base)
	for key: String in theirs:
		if key != stat and not is_equal_approx(float(mine.get(key, 0.0)), float(theirs[key])):
			_fail("STAT DRIFT %s %s=%s, base has %s" % [slug, key,
				mine.get(key, 0.0), theirs[key]])
	for key: String in mine:
		if key != stat and not theirs.has(key):
			_fail("STAT EXTRA %s adds %s" % [slug, key])

	var bonus: float = float(mine.get(stat, 0.0)) - float(theirs.get(stat, 0.0))
	if bonus <= 0.0:
		_fail("GEM ADDS NOTHING %s (%s)" % [slug, stat])
	var ring: GearItem = load("%s/%s.tres" % [RINGS, CEILING_RING[stat]]) as GearItem
	if ring == null:
		_fail("CEILING RING MISSING " + str(CEILING_RING[stat]))
	elif bonus > float(_stats(ring).get(stat, 0.0)):
		_fail("GEM OVER CEILING %s +%s %s > %s %s" % [slug, bonus, stat,
			CEILING_RING[stat], _stats(ring).get(stat, 0.0)])

	var want_vendor: int = base.vendor_value * 2 + int(cut.vendor_value / 2.0)
	if gear.vendor_value != want_vendor:
		_fail("VENDOR %s is %d, want %d (old base %d + half of %d)" % [slug,
			gear.vendor_value, want_vendor, base.vendor_value * 2, cut.vendor_value])


## recipe_items / recipe_levels are read POSITIONALLY: a drift does not error,
## it labels every later recipe with the wrong level in the skill guide.
func _check_guides() -> void:
	var want: Dictionary = {"smithing": {"gold_amulet": 15}, "outfitting": {}}
	for gem: String in LADDER:
		want["outfitting"][gem] = int(LADDER[gem][0])
		for metal: String in METALS:
			for piece: String in PIECES:
				want["outfitting"]["%s_%s_%s" % [gem, metal, piece]] = int(LADDER[gem][1])

	for job_slug: String in want:
		var path: String = "res://source/common/gameplay/jobs/%s.tres" % job_slug
		var job: JobPerks = load(path) as JobPerks
		if job == null:
			_fail("could not load " + path)
			continue
		if job.recipe_items.size() != job.recipe_levels.size():
			_fail("%s: recipe_items %d != recipe_levels %d" % [job_slug,
				job.recipe_items.size(), job.recipe_levels.size()])
			continue
		var rows: Dictionary = {}
		for i: int in job.recipe_items.size():
			var item: Item = job.recipe_items[i]
			if item != null:
				rows[str(item.get_meta(&"slug", &""))] = job.recipe_levels[i]
		for slug: String in want[job_slug]:
			if not rows.has(slug):
				_fail("%s guide is missing %s" % [job_slug, slug])
			elif int(rows[slug]) != int(want[job_slug][slug]):
				_fail("%s guide lists %s at %d, want %d" % [job_slug, slug,
					rows[slug], want[job_slug][slug]])
