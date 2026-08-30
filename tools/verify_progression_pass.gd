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


# --- Daily board: skilling-only, deterministic, difficulty-scaled -------------

## The board is an autoload (DailyQuestManager) but this tool runs under `-s`,
## where autoloads are not instantiated. The manager deliberately holds no state,
## so a bare `.new()` outside the tree exercises the real logic; `_ready` (the
## only part that touches another autoload) never fires because the node is never
## added to a tree.
func _board() -> Node:
	var script: GDScript = load("res://source/common/gameplay/quests/daily_quest_manager.gd")
	return script.new() as Node


func _dailies() -> void:
	print("[dailies]")
	var mgr: Node = _board()
	_check(mgr != null, "DailyQuestManager loads")
	if mgr == null:
		return

	# Every slug on the roster must be a real job, or the board offers a task no
	# XP grant can ever advance. This is the check that catches someone authoring
	# the DISPLAY names ("Crafting", "Farming") where the slugs (&"outfitting",
	# &"harvesting") belong.
	var unknown: PackedStringArray = PackedStringArray()
	for slug: StringName in mgr.SKILLS:
		if not JobRegistry.has_job(slug):
			unknown.append(String(slug))
	_check(unknown.is_empty(), "every rostered skill is a registered job%s" % (
		"" if unknown.is_empty() else " - unknown: " + ", ".join(unknown)
	))
	_check(mgr.SKILLS.size() == 9, "nine skilling jobs on the roster (%d)" % mgr.SKILLS.size())

	var table: DailyRewardTable = load(QUESTS_DIR + "daily_rewards.tres") as DailyRewardTable
	_check(table != null, "daily_rewards.tres loads")
	if table != null:
		_check(
			table.gold_for(DailyTaskResource.Difficulty.HARD)
				> table.gold_for(DailyTaskResource.Difficulty.EASY),
			"Hard pays more than Easy (%dg vs %dg)" % [
				table.gold_for(DailyTaskResource.Difficulty.HARD),
				table.gold_for(DailyTaskResource.Difficulty.EASY),
			]
		)
		# Hard is a whole-session commitment against a ~10.7x bigger target, so it
		# has to beat farming Easy three times over on a per-action basis.
		var per_action_easy: float = float(table.gold_for(0)) / 37.5
		var per_action_hard: float = float(table.gold_for(2)) / 400.0
		_check(
			per_action_hard > per_action_easy,
			"Hard pays better PER ACTION than Easy (%.1fg vs %.1fg)" % [
				per_action_hard, per_action_easy
			]
		)
	_check(
		mgr.BONUS_GOLD >= 2000,
		"the all-3 bonus is worth finishing (%dg)" % mgr.BONUS_GOLD
	)
	_daily_determinism(mgr)
	_daily_flow(mgr)


## The whole desync story rests on the offer being a pure function of
## (player_id, UTC day): a player who relogs, crashes, or loses a save must be
## handed the identical three skills and the identical candidate targets.
func _daily_determinism(mgr: Node) -> void:
	var a: PlayerResource = PlayerResource.new()
	a.player_id = 4242
	var b: PlayerResource = PlayerResource.new()
	b.player_id = 4242

	var skills_a: PackedStringArray = PackedStringArray()
	for task: DailyTaskResource in mgr.get_board(a):
		skills_a.append(String(task.skill))
	var skills_b: PackedStringArray = PackedStringArray()
	for task: DailyTaskResource in mgr.get_board(b):
		skills_b.append(String(task.skill))
	_check(
		skills_a == skills_b,
		"the same character rerolls the same board (%s vs %s)" % [
			", ".join(skills_a), ", ".join(skills_b)
		]
	)
	_check(skills_a.size() == 3, "three slots offered (%d)" % skills_a.size())
	var distinct: Dictionary = {}
	for s: String in skills_a:
		distinct[s] = true
	_check(
		distinct.size() == skills_a.size(),
		"the three skills are distinct (%s)" % ", ".join(skills_a)
	)

	# A different character should get a different board; identical rolls for
	# everyone would mean the seed quietly ignores player_id.
	var other: PlayerResource = PlayerResource.new()
	other.player_id = 99_001
	var skills_other: PackedStringArray = PackedStringArray()
	for task: DailyTaskResource in mgr.get_board(other):
		skills_other.append(String(task.skill))
	_check(
		skills_other != skills_a,
		"a different character gets a different board (%s)" % ", ".join(skills_other)
	)

	var opts_a: Array[Dictionary] = mgr.difficulty_options(a, 0)
	var opts_b: Array[Dictionary] = mgr.difficulty_options(b, 0)
	_check(opts_a.size() == 3, "three difficulties offered per slot (%d)" % opts_a.size())
	var stable: bool = true
	for i: int in opts_a.size():
		if int(opts_a[i].get("target", -1)) != int(opts_b[i].get("target", -2)):
			stable = false
	_check(stable, "candidate targets are stable across reopens")
	if opts_a.size() == 3:
		_check(
			int(opts_a[0]["target"]) < int(opts_a[1]["target"])
				and int(opts_a[1]["target"]) < int(opts_a[2]["target"]),
			"targets scale Easy < Medium < Hard (%d / %d / %d)" % [
				int(opts_a[0]["target"]), int(opts_a[1]["target"]), int(opts_a[2]["target"])
			]
		)
		for i: int in 3:
			var band: Vector2i = DailyTaskResource.band_for(i)
			var target: int = int(opts_a[i]["target"])
			_check(
				target >= band.x and target <= band.y,
				"%s target %d sits inside its band %d-%d" % [
					DailyTaskResource.difficulty_name(i), target, band.x, band.y
				]
			)


