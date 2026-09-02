extends Node
## Gate for the four high-tier arrow tiers: items, procs, recipes and the splat
## colour wiring.
##
##   godot --path . --mode=client res://tools/verify_high_tier_arrows.tscn
##
## Scene mode, not `-s`: AmmoItem is a GearItem and the proc service reaches
## CombatHit, which pulls autoloads a `-s` SceneTree run does not provide.
##
## The checks that earn their keep are the ones a screenshot cannot make:
##   * a half-authored proc (a chance with no effect, or an effect with no
##     chance) ships as an ordinary arrow and nothing anywhere complains
##   * an `effect_type` typo is dispatched to `_: pass`, so the arrow reads as
##     having a proc, rolls it, and does nothing
##   * a SPLAT_* constant renamed without updating FloatingDamageNumber drops
##     the hit splat silently back to default orange
##   * recipe_items / recipe_levels in the job files are POSITIONAL; a drift
##     there mislabels every recipe after the insertion point

const TIERS: Array[String] = ["dragon", "obsidian", "celestial", "astralite"]
const ARROW := "res://source/common/gameplay/items/ammo/%s_arrow.tres"
const HEADS := "res://source/common/gameplay/items/materials/metals/%s_arrowheads.tres"
const ANVIL := "res://source/common/gameplay/crafting/resources/anvil.tres"
const BENCH := "res://source/common/gameplay/crafting/resources/fletching_bench.tres"
const FCT := "res://source/client/ui/combat_feedback/floating_damage_number.gd"
## The tier this ladder continues. Every new arrow must beat it.
const RUNITE := "res://source/common/gameplay/items/ammo/runite_arrow.tres"

var _bad: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _fail(msg: String) -> void:
	_bad += 1
	print("  FAIL ", msg)
	push_error(msg)


func _go() -> void:
	_check_items()
	_check_splat_colors()
	_check_recipes()
	_check_job_mirrors()
	print("HIGH_TIER_ARROWS bad=", _bad)
	if _bad == 0:
		print("VERIFY_PASS high_tier_arrows")
	get_tree().quit(0)


func _known_effects() -> Array[StringName]:
	return [
		AmmoProcService.EFFECT_THERMAL, AmmoProcService.EFFECT_SIPHON,
		AmmoProcService.EFFECT_SPLASH, AmmoProcService.EFFECT_GRAVITY,
	]


func _check_items() -> void:
	var runite: AmmoItem = load(RUNITE) as AmmoItem
	var floor_ad: float = _ad_of(runite) if runite != null else 0.0
	var last_ad: float = floor_ad
	var last_mastery: int = runite.required_mastery_level if runite != null else 0
	var seen_effects: Dictionary = {}

	for tier: String in TIERS:
		var heads: Item = load(HEADS % tier) as Item
		if heads == null:
			_fail("%s arrowheads failed to load" % tier)
		elif int(heads.get_meta(&"id", 0)) <= 0:
			_fail("%s arrowheads are not in the items index" % tier)

		var arrow: AmmoItem = load(ARROW % tier) as AmmoItem
		if arrow == null:
			_fail("%s arrow failed to load or is not an AmmoItem" % tier)
			continue
		if int(arrow.get_meta(&"id", 0)) <= 0:
			_fail("%s arrow is not in the items index" % tier)

		# A proc must be COMPLETE. Half-authored ships as a plain arrow.
		if not arrow.has_proc():
			_fail("%s arrow has an incomplete proc (chance %.2f, effect '%s', magnitude %.2f)"
				% [tier, arrow.proc_chance, arrow.effect_type, arrow.proc_magnitude])
		if arrow.effect_type not in _known_effects():
			_fail("%s arrow effect_type '%s' is not dispatched by AmmoProcService — it would roll and do nothing"
				% [tier, arrow.effect_type])
		if seen_effects.has(arrow.effect_type):
			_fail("%s arrow reuses effect_type '%s'" % [tier, arrow.effect_type])
		seen_effects[arrow.effect_type] = true
		# Duration-based effects need a duration; instant ones must not claim one.
		var needs_duration: bool = arrow.effect_type in [
			AmmoProcService.EFFECT_THERMAL, AmmoProcService.EFFECT_GRAVITY
		]
		if needs_duration and arrow.proc_duration_s <= 0.0:
			_fail("%s arrow's %s needs a duration" % [tier, arrow.effect_type])
		# Fractions must be fractions — a 35% siphon authored as 35.0 heals the
		# attacker for 35x the hit.
		if arrow.effect_type in [AmmoProcService.EFFECT_SIPHON, AmmoProcService.EFFECT_GRAVITY] \
				and arrow.proc_magnitude > 1.0:
			_fail("%s arrow magnitude %.2f is a fraction 0-1 for %s"
				% [tier, arrow.proc_magnitude, arrow.effect_type])
		if arrow.description.strip_edges().is_empty():
			_fail("%s arrow has no tooltip" % tier)

		var ad: float = _ad_of(arrow)
		if ad <= last_ad:
			_fail("%s arrow ad %.0f does not beat the tier below (%.0f)" % [tier, ad, last_ad])
		if arrow.required_mastery_level <= last_mastery:
			_fail("%s arrow mastery %d does not exceed the tier below (%d)"
				% [tier, arrow.required_mastery_level, last_mastery])
		last_ad = ad
		last_mastery = arrow.required_mastery_level
		print("ok %-10s ad %.0f, mastery %d, %d%% %s (mag %.2f, %.1fs)" % [
			tier, ad, arrow.required_mastery_level, roundi(arrow.proc_chance * 100.0),
			arrow.effect_type, arrow.proc_magnitude, arrow.proc_duration_s,
		])


