extends SceneTree
## Verifies the quest / daily / slayer / loot / projectile reward pass. Run headless:
##   godot --headless --path . -s tools/verify_progression_pass.gd
## Prints VERIFY_PASS on success, VERIFY_FAIL (+ reasons) otherwise.
##
## Pre-existing `-s` noise (client autoloads absent, so ConsumableItem and
## melee_arc.tscn fail to compile) is expected and is NOT what this reports — see
## tools/audit_boss_integration.gd. Anything loaded through ConsumableItem reads as
## null here and on the live server does not, so this deliberately never asserts on
## potion drops.

const QUESTS_DIR: String = "res://source/common/gameplay/quests/resources/"
const FUNGUS_DIR: String = "res://source/common/gameplay/characters/npc/types/fungus/"
const CHARACTER_SCENE: String = "res://source/common/gameplay/characters/character.tscn"

var _fails: Array[String] = []


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   %s" % label)
	else:
		_fails.append(label)
		print("  FAIL %s" % label)


func _init() -> void:
	_slayer()
	_turael_variety()
	_woodland_east()
	_crafting_xp()
	_fungus_loot()
	_quest_rewards()
	_quest_locations()
	_dailies()
	_starter_kit()
	_muzzle()
	print("")
	if _fails.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL (%d)" % _fails.size())
		for f: String in _fails:
			print("  - %s" % f)
	quit(0 if _fails.is_empty() else 1)


# --- Goblin Chief + his minions count for Slayer ------------------------------

func _slayer() -> void:
	print("[slayer]")
	var goblins: SlayerTaskDef = load(
		"res://source/common/gameplay/slayer/tasks/goblins.tres"
	) as SlayerTaskDef
	_check(goblins != null, "goblins.tres loads")
	if goblins == null:
		return
	_check(goblins.matches(&"goblin_chief"), "goblin_chief is on the Goblins task")
	_check(goblins.matches(&"goblin_runt"), "goblin_runt (the Chief's adds) still counts")
	_check(
		is_equal_approx(SlayerTaskService.boss_xp_bonus(true), SlayerTaskService.BOSS_XP_MULTIPLIER),
		"a boss on task carries the Slayer XP bonus (x%.1f)" % SlayerTaskService.BOSS_XP_MULTIPLIER
	)
	_check(is_equal_approx(SlayerTaskService.boss_xp_bonus(false), 1.0), "trash carries no bonus")
	var rng: Vector2i = goblins.xp_per_kill_range()
	_check(rng.y > rng.x, "advertised XP range widened by the boss (%d-%d)" % [rng.x, rng.y])


# --- Turael can send a Slayer-1 player somewhere other than Goblin Woodland ----

## The low-level variants added so the entry master has a real table, each
## paired with the map it was actually placed in. A task whose monster exists only
## as a .tres is a task you cannot complete.
##
## cutpurses/orc_whelps used to live here too, but bandit_cutpurse and orc_whelp
## only ever spawn in forest.tscn (= DimWood, Slayer-20+ gated) — unreachable at
## Slayer 1. Pulled from Turael's pool entirely; Durael's "Orcs" task already
## covers orc_whelp at the level where DimWood is actually reachable.
const LOW_TASKS: Array[Array] = [
	["dusk_bats", &"dusk_bat", "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"],
	["bonepickers", &"bonepicker", "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"],
	["spore_ticks", &"spore_tick", "res://source/common/gameplay/maps/maps/fungus_cave/fungus_cave.tscn"],
]
## Everything a Slayer-1 character could be sent after BEFORE this pass — all of it
## in one zone, which is the complaint being fixed.
const OLD_LOW_TASKS: Array[String] = ["rats", "wolves", "goblins"]


