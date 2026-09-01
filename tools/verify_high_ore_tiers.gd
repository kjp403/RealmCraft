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
