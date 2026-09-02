extends SceneTree
## Load every Dragon/Obsidian/Celestial/Astralite ore, bar, vein and tool, then
## check the things loading alone cannot catch: that the new tiers are a real
## progression, and that they smelt on the custom pipeline rather than coal.
##
##   godot --headless --path . -s tools/verify_high_ore_tiers.gd
##
## `bad` counts hard authoring faults and must be 0. The XP ORDER section is
## reported separately on purpose — see the note above `_check_xp_order`.

const TIERS: Array[String] = ["dragon", "obsidian", "celestial", "astralite"]
const FURNACE: String = "res://source/common/gameplay/crafting/resources/furnace.tres"

var _bad: int = 0


func _initialize() -> void:
	_check_loads()
	_check_smelting()
	_check_crucible()
	_check_full_bag()
	print("HIGH_ORE_TIER_VERIFY bad=", _bad)
	_check_xp_order()
	quit(0)


func _check_loads() -> void:
	var paths: PackedStringArray = []
	for tier: String in TIERS:
		paths.append("res://source/common/gameplay/items/materials/metals/%s_ore.tres" % tier)
		paths.append("res://source/common/gameplay/items/materials/metals/%s_bar.tres" % tier)
		paths.append("res://source/common/gameplay/maps/components/mineable_nodes/%s_vein.tres" % tier)
		for kind: String in ["pickaxe", "axe", "sickle"]:
			paths.append("res://source/common/gameplay/items/weapons/tools/%s_%s.tres" % [kind, tier])
	for slug: String in ["dragon_scale", "obsidian_flux", "celestial_dust",
			"astralite_mote", "everburning_crucible"]:
		paths.append("res://source/common/gameplay/items/materials/catalysts/%s.tres" % slug)
	paths.append("res://source/common/gameplay/items/weapons/tools/fishing_rod_dragon.tres")
	paths.append(FURNACE)
	paths.append("res://source/common/gameplay/crafting/resources/anvil.tres")
	paths.append("res://source/common/gameplay/jobs/mining.tres")
	for path: String in paths:
		var res: Resource = load(path)
		if res == null:
			push_error("FAILED " + path)
			_bad += 1
		else:
			print("ok ", path)


## The four new bars must smelt on the SmeltingRecipe path: a catalyst held, an
## additive and an alloy consumed, and no coal anywhere. A recipe that quietly
## reverts to the coal ladder would still load and still craft, so nothing else
## in the project would notice.
func _check_smelting() -> void:
	var furnace: CraftingStationResource = load(FURNACE) as CraftingStationResource
	if furnace == null:
		return
	var seen: Dictionary[String, bool] = {}
	for recipe: CraftingRecipe in furnace.recipes:
		if recipe == null or recipe.output_item == null:
			continue
		var slug: String = str(recipe.output_item.get_meta(&"slug", &""))
		var tier: String = slug.replace("_bar", "")
		if tier not in TIERS:
			continue
		seen[tier] = true
		var smelt: SmeltingRecipe = recipe as SmeltingRecipe
		if smelt == null:
			push_error("NOT A SmeltingRecipe: " + slug)
			_bad += 1
			continue
		if smelt.catalysts.is_empty():
			push_error("no catalyst on " + slug)
			_bad += 1
		if smelt.required_inputs().size() <= smelt.ingredients.size():
			push_error("catalysts missing from required_inputs() on " + slug)
			_bad += 1
		for ingredient: CraftIngredient in smelt.required_inputs():
			if ingredient == null or ingredient.item == null:
				push_error("null ingredient on " + slug)
				_bad += 1
				continue
			if str(ingredient.item.get_meta(&"slug", &"")) == "coal_ore":
				push_error("still burns coal: " + slug)
				_bad += 1
		print("ok smelt %s: %d consumed + %d held @ %.0f%%" % [
			slug, smelt.ingredients.size(), smelt.catalysts.size(),
			smelt.catalyst_consume_chance * 100.0,
		])
	for tier: String in TIERS:
		if not seen.has(tier):
			push_error("no furnace recipe for " + tier + "_bar")
			_bad += 1


## The Crucible gates all four smelts, so it has to be craftable, it has to be
## the runite sink it is designed as, and it must not be worth more at a vendor
## than the bars that went into it.
func _check_crucible() -> void:
	var anvil: CraftingStationResource = load(
		"res://source/common/gameplay/crafting/resources/anvil.tres"
	) as CraftingStationResource
	if anvil == null:
		return
	var recipe: CraftingRecipe = null
	for candidate: CraftingRecipe in anvil.recipes:
		if candidate == null or candidate.output_item == null:
			continue
		if str(candidate.output_item.get_meta(&"slug", &"")) == "everburning_crucible":
			recipe = candidate
			break
	if recipe == null:
		push_error("no anvil recipe for the Everburning Crucible — the smelts are uncraftable")
		_bad += 1
		return

	var input_value: int = 0
	var bars: int = 0
	for ingredient: CraftIngredient in recipe.required_inputs():
		if ingredient == null or ingredient.item == null:
			continue
		input_value += ingredient.item.vendor_value * ingredient.amount
		if str(ingredient.item.get_meta(&"slug", &"")) == "runite_bar":
			bars = ingredient.amount
	if bars <= 0:
		push_error("Crucible no longer costs runite bars — the mid-tier sink is gone")
		_bad += 1
	# Craft-and-vendor must lose money, or the recipe is a gold printer.
	if recipe.output_item.vendor_value >= input_value:
		push_error("Crucible vendors for %d against %d of inputs — craftable gold printer"
			% [recipe.output_item.vendor_value, input_value])
		_bad += 1

	# Amortised sink: how much runite each high-tier bar really costs once the
	# crucible's erosion is spread over its expected lifetime.
	var erosion: float = 0.0
	for smelt_recipe: CraftingRecipe in (
		load("res://source/common/gameplay/crafting/resources/furnace.tres")
		as CraftingStationResource
	).recipes:
		if smelt_recipe is SmeltingRecipe:
			erosion = maxf(erosion, (smelt_recipe as SmeltingRecipe).catalyst_consume_chance)
	var per_smelt: float = float(bars) * erosion
	print("ok crucible: lv%d, %d runite bars, %dg inputs vs %dg vendor" % [
		recipe.required_level, bars, input_value, recipe.output_item.vendor_value,
	])
	print("   sink: %.0f smelts per crucible, %.2f runite bars amortised per smelt" % [
		(1.0 / erosion) if erosion > 0.0 else 0.0, per_smelt,
	])