func _turael_variety() -> void:
	print("[turael]")
	var turael: SlayerMasterResource = load(
		"res://source/common/gameplay/slayer/masters/turael.tres"
	) as SlayerMasterResource
	_check(turael != null, "turael.tres loads")
	if turael == null:
		return

	# What a brand-new Slayer 1 character can actually be assigned.
	var rollable: Array[SlayerMasterTaskEntry] = turael.eligible_entries(1, {})
	var slugs: PackedStringArray = PackedStringArray()
	for entry: SlayerMasterTaskEntry in rollable:
		slugs.append(String(entry.task.task_slug()))
	_check(rollable.size() >= 6, "Slayer 1 can roll %d tasks (was %d)" % [
		rollable.size(), OLD_LOW_TASKS.size()
	])

	var zones: Dictionary[String, bool] = {}
	for entry: SlayerMasterTaskEntry in rollable:
		zones[entry.task.location_hint] = true
	_check(zones.size() >= 4, "those tasks span %d zones, not just the woodland" % zones.size())

	for row: Array in LOW_TASKS:
		var slug: String = row[0]
		var enemy_slug: StringName = row[1]
		var map_path: String = row[2]
		var task: SlayerTaskDef = load(
			"res://source/common/gameplay/slayer/tasks/%s.tres" % slug
		) as SlayerTaskDef
		if task == null:
			_check(false, "%s.tres loads" % slug)
			continue
		_check(task.min_slayer_level <= 1, "%s is open at Slayer 1" % slug)
		_check(slugs.has(slug), "%s is in Turael's table" % slug)
		_check(not task.location_hint.is_empty(), "%s says where to hunt (%s)" % [
			slug, task.location_hint
		])

		# The monster must exist, be registered, and be tuned near the goblin band —
		# an "easy" task pointing at a 1,100 HP orc is the bug, not the fix.
		var mob: EnemyTypeResource = ContentRegistryHub.load_by_slug(
			&"enemy_types", enemy_slug
		) as EnemyTypeResource
		if mob == null:
			_check(false, "%s is registered in the enemy index" % enemy_slug)
			continue
		_check(task.matches(enemy_slug), "%s counts %s" % [slug, enemy_slug])
		# Doubled after playtest: too soft at the original numbers. The ceiling is
		# what still separates them from their full-strength parents (cave skeleton
		# 700, orc 1,100, bandit 900) — cross it and the "easy" task is a lie.
		_check(
			mob.max_health <= 700.0,
			"%s stays under its parent tier (%d HP)" % [enemy_slug, int(mob.max_health)]
		)
		_check(not mob.loot.is_empty(), "%s drops something" % enemy_slug)

		# And it has to be somewhere a player can walk to. Read the scene as TEXT
		# rather than instantiating it: hostile_npc.tscn pulls in weapon.gd, which
		# cannot compile without the client autoloads, so an instantiate() here
		# yields zero HostileNpc children and would report a false failure.
		_check(_placements(map_path, enemy_slug) >= 4, "%s is placed in %s" % [
			enemy_slug, map_path.get_file()
		])


