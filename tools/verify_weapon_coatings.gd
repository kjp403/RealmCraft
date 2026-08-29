extends Node
## Load-and-shape check for the whole weapon-coating loop: salvage table ->
## materials -> the four brews -> the coating potions.
##
## Runs as a SCENE, not `-s`: under `-s` there are no autoloads, so
## ConsumableItem (which reaches ClientState) fails to compile and every potion
## in the station and the job list loads as null — the check then reports
## cascading false failures. See verify_bank.gd for the same note.
##
##   godot --headless --path . --mode=client res://tools/verify_weapon_coatings.tscn

const TABLE_PATH: String = "res://source/common/gameplay/crafting/resources/salvage_table.tres"
const STATION_PATH: String = "res://source/common/gameplay/crafting/resources/alchemy_station.tres"

## THE owner-authored spec, in one place: which weapon family breaks into what.
## If a family silently stops paying out, this is what catches it.
## Note there is deliberately no rustic WAND — the art pack does not contain one.
const EXPECTED_SOURCES: Dictionary = {
	"sword_spore.item": "blightspore", "hammer_spore.item": "blightspore",
	"spore_bow.item": "blightspore", "wand_spore.item": "blightspore",
	"book_spore.item": "blightspore",

	"sword_poison.item": "venom_sac", "hammer_poison.item": "venom_sac",
	"poison_bow.item": "venom_sac", "wand_poison.item": "venom_sac",
	"book_poison.item": "venom_sac",

	"sword_fairy.item": "fairy_dust", "hammer_fairy.item": "fairy_dust",
	"fairy_bow.item": "fairy_dust", "wand_fairy.item": "fairy_dust",
	"book_fairy.item": "fairy_dust",

	"sword_fire.item": "ember_ash", "hammer_fire.item": "ember_ash",
	"fire_bow.item": "ember_ash", "fire_wand.item": "ember_ash",
	"book_fire.item": "ember_ash",

	"sword_bone.item": "bone", "hammer_bone.item": "bone",
	"bone_bow.item": "bone", "wand_bone.item": "bone", "book_bone.item": "bone",

	"sword_rustic.item": "iron_bar", "hammer_rustic.item": "iron_bar",
	"rustic_bow.item": "iron_bar", "book_rustic.item": "iron_bar",
}

## Materials whose yield is a RANDOM range, and the range expected.
const EXPECTED_RANGES: Dictionary = {
	"bone": [2, 4],
	"iron_bar": [1, 3],
}

## potion slug -> [coating kind, brew level, herb slug]
##
## The coatings are END-GAME herblore, deliberately: level 65 arrives quickly,
## and when every potion in the game sat at or below it the skill had nothing
## left above the halfway mark. 70/76/82/88 also leaves 89-99 open for whatever
## gets brewed next.
const EXPECTED_POTIONS: Dictionary = {
	"weapon_poison": ["poison", 70, "blightspore"],
	"weapon_salve": ["heal", 76, "fairy_dust"],
	"weapon_ember": ["burn", 82, "ember_ash"],
	"weapon_poison_plus": ["poison", 88, "venom_sac"],
}

const MATERIAL_SLUGS: Array[String] = [
	"blightspore", "venom_sac", "fairy_dust", "ember_ash", "bone", "iron_bar",
]

var _fails: Array[String] = []


func _ready() -> void:
	_check_materials()
	_check_salvage_table()
	_check_potions()
	_check_brews()
	_check_job_listing()

	if _fails.is_empty():
		print("VERIFY_PASS weapon_coatings")
		get_tree().quit(0)
	else:
		for f: String in _fails:
			print("VERIFY_FAIL ", f)
		get_tree().quit(1)


func _check_materials() -> void:
	for slug: String in MATERIAL_SLUGS:
		var mat: MaterialItem = ContentRegistryHub.load_by_slug(
			&"items", StringName(slug)
		) as MaterialItem
		if mat == null:
			_fails.append("%s missing from the item registry as a MaterialItem" % slug)
			continue
		if int(mat.get_meta(&"id", 0)) <= 0:
			_fails.append("%s has no registry id" % slug)
		if mat.inventory_tab() != Item.InventoryTab.MATERIAL:
			_fails.append("%s should live in the Materials tab" % slug)
		print("  material ", slug, " id=", int(mat.get_meta(&"id", 0)),
			" vendor=", mat.vendor_value)


