extends SceneTree
## Headless checks for the ten boss-drop relics (tools/build_boss_relics.gd):
##   - every relic loads as a GearItem sitting in the `relic` slot, with its icon
##   - modifiers only use stats StatModifier actually exposes (a stat outside
##     that enum silently does nothing and shows as a dead tooltip line)
##   - the items index knows each relic, and its hash matches the file on disk
##   - each boss carries exactly ONE drop of its relic, at a sane chance
##   - the ladder actually ladders: each greater sigil out-values its lesser
##     charm of the same colour family, and costs more
##
##   godot --headless --path . -s tools/verify_boss_relics.gd

const RELIC_DIR := "res://source/common/gameplay/items/gears/relics"
const TYPES := "res://source/common/gameplay/characters/npc/types"
const INDEX := "res://source/common/registry/indexes/items_index.tres"
const LOOT_SCRIPT := "res://source/common/gameplay/combat/loot_drop.gd"

## `[slug, boss, chance]` — mirrors the build tool's table.
const EXPECTED: Array = [
	["relic_mossgrown", "goblins/goblin_chief", 0.001],
	["relic_sporebloom", "fungus/fungal_heart", 0.001],
	["relic_bloodbrand", "bandit_captain", 0.001],
	["relic_duskglass", "skeleton_mage", 0.001],
	["relic_emberbrand", "orc_leader", 0.001],
	["relic_rotmire", "bosses/cistern_sovereign", 0.001],
	["relic_coreblossom", "mecha_stone_golem", 0.001],
	["relic_scarabheart", "bosses/sand_king", 0.001],
	["relic_netherglass", "trpg/trpg_necromancer", 0.001],
	["relic_cinderheart", "bosses/cinderborn", 0.001],
]

## Lesser charm -> greater sigil, by colour family.
const FAMILIES: Array = [
	["relic_mossgrown", "relic_rotmire"],
	["relic_sporebloom", "relic_coreblossom"],
	["relic_bloodbrand", "relic_scarabheart"],
	["relic_duskglass", "relic_netherglass"],
	["relic_emberbrand", "relic_cinderheart"],
]

## The nine stats StatModifier's @export_enum offers. Anything else is inert.
const LIVE_STATS: Array[String] = [
	"health_max", "mana_max", "mana_regen", "armor", "mr",
	"ad", "ap", "ability_haste", "move_speed",
]

## Rough gold-per-point weights, used only to assert the ladder climbs.
const WEIGHTS: Dictionary = {
	"armor": 1.0, "mr": 1.0, "health_max": 0.5, "ad": 1.5, "ap": 1.5,
	"mana_max": 0.4, "mana_regen": 8.0, "move_speed": 2.0, "ability_haste": 2.0,
}


func _init() -> void:
	var failures: Array[String] = []
	var budgets: Dictionary = {}
	var vendors: Dictionary = {}

	var index: ContentIndex = load(INDEX) as ContentIndex
	if index == null:
		print("VERIFY_FAIL items index failed to load")
		quit(1)
		return
	var indexed: Dictionary = {}
	for entry: Dictionary in index.entries:
		indexed[StringName(entry.get(&"slug", &""))] = entry

	for row: Array in EXPECTED:
		var slug: String = row[0]
		var path := "%s/%s.tres" % [RELIC_DIR, slug]
		var relic: GearItem = load(path) as GearItem
		if relic == null:
			failures.append("%s failed to load as GearItem" % slug)
			continue

		if relic.slot == null or relic.slot.key != &"relic":
			failures.append("%s is not in the relic slot" % slug)
		if relic.item_icon == null:
			failures.append("%s has no icon" % slug)
		if String(relic.item_name).is_empty() or relic.item_name == &"ItemDefault":
			failures.append("%s has no item_name" % slug)
		if relic.description.strip_edges().is_empty():
			failures.append("%s has no description" % slug)
		if not relic.can_trade:
			failures.append("%s is untradeable" % slug)
		if relic.vendor_value <= 0:
			failures.append("%s has vendor_value %d" % [slug, relic.vendor_value])
		# GearItem defaults to 5 (smithable armour batches); relics are keepsakes.
		if relic.stack_limit != 1:
			failures.append("%s stacks to %d, expected 1" % [slug, relic.stack_limit])

		# Relics stay ungated like every other relic/ring — the zone is the gate.
		if relic.required_level != 0 or relic.required_mastery_level != 0:
			failures.append("%s carries a level/mastery gate" % slug)

		var budget := 0.0
		if relic.base_modifiers.is_empty():
			failures.append("%s grants no stats" % slug)
		for mod: StatModifier in relic.base_modifiers:
			if mod == null:
				failures.append("%s has a null modifier" % slug)
				continue
			if not LIVE_STATS.has(mod.stat_name):
				failures.append("%s grants '%s', which no gear path reads" % [slug, mod.stat_name])
				continue
			if is_zero_approx(mod.value):
				failures.append("%s grants 0 %s" % [slug, mod.stat_name])
			budget += float(WEIGHTS[mod.stat_name]) * mod.value
		budgets[slug] = budget
		vendors[slug] = relic.vendor_value

		# --- index -----------------------------------------------------------
		var entry: Dictionary = indexed.get(StringName(slug), {})
		if entry.is_empty():
			failures.append("%s is missing from items_index" % slug)
		else:
			if int(relic.get_meta(&"id", 0)) != int(entry.get(&"id", -1)):
				failures.append("%s metadata/id disagrees with the index" % slug)
			if String(entry.get(&"hash", "")) != FileAccess.get_sha256(path):
				failures.append("%s index hash is stale" % slug)

		failures.append_array(_check_drop(slug, String(row[1]), float(row[2])))

	# --- the ladder climbs ------------------------------------------------------
	for pair: Array in FAMILIES:
		var lesser: String = pair[0]
		var greater: String = pair[1]
		if not budgets.has(lesser) or not budgets.has(greater):
			continue
		if float(budgets[greater]) <= float(budgets[lesser]):
			failures.append("%s (%.1f) does not out-stat %s (%.1f)" % [
				greater, budgets[greater], lesser, budgets[lesser]
			])
		if int(vendors[greater]) <= int(vendors[lesser]):
			failures.append("%s is not worth more than %s" % [greater, lesser])

	if failures.is_empty():
		print("VERIFY_PASS boss_relics (%d relics, %d families)" % [
			EXPECTED.size(), FAMILIES.size()
		])
		quit(0)
	else:
		for f: String in failures:
			print("VERIFY_FAIL ", f)
		quit(1)