## How many nodes in [param map_path] carry [param enemy_slug] as their enemy_data,
## counted straight out of the .tscn text.
func _placements(map_path: String, enemy_slug: StringName) -> int:
	var text: String = FileAccess.get_file_as_string(map_path)
	if text.is_empty():
		return 0
	# The ext_resource id the map gave this enemy type, then the nodes using it.
	var ext_id: String = ""
	for line: String in text.split("
"):
		if not line.begins_with("[ext_resource"):
			continue
		if not line.contains("/%s.tres" % enemy_slug):
			continue
		var at: int = line.rfind("id=\"")
		if at < 0:
			continue
		var rest: String = line.substr(at + 4)
		ext_id = rest.substr(0, rest.find("\""))
		break
	if ext_id.is_empty():
		return 0
	var needle: String = "enemy_data = ExtResource(\"%s\")" % ext_id
	var count: int = 0
	for line: String in text.split("
"):
		if line.strip_edges() == needle:
			count += 1
	return count


# --- Goblin Woodlands East is actually inhabited ------------------------------

const WOODLAND_EAST: String = "res://source/common/gameplay/maps/maps/woodland/woodland_east.tscn"


func _woodland_east() -> void:
	print("[woodland east]")
	var text: String = FileAccess.get_file_as_string(WOODLAND_EAST)
	if text.is_empty():
		_check(false, "woodland_east.tscn reads")
		return
	var mobs: int = text.count("parent=\"ReplicatedPropsContainer\"")
	# It shipped with 20 bodies over a ~1,800x1,600 px zone, which is why it read
	# as empty. Anything under 40 is back to that.
	_check(mobs >= 40, "the east expansion holds %d mobs (shipped with 20)" % mobs)

	# And they have to be the zone's own level band (5-15), not only the level-48
	# rabid wolves and level-36 bats that were the bulk of the original 20.
	for slug: StringName in [&"goblin_runt", &"goblin_cutter", &"bandit_cutpurse", &"orc_whelp"]:
		_check(
			_placements(WOODLAND_EAST, slug) > 0,
			"%s is stationed in the east expansion" % slug
		)


# --- Crafting XP is worth the click ------------------------------------------

const CRAFT_DIR: String = "res://source/common/gameplay/crafting/resources/"
## Anchors after the 3x pass, so a future edit that silently halves the rate again
## trips here rather than in a player's log.
const CRAFT_XP_ANCHORS: Dictionary[String, int] = {
	"furnace.tres": 60,   # Bronze Bar, the first thing anyone smelts
	"anvil.tres": 60,     # Bronze Bar at the smithing table
}


func _crafting_xp() -> void:
	print("[crafting xp]")
	var lowest: int = 1 << 30
	var recipes: int = 0
	for file_name: String in DirAccess.get_files_at(CRAFT_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var station: CraftingStationResource = load(CRAFT_DIR + file_name) as CraftingStationResource
		if station == null:
			continue
		var first_tier: int = 0
		for recipe: CraftingRecipe in station.recipes:
			if recipe == null:
				continue
			recipes += 1
			lowest = mini(lowest, recipe.xp_reward)
			if first_tier == 0 and recipe.required_level <= 1:
				first_tier = recipe.xp_reward
		if CRAFT_XP_ANCHORS.has(file_name):
			_check(
				first_tier == CRAFT_XP_ANCHORS[file_name],
				"%s tier-1 recipe pays %d xp (expected %d)" % [
					file_name, first_tier, CRAFT_XP_ANCHORS[file_name]
				]
			)
	_check(recipes >= 280, "%d recipes scanned" % recipes)
	_check(lowest >= 30, "even the cheapest recipe pays %d xp" % lowest)
	# The number that answers "is this still slow?": OSRS levels 1-10 is 1,154 xp.
	var to_ten: int = SkillXp.total_xp_for_level(10)
	@warning_ignore("integer_division")
	var crafts: int = to_ten / maxi(1, lowest)
	_check(crafts <= 40, "crafting 1-10 is ~%d of the cheapest craft" % crafts)


# --- Fungus creatures drop something worth picking up -------------------------

func _fungus_loot() -> void:
	print("[fungus loot]")
	for slug: String in ["sporeling", "puffcap", "spore_swarm", "myconid_brute", "fungal_heart"]:
		var mob: EnemyTypeResource = load(FUNGUS_DIR + slug + ".tres") as EnemyTypeResource
		if mob == null:
			_check(false, "%s loads" % slug)
			continue
		var gold_max: int = 0
		var entries: int = 0
		for drop: LootDrop in mob.loot:
			if drop == null or drop.item == null:
				continue # a ConsumableItem the -s harness cannot compile; see header
			entries += 1
			if String(drop.item.get_meta(&"slug", &"")) == "gold":
				gold_max = drop.max_amount
		_check(entries >= 4, "%s has a real loot table (%d entries)" % [slug, entries])
		_check(gold_max >= 20, "%s drops meaningful gold (max %d)" % [slug, gold_max])


# --- Quest rewards scale, and the top tier hands over a T1 wood chest ---------

func _quest_rewards() -> void:
	print("[quest rewards]")
	var thin: PackedStringArray = PackedStringArray()
	var chests: int = 0
	var top_gold: int = 0
	for path: String in _tres_under(QUESTS_DIR):
		if path.ends_with("daily_pool.tres"):
			continue
		var quest: QuestResource = load(path) as QuestResource
		if quest == null:
			continue
		if quest.reward_gold < 400 or quest.reward_mastery_xp < 2000:
			thin.append("%s (%dg / %d mxp)" % [
				path.get_file(), quest.reward_gold, quest.reward_mastery_xp
			])
		top_gold = maxi(top_gold, quest.reward_gold)
		for reward: QuestReward in quest.reward_items:
			if reward != null and reward.item is LootChestItem:
				var table: ChestResource = (reward.item as LootChestItem).resolve_table()
				if table != null and table.tier == 1:
					chests += 1
	_check(thin.is_empty(), "every quest pays real gold + mastery XP%s" % (
		"" if thin.is_empty() else " — thin: " + ", ".join(thin)
	))
	_check(top_gold >= 2500, "the hardest quests pay 2,500g (top = %d)" % top_gold)
	_check(chests >= 5, "T1 wood chests are handed out by %d quests" % chests)


func _quest_locations() -> void:
	print("[quest locations]")
	var missing_visit: PackedStringArray = PackedStringArray()
	var missing_return: PackedStringArray = PackedStringArray()
	for path: String in _tres_under(QUESTS_DIR):
		if path.ends_with("daily_pool.tres"):
			continue
		var quest: QuestResource = load(path) as QuestResource
		if quest == null:
			continue
		for objective: QuestObjective in quest.objectives:
			if objective == null or objective.type != QuestObjective.Type.VISIT:
				continue
			if not objective.describe().contains(" · "):
				missing_visit.append("%s (%s)" % [path.get_file(), objective.describe()])
		if quest.auto_complete:
			continue
		if quest.return_prompt().contains("the quest giver"):
			missing_return.append(path.get_file())
	_check(missing_visit.is_empty(), "VISIT objectives name a place%s" % (
		"" if missing_visit.is_empty() else " — " + ", ".join(missing_visit)
	))
	_check(missing_return.is_empty(), "turn-in quests name the NPC%s" % (
		"" if missing_return.is_empty() else " — " + ", ".join(missing_return)
	))
	var ilka: QuestResource = load(QUESTS_DIR + "hollow_seep/the_builders_grave.tres") as QuestResource
	_check(ilka != null and ilka.objectives.size() == 1, "The Builders' Grave loads")
	if ilka != null and not ilka.objectives.is_empty() and ilka.objectives[0] != null:
		var line: String = ilka.objectives[0].describe()
		_check(line.contains("Dune Scout Ilka"), "Builders' Grave names Ilka (%s)" % line)
		_check(line.contains("Desert"), "Builders' Grave says Desert (%s)" % line)
	var helka: QuestResource = load(QUESTS_DIR + "hollow_seep/the_last_foundry.tres") as QuestResource
	_check(helka != null and helka.objectives.size() == 1, "The Last Foundry loads")
	if helka != null and not helka.objectives.is_empty() and helka.objectives[0] != null:
		var foundry: String = helka.objectives[0].describe()
		_check(foundry.contains("Forgemaster Helka"), "Last Foundry names Helka (%s)" % foundry)
		_check(foundry.contains("entrance"), "Last Foundry says entrance (%s)" % foundry)


# --- Daily board: buffed, location-hinted, skippable --------------------------

func _dailies() -> void:
	print("[dailies]")
	var pool: DailyQuestPool = load(QUESTS_DIR + "daily_pool.tres") as DailyQuestPool
	_check(pool != null, "daily_pool.tres loads")
	if pool == null:
		return
	var thin: PackedStringArray = PackedStringArray()
	var unlocated: PackedStringArray = PackedStringArray()
	for t: DailyQuestTemplate in pool.templates:
		if t == null:
			continue
		if t.reward_gold < 400 or t.reward_mastery_xp < 5000:
			thin.append("%d (%dg / %d mxp)" % [t.template_id, t.reward_gold, t.reward_mastery_xp])
		# Targeted kinds must say WHERE; the generic action kinds have no one place.
		if (t.kind == DailyQuestTemplate.Kind.KILL or t.kind == DailyQuestTemplate.Kind.COLLECT) \
				and t.location_hint.is_empty():
			unlocated.append(t.describe())
	_check(thin.is_empty(), "every daily pays real gold + mastery XP%s" % (
		"" if thin.is_empty() else " — thin: " + ", ".join(thin)
	))
	_check(unlocated.is_empty(), "every targeted daily says where to go%s" % (
		"" if unlocated.is_empty() else " — missing: " + ", ".join(unlocated)
	))
	_check(DailyQuestService.MAX_SKIPS_PER_DAY == 3, "3 skips a day")
	_check(
		DailyQuestService.BONUS_GOLD >= 2000,
		"the all-3 bonus is worth finishing (%dg)" % DailyQuestService.BONUS_GOLD
	)
	_skip_flow()


## Exercises skip() end to end on a throwaway PlayerResource: a reroll replaces the
## slot with a DIFFERENT template, spends exactly one skip, and the budget runs out
## after three.
func _skip_flow() -> void:
	var res: PlayerResource = PlayerResource.new()
	res.level = 8
	DailyQuestService.get_or_roll(res)
	if res.daily_quests.is_empty():
		_check(false, "a level-8 character rolls a daily set")
		return
	var before: int = int((res.daily_quests[0] as Dictionary).get("template_id", 0))
	var result: Dictionary = DailyQuestService.skip(res, before)
	_check(bool(result.get("ok", false)), "skip() rerolls a daily (%s)" % result.get("reason", "ok"))
	var after: int = int((res.daily_quests[0] as Dictionary).get("template_id", 0))
	_check(after != before, "the skipped slot holds a different task (%d -> %d)" % [before, after])
	_check(
		DailyQuestService.skips_left(res) == 2,
		"one skip spent, %d left" % DailyQuestService.skips_left(res)
	)
	# Burn the rest, then confirm the cap actually bites.
	for _i: int in 4:
		DailyQuestService.skip(res, int((res.daily_quests[0] as Dictionary).get("template_id", 0)))
	_check(DailyQuestService.skips_left(res) == 0, "the budget bottoms out at 0, never negative")
	var refused: Dictionary = DailyQuestService.skip(
		res, int((res.daily_quests[0] as Dictionary).get("template_id", 0))
	)
	_check(
		not bool(refused.get("ok", false)) and str(refused.get("reason", "")) == "no_skips_left",
		"a 4th skip is refused"
	)


# --- Every slug in the new-character kit resolves -----------------------------

func _starter_kit() -> void:
	print("[starter kit]")
	var missing: PackedStringArray = PackedStringArray()
	for entry: Array in WorldStoreSqlite.STARTING_KIT:
		if ContentRegistryHub.id_from_slug(&"items", entry[0] as StringName) <= 0:
			missing.append(String(entry[0]))
	_check(missing.is_empty(), "all %d kit slugs resolve%s" % [
		WorldStoreSqlite.STARTING_KIT.size(),
		"" if missing.is_empty() else " — missing: " + ", ".join(missing),
	])
	_check(
		WorldStoreSqlite.STARTING_GOLD >= 1000,
		"new characters start with %dg" % WorldStoreSqlite.STARTING_GOLD
	)


# --- The computed muzzle still matches the drawn hand rig ---------------------

func _muzzle() -> void:
	print("[projectile muzzle]")
	var scene: PackedScene = load(CHARACTER_SCENE) as PackedScene
	if scene == null:
		_check(false, "character.tscn loads")
		return
	var body: Node = scene.instantiate()
	var offset: Node2D = body.get_node_or_null(^"HandOffset") as Node2D
	var spot: Node2D = body.get_node_or_null(^"HandOffset/HandPivot/RightHandSpot") as Node2D
	if offset == null or spot == null:
		_check(false, "the hand rig is where muzzle_position assumes")
		body.free()
		return
	# muzzle_position reproduces the rig by hand so the shot does not ride a
	# network-smoothed node; if the rig moves, these constants must move with it.
	_check(
		is_equal_approx(offset.position.y, AbilityResource.MUZZLE_HEIGHT_PX),
		"muzzle height matches HandOffset.y (%.1f vs %.1f)" % [
			AbilityResource.MUZZLE_HEIGHT_PX, offset.position.y
		]
	)
	_check(
		is_equal_approx(spot.position.x, AbilityResource.MUZZLE_FORWARD_PX),
		"muzzle reach matches RightHandSpot.x (%.1f vs %.1f)" % [
			AbilityResource.MUZZLE_FORWARD_PX, spot.position.x
		]
	)
	body.free()


## Every .tres under [param dir], recursively.
func _tres_under(dir: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for file_name: String in DirAccess.get_files_at(dir):
		if file_name.ends_with(".tres"):
			out.append(dir + file_name)
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_tres_under(dir + sub + "/"))
	return out