func _check_salvage_table() -> void:
	var table: SalvageTable = load(TABLE_PATH) as SalvageTable
	if table == null:
		_fails.append("salvage_table.tres failed to load as SalvageTable")
		return
	if table.profession != &"herblore":
		_fails.append("salvage profession should be herblore, got %s" % table.profession)
	if table.recipes.size() != EXPECTED_SOURCES.size():
		_fails.append("expected %d salvage recipes, got %d" % [
			EXPECTED_SOURCES.size(), table.recipes.size()
		])

	var seen: Array[String] = []
	for recipe: SalvageRecipe in table.recipes:
		if recipe == null or recipe.source_item == null:
			_fails.append("null salvage recipe / source item")
			continue
		var slug: String = String(recipe.source_item.get_meta(&"slug", &""))
		if seen.has(slug):
			_fails.append("%s appears twice in the salvage table" % slug)
		seen.append(slug)
		if not EXPECTED_SOURCES.has(slug):
			_fails.append("%s is salvageable but is not in the spec" % slug)
		if int(recipe.source_item.get_meta(&"id", 0)) <= 0:
			_fails.append("%s source has no registry id" % slug)
		if recipe.outputs.is_empty():
			_fails.append("%s yields nothing" % slug)
		if recipe.xp_reward <= 0:
			_fails.append("%s pays no herblore xp" % slug)
		_check_outputs(slug, recipe)

	for want: String in EXPECTED_SOURCES:
		if not seen.has(want):
			_fails.append("salvage table missing %s" % want)

	# The id lookup the bag button and the server handler both go through.
	var spore_sword: Item = ContentRegistryHub.load_by_slug(&"items", &"sword_spore.item")
	if spore_sword != null and table.recipe_for(int(spore_sword.get_meta(&"id", 0))) == null:
		_fails.append("recipe_for(spore sword id) returned null")
	if table.recipe_for(0) != null:
		_fails.append("recipe_for(0) should be null")
	# An ordinary weapon must NOT be salvageable — the button is offered off this.
	var bronze: Item = ContentRegistryHub.load_by_slug(&"items", &"sword_bronze.item")
	if bronze != null and table.recipe_for(int(bronze.get_meta(&"id", 0))) != null:
		_fails.append("bronze sword should not be salvageable")


func _check_outputs(slug: String, recipe: SalvageRecipe) -> void:
	var want_mat: String = str(EXPECTED_SOURCES.get(slug, ""))
	for output: SalvageOutput in recipe.outputs:
		if output == null or output.item == null:
			_fails.append("%s has a broken output" % slug)
			continue
		var got_mat: String = String(output.item.get_meta(&"slug", &""))
		if got_mat != want_mat:
			_fails.append("%s yields %s, spec says %s" % [slug, got_mat, want_mat])
		if output.min_amount <= 0 or output.max_amount < output.min_amount:
			_fails.append("%s has an invalid yield range %d-%d" % [
				slug, output.min_amount, output.max_amount
			])
			continue
		if EXPECTED_RANGES.has(want_mat):
			var want_range: Array = EXPECTED_RANGES[want_mat]
			if output.min_amount != int(want_range[0]) or output.max_amount != int(want_range[1]):
				_fails.append("%s should roll %d-%d %s, got %d-%d" % [
					slug, int(want_range[0]), int(want_range[1]), want_mat,
					output.min_amount, output.max_amount
				])
			if not output.is_random():
				_fails.append("%s yield should be random" % slug)
		elif output.is_random():
			_fails.append("%s yield should be fixed, not a range" % slug)
		# A roll must always land inside the authored range — this is the number
		# that becomes real items in a player's bag.
		for _try: int in 60:
			var rolled: int = output.roll()
			if rolled < output.min_amount or rolled > output.max_amount:
				_fails.append("%s rolled %d outside %d-%d" % [
					slug, rolled, output.min_amount, output.max_amount
				])
				break
		print("  salvage ", slug, " -> ", output.describe(),
			"  lv", recipe.required_level, " xp", recipe.xp_reward)


