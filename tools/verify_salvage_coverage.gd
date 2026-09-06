extends SceneTree
## Gate for the boss weapon -> salvage -> herblore loop.
##
##     godot --headless --path . -s tools/verify_salvage_coverage.gd
##
## The loop these bosses are built around is: farm the boss repeatedly, take the
## weapons, break them down for herblore materials. The weapons are deliberately
## LOW TIER because they are a material tap, not a gear step — so a weapon with
## no salvage recipe is not a minor omission, it is a boss whose entire payout
## dead-ends. That is exactly what happened to Ankhemet: five Sunsteel weapons,
## no recipe anywhere, on a 30,000g level-72 contract.
##
## Checks:
##  1. Every boss weapon AT OR BELOW [constant SALVAGE_TIER_CAP] has a salvage
##     recipe. Endgame weapons are exempt — they are keepers, not fodder.
##  2. Every salvage output has somewhere to go — a crafting recipe consumes it.
##  3. Salvage-only materials really are salvage-only: no gathering node. That
##     exclusivity is what makes the loop worth running rather than just farming
##     herbs, so a material with both taps is flagged.

const BOSS_PATH: String = "res://source/common/gameplay/characters/npc/types/bosses/"
const SALVAGE_TABLE: String = "res://source/common/gameplay/crafting/resources/salvage_table.tres"
const NODES_PATH: String = "res://source/common/gameplay/maps/components/mineable_nodes/"
const STATIONS_PATH: String = "res://source/common/gameplay/crafting/resources/"

## Above this weapon mastery tier, a boss weapon is a KEEPER, not salvage fodder,
## and needs no recipe. The line is not arbitrary: every salvageable family today
## sits on a continuous 5-level ladder — bone 2, spore 5, rustic 10, poison 15,
## fairy 20, sunsteel 25, fire 30 — and the next boss weapons after that jump
## straight to 70/80/90 (Colossus, Behemoth, Worldbreaker off Ossuran and the
## Sun-Eater). Those are endgame gear players equip and keep; breaking one down
## for herbs would be a mistake, not a loop. 40 sits in the empty gap between.
const SALVAGE_TIER_CAP: int = 40

var _failures: Array[String] = []
var _warnings: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	var table: SalvageTable = ResourceLoader.load(SALVAGE_TABLE) as SalvageTable
	if table == null:
		_f("salvage_table.tres did not load as a SalvageTable")
		return _report()

	# slug -> recipe, for the coverage check.
	var salvageable: Dictionary = {}
	var outputs: Dictionary = {}
	for recipe: SalvageRecipe in table.recipes:
		if recipe == null or recipe.source_item == null:
			continue
		salvageable[StringName(str(recipe.source_item.get_meta(&"slug", &"")))] = true
		for out: SalvageOutput in recipe.outputs:
			if out != null and out.item != null:
				outputs[StringName(str(out.item.get_meta(&"slug", &"")))] = true

	_check_boss_weapons(salvageable)
	_check_outputs_consumed(outputs)
	_check_outputs_exclusive(outputs)
	_report()


## Every weapon on a boss's table must be breakable.
func _check_boss_weapons(salvageable: Dictionary) -> void:
	var missing: Dictionary = {}
	for path: String in FileUtils.get_all_file_at(BOSS_PATH, "*.tres"):
		var enemy: EnemyTypeResource = ResourceLoader.load(path) as EnemyTypeResource
		if enemy == null or not enemy.is_boss:
			continue
		for drop: LootDrop in enemy.loot:
			if drop == null or drop.item == null or not (drop.item is WeaponItem):
				continue
			# Endgame weapons are terminal by design — see SALVAGE_TIER_CAP.
			if (drop.item as WeaponItem).required_mastery_level > SALVAGE_TIER_CAP:
				continue
			var slug: StringName = StringName(str(drop.item.get_meta(&"slug", &"")))
			_checks += 1
			if not salvageable.has(slug):
				# Grouped by weapon, not by boss — one missing family shows up on
				# every boss that drops it and would otherwise spam the report.
				missing[slug] = str(enemy.display_name)
	for slug: StringName in missing:
		_f("'%s' drops from %s but has NO salvage recipe — that boss's weapons "
			% [slug, missing[slug]] + "dead-end")


## A salvage output nothing consumes is a material that piles up forever.
func _check_outputs_consumed(outputs: Dictionary) -> void:
	var consumed: Dictionary = {}
	for path: String in FileUtils.get_all_file_at(STATIONS_PATH, "*.tres"):
		var station: CraftingStationResource = ResourceLoader.load(
			path) as CraftingStationResource
		if station == null:
			continue
		for recipe: CraftingRecipe in station.recipes:
			if recipe == null:
				continue
			for ing: CraftIngredient in recipe.ingredients:
				if ing != null and ing.item != null:
					consumed[StringName(str(ing.item.get_meta(&"slug", &"")))] = true
	for slug: StringName in outputs:
		_checks += 1
		if not consumed.has(slug):
			_f("salvage yields '%s' but no crafting recipe consumes it — it is a "
				% slug + "dead-end material")


## Salvage-only materials must have no gathering node, or the loop is redundant.
func _check_outputs_exclusive(outputs: Dictionary) -> void:
	var gatherable: Dictionary = {}
	for path: String in FileUtils.get_all_file_at(NODES_PATH, "*.tres"):
		var node: Resource = ResourceLoader.load(path)
		if node == null:
			continue
		# Node resources name their yield differently across types; the file name
		# matches the material slug by convention, which is what the audit uses.
		gatherable[StringName(path.get_file().get_basename())] = true
	for slug: StringName in outputs:
		_checks += 1
		if gatherable.has(slug):
			# A warning, not a failure: bone and iron_bar are deliberately shared
			# with other sources. Flagged so a NEW boss-gated herb is not quietly
			# given a node, which would make its boss farm pointless.
			_warnings.append("'%s' is both a salvage output and gatherable — the "
				% slug + "salvage tap for it is redundant with farming")


func _f(msg: String) -> void:
	_failures.append(msg)


func _report() -> void:
	print("")
	for line: String in _warnings:
		print("  WARN: %s" % line)
	if _failures.is_empty():
		print("VERIFY_PASS  (%d checks, %d warnings)" % [_checks, _warnings.size()])
	else:
		for line: String in _failures:
			printerr("  FAIL: %s" % line)
		print("VERIFY_FAIL  (%d failures / %d checks)" % [_failures.size(), _checks])
	quit(0 if _failures.is_empty() else 1)