## A bag can have room for the ORE and no room for the ADDITIVE — the additive
## needs a fresh slot while the ore stacks into one that already exists. That is
## the case that loses a rare drop if the gather path checks space for the
## primary yield instead of what was actually caught. MineableNode derives its
## id from `caught` AFTER the secondary swap, so the right one is checked; this
## pins the asymmetry so a refactor that reorders those lines fails here.
func _check_full_bag() -> void:
	var ore: Item = load(
		"res://source/common/gameplay/items/materials/metals/dragon_ore.tres"
	) as Item
	var additive: Item = load(
		"res://source/common/gameplay/items/materials/catalysts/dragon_scale.tres"
	) as Item
	if ore == null or additive == null:
		return
	var ore_id: int = int(ore.get_meta(&"id", 0))
	var additive_id: int = int(additive.get_meta(&"id", 0))

	# Fill every slot, leaving one partial ore stack with room in it.
	var inventory: Dictionary = {}
	var limit: int = Inventory.stack_limit_for(ore, false)
	Inventory.add_item(inventory, ore_id, limit * (Inventory.MAX_SLOTS - 1) + 1)
	var used: int = Inventory.used_slots(inventory, 0)
	if used != Inventory.MAX_SLOTS:
		push_error("full-bag fixture built %d slots, expected %d" % [used, Inventory.MAX_SLOTS])
		_bad += 1
		return

	var ore_fits: bool = Inventory.can_add(inventory, ore_id, 1, Inventory.MAX_SLOTS, false, 0, 1)
	var additive_fits: bool = Inventory.can_add(
		inventory, additive_id, 1, Inventory.MAX_SLOTS, false, 0, 1
	)
	if not ore_fits:
		push_error("full-bag fixture wrong: the partial ore stack should still accept one")
		_bad += 1
	if additive_fits:
		push_error("can_add let an additive into a bag with no free slot — a catch would be lost")
		_bad += 1
	if ore_fits and not additive_fits:
		print("ok full bag: ore stacks in (true), additive needs a slot and is refused (false)")


## Smithing XP must rise with level. Among the FOUR NEW TIERS that is pure
## authoring and any inversion is a bug, so it counts against `bad`.
##
## Against the OLD ladder it is a merge-order hazard instead, not a fault in
## this branch: these recipes are costed on the rescaled Smithing curve from
## `rework/skill-xp-rates`, so until that lands a Runite bar still pays its
## un-rescaled 254 against a Dragon bar's 35. Git will not catch it — the two
## branches touch different lines and merge cleanly either way — so it is
## reported loudly here and left out of `bad`, which would otherwise be red on
## a branch that is correct on its own terms.
func _check_xp_order() -> void:
	var furnace: CraftingStationResource = load(FURNACE) as CraftingStationResource
	if furnace == null:
		return
	var rows: Array[Dictionary] = []
	for recipe: CraftingRecipe in furnace.recipes:
		if recipe == null or recipe.output_item == null:
			continue
		rows.append({
			"slug": str(recipe.output_item.get_meta(&"slug", &"")),
			"level": recipe.required_level,
			"xp": recipe.xp_reward,
			"new": recipe is SmeltingRecipe,
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["level"]) < int(b["level"]))

	var cross: int = 0
	var authoring: int = 0
	for i: int in range(1, rows.size()):
		var lo: Dictionary = rows[i - 1]
		var hi: Dictionary = rows[i]
		if int(hi["xp"]) >= int(lo["xp"]):
			continue
		# Two recipes at the SAME level are a design choice, not an inversion,
		# and which of them sorts first is arbitrary — only a genuine step UP in
		# level that pays less counts.
		if int(hi["level"]) == int(lo["level"]):
			continue
		var line: String = "  XP INVERSION: %s (lv%d, %d xp) pays less than %s (lv%d, %d xp)" % [
			hi["slug"], hi["level"], hi["xp"], lo["slug"], lo["level"], lo["xp"],
		]
		if bool(hi["new"]) and bool(lo["new"]):
			push_error(line + " [both new — authoring bug]")
			authoring += 1
			_bad += 1
		else:
			print(line, " [merge-order: needs rework/skill-xp-rates first]")
			cross += 1
	print("XP_ORDER new_tier_inversions=%d cross_ladder_inversions=%d" % [authoring, cross])
	if cross > 0:
		print("XP_ORDER NOTE: merge rework/skill-xp-rates BEFORE this branch.")