func _check_potions() -> void:
	for slug: String in EXPECTED_POTIONS:
		var spec: Array = EXPECTED_POTIONS[slug]
		var potion: ConsumableItem = ContentRegistryHub.load_by_slug(
			&"items", StringName(slug)
		) as ConsumableItem
		if potion == null:
			_fails.append("%s missing from the item registry as a ConsumableItem" % slug)
			continue
		if int(potion.get_meta(&"id", 0)) <= 0:
			_fails.append("%s has no registry id" % slug)
		if not potion.is_coating():
			_fails.append("%s is not a valid coating" % slug)
		if String(potion.coating_kind) != str(spec[0]):
			_fails.append("%s coating kind %s, want %s" % [slug, potion.coating_kind, spec[0]])
		if not is_equal_approx(potion.coating_duration_s, 300.0):
			_fails.append("%s should last 5 minutes, got %.0fs" % [
				slug, potion.coating_duration_s
			])
		# Every coating shares ONE cooldown category, and it is not the health /
		# mana one — coating a weapon must never block an emergency heal.
		if potion.cooldown_category != &"weapon_coating":
			_fails.append("%s should use the shared weapon_coating cooldown" % slug)
		if potion.stat_lines().size() < 2:
			_fails.append("%s is missing its coating tooltip lines" % slug)
		print("  potion ", slug, " kind=", potion.coating_kind)
		for line: Dictionary in potion.stat_lines():
			print("    tooltip: ", line.get("text", ""))


func _check_brews() -> void:
	var station: CraftingStationResource = load(STATION_PATH)
	if station == null:
		_fails.append("alchemy_station.tres failed to load")
		return
	for slug: String in EXPECTED_POTIONS:
		var spec: Array = EXPECTED_POTIONS[slug]
		var brew: CraftingRecipe = null
		for recipe: CraftingRecipe in station.recipes:
			if recipe == null or recipe.output_item == null:
				continue
			if String(recipe.output_item.get_meta(&"slug", &"")) == slug:
				brew = recipe
		if brew == null:
			_fails.append("alchemy station has no %s recipe" % slug)
			continue
		if brew.required_level != int(spec[1]):
			_fails.append("%s brew level %d != %d" % [slug, brew.required_level, int(spec[1])])
		var herb_amount: int = 0
		var vial: int = 0
		for ingredient: CraftIngredient in brew.ingredients:
			if ingredient == null or ingredient.item == null:
				continue
			var ing_slug: String = String(ingredient.item.get_meta(&"slug", &""))
			if ing_slug == str(spec[2]):
				herb_amount = ingredient.amount
			elif ing_slug == "vial_of_water":
				vial = ingredient.amount
		if vial != 1:
			_fails.append("%s should take 1 vial of water, got %d" % [slug, vial])
		if herb_amount <= 0:
			_fails.append("%s should take %s, got %d" % [slug, spec[2], herb_amount])
		print("  brew ", slug, " lv", brew.required_level, " xp", brew.xp_reward,
			"  vial=", vial, " ", spec[2], "=", herb_amount)


func _check_job_listing() -> void:
	var perks: JobPerks = JobRegistry.perks_for(&"herblore")
	if perks == null:
		_fails.append("JobRegistry missing herblore")
		return
	if perks.recipe_items.size() != perks.recipe_levels.size():
		_fails.append("herblore recipe_items/%d and recipe_levels/%d out of step" % [
			perks.recipe_items.size(), perks.recipe_levels.size()
		])
	for slug: String in EXPECTED_POTIONS:
		var want_level: int = int(EXPECTED_POTIONS[slug][1])
		var listed: bool = false
		for i: int in perks.recipe_items.size():
			var item: Item = perks.recipe_items[i]
			if item == null or String(item.get_meta(&"slug", &"")) != slug:
				continue
			listed = true
			if i < perks.recipe_levels.size() and perks.recipe_levels[i] != want_level:
				_fails.append("herblore lists %s at %d, want %d" % [
					slug, perks.recipe_levels[i], want_level
				])
		if not listed:
			_fails.append("herblore job does not list %s" % slug)