## Accept to progress to auto-complete to claim, plus the three things that make
## the board exploitable if they ever regress: re-picking a difficulty, claiming
## twice, and one skill advancing another skill's task.
func _daily_flow(mgr: Node) -> void:
	var res: PlayerResource = PlayerResource.new()
	res.player_id = 777
	var board: Array[DailyTaskResource] = mgr.get_board(res)
	if board.is_empty():
		_check(false, "a character is offered a board")
		return
	var skill: StringName = board[0].skill

	_check(
		not bool(mgr.claim(res, 0).get("ok", true)),
		"an un-accepted slot cannot be claimed"
	)
	# What the card offered must be exactly what the player is held to. These are
	# two separate calls into the seeded stream, and if they ever diverge the
	# player commits to "gather 40" and silently owes 180.
	var offered: Array[Dictionary] = mgr.difficulty_options(res, 0)
	var offered_easy: int = int(offered[DailyTaskResource.Difficulty.EASY]["target"])
	var accepted: Dictionary = mgr.accept(res, 0, DailyTaskResource.Difficulty.EASY)
	_check(
		int(accepted.get("target", -1)) == offered_easy,
		"the accepted target is the one the card offered (%d vs %d)" % [
			int(accepted.get("target", -1)), offered_easy
		]
	)
	_check(
		bool(accepted.get("ok", false)),
		"accept() starts the task (%s)" % accepted.get("reason", "ok")
	)
	var target: int = int(accepted.get("target", 0))
	_check(target > 0, "accepting stamps a target (%d)" % target)
	_check(
		not bool(mgr.accept(res, 0, DailyTaskResource.Difficulty.HARD).get("ok", true)),
		"the difficulty cannot be re-picked once accepted"
	)

	# Progress arrives through the same signature the bus emitters use.
	mgr._on_skill_action(res, skill, 0, target - 1)
	var mid: Array[DailyTaskResource] = mgr.get_board(res)
	_check(
		mid[0].progress == target - 1,
		"progress tracks actions (%d/%d)" % [mid[0].progress, target]
	)
	_check(not mid[0].is_complete(), "not complete one short of target")
	_check(
		not bool(mgr.claim(res, 0).get("ok", true)),
		"an incomplete task cannot be claimed"
	)

	# Overshoot deliberately: the counter must clamp, not run past the target.
	mgr._on_skill_action(res, skill, 0, 50)
	var done: Array[DailyTaskResource] = mgr.get_board(res)
	_check(done[0].is_complete(), "the task auto-completes at target")
	_check(
		done[0].progress == target,
		"progress clamps at the target (%d/%d)" % [done[0].progress, target]
	)

	# A task in a DIFFERENT skill must not be advanced by this skill's actions.
	var other_slot: int = -1
	for i: int in board.size():
		if board[i].skill != skill:
			other_slot = i
			break
	if other_slot >= 0:
		mgr.accept(res, other_slot, DailyTaskResource.Difficulty.EASY)
		mgr._on_skill_action(res, skill, 0, 25)
		_check(
			mgr.get_board(res)[other_slot].progress == 0,
			"actions only advance their own skill"
		)

	var claimed: Dictionary = mgr.claim(res, 0)
	_check(
		bool(claimed.get("ok", false)),
		"a complete task claims (%s)" % claimed.get("reason", "ok")
	)
	_check(int(claimed.get("gold", 0)) > 0, "the claim pays gold (%dg)" % int(claimed.get("gold", 0)))
	var paid_skill: bool = false
	for row_v: Variant in (claimed.get("skill_xp", []) as Array):
		if str((row_v as Dictionary).get("skill", "")) == String(skill):
			paid_skill = int((row_v as Dictionary).get("xp", 0)) > 0
	_check(paid_skill, "the claim pays XP into the assigned skill")
	_check(
		not bool(mgr.claim(res, 0).get("ok", true)),
		"a claimed task cannot be claimed twice"
	)

	# Relog: state must survive a save/load round trip through JSON, which is
	# where ints come back as floats and a naive reader silently loses progress.
	var saved: String = JSON.stringify(mgr.save_state(res))
	var reloaded: PlayerResource = PlayerResource.new()
	reloaded.player_id = res.player_id
	mgr.load_state(reloaded, JSON.parse_string(saved))
	var after: Array[DailyTaskResource] = mgr.get_board(reloaded)
	_check(
		after[0].accepted and after[0].claimed and after[0].progress == target,
		"accepted state survives a save/load round trip (%d/%d, claimed=%s)" % [
			after[0].progress, after[0].target_amount, after[0].claimed
		]
	)
	# Pre-overhaul rows carry template_id and no skill. They must be dropped, not
	# resurrected as a broken slot.
	var legacy: PlayerResource = PlayerResource.new()
	legacy.player_id = res.player_id
	mgr.load_state(legacy, {
		"quests": [{"template_id": 4, "count_so_far": 2, "claimed": false}],
		"refresh_at_ms": 0,
	})
	_check(legacy.daily_quests.is_empty(), "pre-overhaul daily rows are discarded on load")


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