## Check the boss's loot wiring by reading the `.tres` as TEXT.
##
## Six of the ten bosses cannot be `load()`ed in a headless `-s` run: they drop
## `*.item.tres` weapons, and WeaponItem's script chain reaches weapon.gd, which
## needs the `Client` autoload and fails to compile here. That is a pre-existing
## limit of headless runs (the same one that makes update_items_index.gd
## additive), so this reads the file the build tool actually writes instead of
## the object graph.
func _check_drop(slug: String, boss: String, chance: float) -> Array[String]:
	var out: Array[String] = []
	var path := "%s/%s.tres" % [TYPES, boss]
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		out.append("%s: cannot read %s" % [slug, boss])
		return out

	var drop_id := "Drop_%s" % slug
	var ext_id := ""
	var ext_count := 0
	var in_block := false
	var saw_item := false
	var saw_chance := false
	var saw_script := false
	var blocks := 0

	# The ext_resource id of loot_drop.gd, which the drop's `script` must name.
	var loot_id := ""
	for line: String in text.split("\n"):
		if line.begins_with("[ext_resource") and line.contains(LOOT_SCRIPT):
			loot_id = line.get_slice(' id="', 1).get_slice('"', 0)
			break
	if loot_id.is_empty():
		out.append("%s: no loot_drop.gd ext_resource in %s" % [slug, boss])
		return out

	for line: String in text.split("\n"):
		if line.begins_with("[ext_resource") and line.contains("%s/%s.tres" % [RELIC_DIR, slug]):
			ext_count += 1
			# Leading space, so `id` does not match the `uid` on the same line.
			ext_id = line.get_slice(' id="', 1).get_slice('"', 0)
		if line.begins_with("["):
			in_block = line.begins_with("[sub_resource") and line.contains('id="%s"' % drop_id)
			if in_block:
				blocks += 1
			continue
		if not in_block:
			continue
		if line.begins_with("script = "):
			saw_script = true
			if not line.contains('ExtResource("%s")' % loot_id):
				out.append("%s: drop script in %s is %s, not ExtResource(\"%s\")" % [
					slug, boss, line.get_slice(" = ", 1), loot_id
				])
		if line.begins_with("item = "):
			saw_item = true
			if not line.contains('ExtResource("%s")' % ext_id):
				out.append("%s: drop points at %s, not the relic" % [slug, line])
		if line.begins_with("chance = "):
			saw_chance = true
			if not is_equal_approx(float(line.get_slice(" = ", 1)), chance):
				out.append("%s: drops from %s at %s, expected %.2f" % [
					slug, boss, line.get_slice(" = ", 1), chance
				])
		# min/max are left at their default of 1 — a relic must never stack.
		if line.begins_with("min_amount = ") or line.begins_with("max_amount = "):
			if int(line.get_slice(" = ", 1)) != 1:
				out.append("%s: drops in a stack from %s (%s)" % [slug, boss, line])

	if ext_count != 1:
		out.append("%s: %d ext_resource lines in %s, expected 1" % [slug, ext_count, boss])
	if blocks != 1:
		out.append("%s: %d '%s' blocks in %s, expected 1" % [slug, blocks, drop_id, boss])
	if not saw_script:
		out.append("%s: drop block in %s has no script" % [slug, boss])
	if not saw_item:
		out.append("%s: drop block in %s has no item" % [slug, boss])
	if not saw_chance:
		out.append("%s: drop block in %s has no chance" % [slug, boss])

	# The drop has to be listed on the resource, not just defined above it.
	var loot_line := ""
	for line: String in text.split("\n"):
		if line.begins_with("loot = Array["):
			loot_line = line
			break
	if loot_line.is_empty():
		out.append("%s: %s has no loot array" % [slug, boss])
	elif loot_line.count('SubResource("%s")' % drop_id) != 1:
		out.append("%s: listed %d times in %s's loot array, expected 1" % [
			slug, loot_line.count('SubResource("%s")' % drop_id), boss
		])

	# A relic behind a boss that never comes back is one-per-world. skeleton_mage
	# is the exception: it is a dungeon boss, respawned fresh on every run.
	if text.contains("respawns = false") and boss != "skeleton_mage":
		out.append("%s hangs off %s, which never respawns" % [slug, boss])
	return out