func _ad_of(item: AmmoItem) -> float:
	if item == null:
		return 0.0
	for mod: StatModifier in item.base_modifiers:
		if mod != null and StringName(mod.stat_name) == Stat.AD:
			return mod.value
	return 0.0


## Every splat constant the service can emit must be matched by name in the
## client's colour table. These are joined by a STRING, not a symbol, so a
## rename compiles fine on both sides and silently loses the colour.
func _check_splat_colors() -> void:
	var text: String = FileAccess.get_file_as_string(FCT)
	if text.is_empty():
		_fail("could not read " + FCT)
		return
	for splat: StringName in [
		AmmoProcService.SPLAT_THERMAL, AmmoProcService.SPLAT_SIPHON,
		AmmoProcService.SPLAT_SPLASH, AmmoProcService.SPLAT_GRAVITY,
	]:
		if not text.contains('&"%s"' % splat):
			_fail("FloatingDamageNumber has no colour for '%s' — the splat falls back to orange"
				% splat)
	print("ok splat colours: 4 arrow effects matched in FloatingDamageNumber")


func _check_recipes() -> void:
	_check_station(ANVIL, "_arrowheads", "Smithing", 1)
	_check_station(BENCH, "_arrow", "Fletching", 2)


## `expect_inputs` is how many distinct ingredients the recipe should have: an
## arrowhead recipe is one bar, an arrow is shafts plus heads.
func _check_station(path: String, suffix: String, job: String, expect_inputs: int) -> void:
	var station: CraftingStationResource = load(path) as CraftingStationResource
	if station == null:
		_fail("could not load " + path)
		return
	var last_level: int = 0
	var last_xp: int = 0
	for tier: String in TIERS:
		var want: String = tier + suffix
		var recipe: CraftingRecipe = null
		for candidate: CraftingRecipe in station.recipes:
			if candidate != null and candidate.output_item != null \
					and str(candidate.output_item.get_meta(&"slug", &"")) == want:
				recipe = candidate
				break
		if recipe == null:
			_fail("no %s recipe for %s" % [job, want])
			continue
		if recipe.output_amount != 10:
			_fail("%s yields %d, not 10" % [want, recipe.output_amount])
		if recipe.ingredients.size() != expect_inputs:
			_fail("%s takes %d ingredients, expected %d"
				% [want, recipe.ingredients.size(), expect_inputs])
		if recipe.required_level <= last_level:
			_fail("%s level %d does not exceed the tier below (%d)"
				% [want, recipe.required_level, last_level])
		if recipe.xp_reward <= last_xp:
			_fail("%s %s XP %d does not exceed the tier below (%d)"
				% [want, job, recipe.xp_reward, last_xp])
		last_level = recipe.required_level
		last_xp = recipe.xp_reward
		print("ok %-22s %s lv%-3d %4d xp, %d input(s) -> 10"
			% [want, job, recipe.required_level, recipe.xp_reward, recipe.ingredients.size()])


## recipe_items and recipe_levels are read POSITIONALLY. A length drift does not
## error — it silently labels every recipe after the insertion point with the
## wrong level in the skill guide.
func _check_job_mirrors() -> void:
	for entry: Array in [
		["res://source/common/gameplay/jobs/smithing.tres", "_arrowheads"],
		["res://source/common/gameplay/jobs/fletching.tres", "_arrow"],
	]:
		var job: JobPerks = load(entry[0]) as JobPerks
		if job == null:
			_fail("could not load " + entry[0])
			continue
		if job.recipe_items.size() != job.recipe_levels.size():
			_fail("%s: recipe_items %d != recipe_levels %d"
				% [entry[0].get_file(), job.recipe_items.size(), job.recipe_levels.size()])
			continue
		for tier: String in TIERS:
			var want: String = tier + str(entry[1])
			var found: bool = false
			for item: Item in job.recipe_items:
				if item != null and str(item.get_meta(&"slug", &"")) == want:
					found = true
					break
			if not found:
				_fail("%s is missing from %s recipe_items" % [want, entry[0].get_file()])
		print("ok %-16s %d recipes, levels parallel"
			% [entry[0].get_file(), job.recipe_items.size()])
