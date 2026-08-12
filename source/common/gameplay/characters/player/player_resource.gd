class_name PlayerResource
extends Resource


const ATTRIBUTE_POINTS_PER_LEVEL: int = 3

## Profile customization limits, shared by the client edit UI and server validator.
const MAX_PROFILE_STATUS_LEN: int = 200
const ALLOWED_PROFILE_ANIMATIONS: PackedStringArray = ["idle", "run", "death"]
## Hard cap on how many achievement chips show on the profile trophy strip.
const MAX_DISPLAYED_TROPHIES: int = 3

const BASE_STATS: Dictionary[StringName, float] = {
	Stat.HEALTH_MAX: 50.0,
	# Low innate attack power on purpose: most of your damage comes from your
	# weapon's AD + the Strength attribute, so leveling and gear both matter and
	# a fresh level-1 is meant to feel weak. See AttributeMap / the weapon items.
	# (Was 10 — with a +4 wood sword that printed 14s on 0-armor goblins at L1.)
	Stat.AD: 3.0,
	Stat.ARMOR: 15.0,
	Stat.MR: 15.0,
	# Mana gates SPECIAL abilities only (mana_cost on the AbilityResource);
	# basic attacks stay free. Regen lives in Player (server tick). Spirit
	# grows the pool.
	Stat.MANA_MAX: 50.0,
	Stat.MANA_REGEN: 0.5,
	Stat.MOVE_SPEED: 112.5,
	Stat.ATTACK_SPEED: 0.8
}

## Free max HP per level past 1 — the PvP durability floor: levels buy baseline,
## attributes buy specialization, so no build can opt into being one-tapped
## (docs/pvp_balance.md). Composed into spawn stats (instance_server) and applied
## live on level-up (level_gained signal).
##
## Was 5.0 across the old 1–20 ladder (95 free HP at cap). The ladder is now 1–126
## (mastery-derived), so this is scaled to hold that TOTAL roughly flat — 0.76 ×
## 125 ≈ 95 — rather than handing out 6× the free health. Retune this if you want
## max-level characters tankier; it is the single dial for it.
const HEALTH_PER_LEVEL: float = 0.76

@export var player_id: int
@export var account_name: String

@export var display_name: String = "Player"
@export var skin_id: int = 1 # Default skin

@export var inventory: Dictionary
## Personal bank vault (same slot format as inventory). Unlimited capacity —
## stored separately so bag UI stay compact while long-term storage grows.
@export var bank: Dictionary
## Chest-open staging: Array of { "id": item_id, "a": amount }. Items land here
## instead of the bag until the player claims them (Take / Bank). Flushed to the
## bank on logout. See PendingChestLoot.
@export var pending_chest_loot: Array = []
## Equipped gear: gear-slot key (&"weapon", &"torso", ...) -> item_id. Equipped items
## live here, NOT in inventory (they're moved out on equip, back on unequip).
@export var equipment: Dictionary

@export var attributes: Dictionary[StringName, int]
@export var available_attributes_points: int

@export var level: int = 1
## Character experience toward the next level (resets to the overflow on level-up).
@export var experience: int

## Profession skills: skill_name (&"mining", &"woodcutting", ...) -> {"level": int, "xp": int}.
## Generalizes to any gathering/crafting profession; persisted as JSON.
@export var skills: Dictionary

## Weapon mastery: category (&"wand", ...) -> {"level": int, "xp": int, "spent": Dictionary}.
## "spent" holds the bought mastery-tree node ids (node_id (String) -> true).
## Persisted as JSON (mastery_json column) together with ability_loadout.
@export var masteries: Dictionary

## Chosen special abilities per weapon category: category (String) -> Array of
## mastery node ids (String), in slot order. The server mounts the matching
## abilities into the weapon's special slots (Q, then E) when a weapon of that
## category is wielded, greedily within its weight capacity (MasteryService).
@export var ability_loadout: Dictionary

## Quests: quest_id (int) -> {"state": StringName, "progress": Dictionary(obj_index:int -> count:int)}.
## state is &"active" or &"turned_in". COLLECT objectives are derived from inventory live,
## so only KILL/CRAFT counts live in "progress". Persisted as JSON.
@export var quests: Dictionary

## The guild currently selected as the player's active guild.
@export var active_guild_id: int
## All guilds the player is a member of.
## A player may belong to multiple guilds, but only one can be active at a time.
@export var joined_guild_ids: PackedInt64Array
## The guild in which the player holds the leader role.
@export var led_guild_id: int

@export var server_roles: Dictionary

@export var friends: PackedInt64Array

## Per-player block list. When X has Y in here, the server suppresses every
## chat message Y produces (DM / world / guild / overhead bubbles) from
## reaching X's client. Asymmetric — Y never knows. Mirrors how friends is
## persisted (JSON column on the players row, see world_store_sqlite.gd).
@export var blocked_ids: PackedInt64Array

## Skins this character has purchased and may switch between (skin ids from the `sprites`
## registry). The currently EQUIPPED one is [member skin_id]; this is everything owned. The
## creation skin is seeded on character creation and backfilled on load, so the equipped
## skin is always in here. Persisted as owned_skins_json (mirrors [member friends]).
@export var owned_skins: PackedInt64Array

## Leaderboard counters with rolling day/week buckets. Keys:
## pvp_kills_day/week/total, pve_kills_day/week/total, lb_bucket_day_ms, lb_bucket_week_ms.
## Owned and rolled over by LeaderboardService.
@export var lb_stats: Dictionary

## Vanity titles ever earned by this character. Quest turn-ins can add to this
## list via QuestResource.grant_title. Player chooses which one is displayed via
## display_title.
@export var titles_unlocked: PackedStringArray
## Currently active title (shown on profile under display_name). Empty = no
## title displayed. Auto-set to a newly-granted title only if no title is
## currently active — so players don't lose their chosen banner.
@export var display_title: String
## Earned wardstones — the biome-progression keys (docs/wardstones.md). Slugs
## like "woodland"; granted the moment a biome's finale-quest climax completes,
## checked by InstanceResource.can_join_instance. Character-wide by design.
@export var wardstones: PackedStringArray
## Up to 3 trophies the player pins to their profile's right-side chip strip.
## Each entry must also be in titles_unlocked. Separate from display_title (the
## one shown under their name) — these are the "achievement flex" picks.
@export var displayed_trophies: PackedStringArray

## Daily quest board state: the 3 rolled quests for today and when they expire.
## Each entry is a Dictionary {template_id, count_so_far, claimed}.
## dailies_refresh_at_ms is the unix-ms of the next UTC midnight;
## DailyQuestService rerolls when now crosses it. Empty array = never rolled
## (first board click generates).
@export var daily_quests: Array
@export var dailies_refresh_at_ms: int

## Slayer: the currently assigned task, or {} for none. Shape:
## {"task": String (SlayerTaskDef slug), "master": String (SlayerMasterResource
## slug), "remaining": int, "assigned_amount": int}. See SlayerTaskService.
@export var current_slayer_task: Dictionary = {}
## Account-wide Slayer reward points. Spent on skips (paid masters), blocks, and
## eventually the Slayer Shop — never an inventory item, same reasoning as
## lb_stats: it can't be traded, dropped, or duped.
@export var slayer_points: int = 0
## Consecutive tasks completed WITHOUT a Turael-style free reassignment breaking
## the chain. Drives the OSRS streak-milestone point bonus (SlayerTaskService).
@export var slayer_streak: int = 0
## Lifetime completed-task counter. Unlike slayer_streak this never resets — kept
## for a future "Slayer log" / milestone titles, same role lb_stats' *_total
## counters play for combat.
@export var slayer_tasks_completed: int = 0
## task_id (SlayerTaskDef slug) -> true. Permanently blocked tasks (never
## assigned). Reserved for the Slayer Shop; empty until that ships.
@export var slayer_blocked_tasks: Dictionary = {}

## Soft dungeon charge state lives in dungeon_lockouts under "_daily_charges":
## {day, used, bonus}. Successful clears spend a charge; failed runs do not.
## Bonus comes from Dungeon Keys. Older per-dungeon unix timestamps may still
## linger harmlessly. Persisted as dungeon_lockouts_json.
@export var dungeon_lockouts: Dictionary = {}

## Redeem codes this character has already claimed (upper-cased code strings).
## Per-character by design — see docs/redeem_codes.md. Persisted as
## redeemed_codes_json. Stops re-claiming the same code on this character.
@export var redeemed_codes: PackedStringArray

# Profile
@export var profile_status: String = "Hello I'am new!"
@export var profile_animation: String = "idle"

@export var last_position: Vector2 = Vector2.ZERO
@export var current_instance: String

## Fired once per level gained (see level_up). The live server Player listens and
## applies the per-level grants (HEALTH_PER_LEVEL) — one hook instead of touching
## every add_experience call site (kills, quests, dailies, /xp, redeems).
## (Named level_gained, not leveled_up — add_skill_xp/add_mastery_xp already use
## leveled_up as a local, and the signal would be shadowed.)
signal level_gained

## Current Network ID
var current_peer_id: int

## Server-side runtime stamp of when the current session began (Time.get_ticks_msec).
## Set on auth, consumed at disconnect to bump lb_stats["played_seconds"]. Not
## persisted — each session starts fresh.
var session_start_ms: int = 0

## True while the player is in a sparring match. Bypasses the zone PvP check
## in projectile/melee damage. Server-side runtime only — not persisted; if a
## player disconnects mid-match, SparringService ends the match cleanly so
## this never lingers across sessions.
var in_match: bool = false

var stats: Dictionary

## Live timed stat buffs ({stat, amount, expires_ms} — see BuffService). Runtime
## only on purpose: survives instance changes within a session, gone on logout.
var active_buffs: Array[Dictionary] = []

## Mastery passive modifiers currently applied to live stats ({stat, value}).
## Runtime only — rebuilt by MasteryService.refresh on spawn and weapon swaps.
var applied_mastery_passives: Array[Dictionary] = []

## Per-node gather cooldowns (node_id -> next-ready time in ms). Runtime only, not persisted.
var gather_cooldowns: Dictionary

## Character story/progress flags (flag StringName -> true) — the slot quest
## prerequisites (QuestResource.requires_flag) and the v1 wardstone key-gate
## read. RUNTIME-ONLY for now: nothing sets flags yet; when the wardstone
## system ships, persist via a new _migration_vN JSON column (mirrors friends).
var character_flags: Dictionary


func has_character_flag(flag: StringName) -> bool:
	return character_flags.get(flag, false)


func set_character_flag(flag: StringName) -> void:
	character_flags[flag] = true


func init(
	_player_id: int,
	_account_name: String,
	_display_name: String = display_name,
	_skin_id: int = skin_id
) -> void:
	player_id = _player_id
	account_name = _account_name
	display_name = _display_name
	skin_id = _skin_id


## LEGACY manual level bump — kept for the /setlevel admin command only. Normal
## progression goes through [method sync_combat_level], which derives the level
## from masteries and banks the matching attribute points.
func level_up() -> void:
	available_attributes_points += attribute_points_at_level(level + 1) - attribute_points_at_level(level)
	level += 1
	level_gained.emit()


## LEGACY character-xp curve. [member level] is no longer earned this way — it is
## DERIVED from mastery/Slayer levels (see [method derived_combat_level]). This
## constant and [member experience] survive only so the lifetime "adventure xp"
## counter, its save column, and the progression UI keep working unchanged.
const LEVEL_XP_BASE: int = 70


func level_xp_to_next() -> int:
	return LEVEL_XP_BASE * maxi(1, level)


# ---------------------------------------------------------------------------
# Combat level — derived from masteries, OSRS-style
# ---------------------------------------------------------------------------

## The five weapon masteries that define a character's combat level: Swordsmanship,
## Heavy Weapons, Archery, Battlemage and Arcanist. These and ONLY these — Slayer is
## a support skill and does not contribute, nor do the gathering/crafting jobs.
const COMBAT_STYLE_CATEGORIES: Array[StringName] = [&"sword", &"hammer", &"bow", &"wand", &"book"]

## Combat level with all five masteries at 99. 126 is OSRS's cap, kept deliberately:
## it reads as a combat level to anyone who has played OSRS, and the weights below
## land on it exactly rather than by fudge.
const COMBAT_LEVEL_CAP: int = 126

## 7/11 each, applied to (best mastery + mean of all five): 198 × 7/11 = 126 exactly,
## and a fresh character (1 + 1) floors to 1.
const COMBAT_LEVEL_NUMERATOR: int = 7
const COMBAT_LEVEL_DENOMINATOR: int = 11


## Character/combat level implied by the five weapon masteries:
##   floor( (best mastery + mean of all five) × 7/11 ), clamped to 1..126
##
## Mirrors OSRS's SHAPE — a "best offensive style" term plus a broad term covering
## everything you've trained — using the skills Arkenelle actually has. The two
## halves pull in different directions on purpose:
##   - the BEST term means specialising is always rewarded, and a specialist is
##     never stuck at the bottom (99 in one weapon alone = level 76)
##   - the MEAN term means the 126 cap is reserved for a character who has trained
##     all five, so combat level still says something breadth-wise
## Slayer is deliberately absent: it is earned through the same kills that already
## feed these masteries, so counting it would double-count the same activity.
func derived_combat_level() -> int:
	var best_style: int = 1
	var total: int = 0
	for category: StringName in COMBAT_STYLE_CATEGORIES:
		var mastery_level: int = int(get_mastery(category).get("level", 1))
		best_style = maxi(best_style, mastery_level)
		total += mastery_level
	var mean_style: int = total / COMBAT_STYLE_CATEGORIES.size()
	var raw: int = (best_style + mean_style) * COMBAT_LEVEL_NUMERATOR / COMBAT_LEVEL_DENOMINATOR
	return clampi(raw, 1, COMBAT_LEVEL_CAP)


## Attribute points a character has earned by reaching [param char_level] — one
## per two combat levels. Over the 1→126 range that is 62 points, holding the
## old 1→20 × 3/level budget (57) roughly flat: this change was about how the
## level is DERIVED, not about handing out 6× the attribute points.
static func attribute_points_at_level(char_level: int) -> int:
	return maxi(0, char_level - 1) / 2


## Recomputes [member level] from the five weapon masteries and banks any attribute
## points the climb earned. Call after any mastery XP gain. Returns the number of
## levels gained (0 = nothing changed) so callers can report it, and fires
## [signal level_gained] once per level so the live Player applies its per-level
## grants exactly as it did under the old XP path.
##
## Only ever moves UP: masteries can't drop, and a cap/weight retune must never
## claw back attribute points a player has already spent.
func sync_combat_level() -> int:
	var target: int = derived_combat_level()
	if target <= level:
		return 0
	var gained: int = target - level
	available_attributes_points += attribute_points_at_level(target) - attribute_points_at_level(level)
	level = target
	for _i: int in gained:
		level_gained.emit()
	return gained


## Banks lifetime "adventure" experience (quest + daily + redeem + kill rewards).
##
## This NO LONGER LEVELS THE CHARACTER — [member level] is derived from mastery and
## Slayer levels via [method sync_combat_level]. The counter and its save column are
## kept so nothing that reads `experience` breaks, and levels_gained/points_gained
## are always 0 so existing callers report honestly instead of claiming phantom
## level-ups. Quest `reward_xp` therefore no longer advances the character —
## see the note in docs on giving those rewards a skill destination.
# --- Quests ---

func quest_state(quest_id: int) -> StringName:
	return (quests.get(quest_id, {}) as Dictionary).get("state", &"")


func accept_quest(quest_id: int) -> void:
	if not quests.has(quest_id):
		quests[quest_id] = {"state": &"active", "progress": {}}


func quest_progress(quest_id: int, objective_index: int) -> int:
	var entry: Dictionary = quests.get(quest_id, {})
	return int((entry.get("progress", {}) as Dictionary).get(objective_index, 0))


## Increments a KILL/CRAFT objective's counter (only while the quest is active).
func advance_quest(quest_id: int, objective_index: int, amount: int = 1) -> void:
	var entry: Dictionary = quests.get(quest_id, {})
	if entry.get("state", &"") != &"active":
		return
	var progress: Dictionary = entry["progress"]
	progress[objective_index] = int(progress.get(objective_index, 0)) + amount


func set_quest_turned_in(quest_id: int) -> void:
	if quests.has(quest_id):
		quests[quest_id]["state"] = &"turned_in"


## Whether the "ready to turn in" nudge has been pushed for this quest, so a
## passive (COLLECT/inventory) completion toasts exactly once instead of on every
## tracker refresh. Persisted inside the quests blob; defaults false.
func quest_ready_notified(quest_id: int) -> bool:
	return bool((quests.get(quest_id, {}) as Dictionary).get("ready_notified", false))


func set_quest_ready_notified(quest_id: int, value: bool) -> void:
	if quests.has(quest_id):
		quests[quest_id]["ready_notified"] = value


func add_experience(amount: int) -> Dictionary:
	if amount <= 0:
		return {"level": level, "experience": experience, "levels_gained": 0, "points_gained": 0}
	experience += amount
	return {
		"level": level,
		"experience": experience,
		"levels_gained": 0,
		"points_gained": 0,
	}


## Returns the {"level", "xp", "perks"} entry for a skill, creating it at level 1 if
## missing. Also backfills "perks" on entries loaded from older saves.
func get_skill(skill_name: StringName) -> Dictionary:
	if not skills.has(skill_name):
		skills[skill_name] = {"level": 1, "xp": 0, "perks": {}}
	var skill: Dictionary = skills[skill_name]
	if not skill.has("perks"):
		skill["perks"] = {}
	# Clamp legacy saves that overshot the OSRS 99 cap under the old linear curve.
	if int(skill.get("level", 1)) > SkillXp.LEVEL_CAP:
		skill["level"] = SkillXp.LEVEL_CAP
		skill["xp"] = 0
	return skill


## XP needed to advance from [param skill_level] → next. 0 at/above the 99 cap.
func skill_xp_to_next(skill_level: int) -> int:
	return SkillXp.xp_to_next(skill_level)


## Adds xp to a profession skill, applying any level-ups. Caps at SkillXp.LEVEL_CAP
## (99 / 13,034,431 total XP). Returns {"level", "xp", "leveled_up"}.
func add_skill_xp(skill_name: StringName, amount: int) -> Dictionary:
	var skill: Dictionary = get_skill(skill_name)
	var level: int = int(skill["level"])
	if level >= SkillXp.LEVEL_CAP or amount <= 0:
		skill["xp"] = 0
		return {"level": level, "xp": 0, "leveled_up": false}

	skill["xp"] = int(skill["xp"]) + amount
	var leveled_up: bool = false
	while level < SkillXp.LEVEL_CAP:
		var need: int = skill_xp_to_next(level)
		if need <= 0 or int(skill["xp"]) < need:
			break
		skill["xp"] = int(skill["xp"]) - need
		level += 1
		leveled_up = true
	skill["level"] = level
	if level >= SkillXp.LEVEL_CAP:
		skill["xp"] = 0
	# NOTE no combat-level resync here: character level comes from the five weapon
	# masteries only (see COMBAT_STYLE_CATEGORIES). Slayer and the gathering jobs
	# all flow through this function and none of them move it.
	return {"level": level, "xp": int(skill["xp"]), "leveled_up": leveled_up}


## Max mastery level per weapon category. Same 1–99 OSRS XP curve as profession
## skills ([SkillXp]) so new armor/weapons can keep gating upward without a
## hard mid-game ceiling. Combined with MasteryService LEVELS_PER_POINT (3)
## this sets the point budget — one subclass column, not a full tree.
const MASTERY_LEVEL_CAP: int = SkillXp.LEVEL_CAP


## Returns the {"level", "xp", "spent"} entry for a weapon category, creating
## it at level 1 (0 spendable points until level 3) if missing.
func get_mastery(category: StringName) -> Dictionary:
	var key := StringName(String(category))
	if not masteries.has(key):
		# JSON / mixed String vs StringName keys can leave a sibling entry —
		# adopt it under the canonical StringName key before creating a stub.
		for existing: Variant in masteries.keys():
			if String(existing) == String(key):
				var adopted: Dictionary = masteries[existing]
				masteries.erase(existing)
				masteries[key] = adopted
				# Clamp legacy saves that overshot under an older lower cap.
				if int(adopted.get("level", 1)) > MASTERY_LEVEL_CAP:
					adopted["level"] = MASTERY_LEVEL_CAP
					adopted["xp"] = 0
				return adopted
		masteries[key] = {"level": 1, "xp": 0, "spent": {}}
		return masteries[key]
	var entry: Dictionary = masteries[key]
	if int(entry.get("level", 1)) > MASTERY_LEVEL_CAP:
		entry["level"] = MASTERY_LEVEL_CAP
		entry["xp"] = 0
	return entry


## Read-only mastery level for gates. Does not create entries. Every category
## floors at 1 — masteries run on the same 1–99 curve as skills, so "never
## practiced" is level 1, not level 0 (a level 0 read displayed as an unmet
## "Requires Lv 1" gate on gear the player could actually wear). Use
## [member masteries].has() when you need to know whether a category was ever
## practiced; don't infer it from this returning 0, because it no longer does.
func mastery_level_of(category: StringName) -> int:
	for existing: Variant in masteries.keys():
		if String(existing) == String(category):
			return clampi(int((masteries[existing] as Dictionary).get("level", 1)), 1, MASTERY_LEVEL_CAP)
	return 1


## XP needed to advance from [param mastery_level] → next. Same table as skills.
func mastery_xp_to_next(mastery_level: int) -> int:
	return SkillXp.xp_to_next(mastery_level)


## Adds weapon-mastery xp to a category, applying level-ups (frozen at the
## 99 / 13,034,431 total-XP skill cap). Returns {"category", "level", "xp",
## "xp_to_next", "leveled_up", "started"} so the kill-reward push can report
## progress to the client — "started" marks the very first practice (entry
## creation at level 1), which deserves its own toast even though no level-UP
## happened.
func add_mastery_xp(category: StringName, amount: int) -> Dictionary:
	var started: bool = not masteries.has(category)
	var entry: Dictionary = get_mastery(category)
	var level: int = int(entry["level"])
	var leveled_up: bool = false
	if level >= MASTERY_LEVEL_CAP or amount <= 0:
		entry["xp"] = 0
		return {
			"category": String(category),
			"level": level,
			"xp": 0,
			"xp_to_next": 0,
			"leveled_up": false,
			"started": started,
		}

	entry["xp"] = int(entry["xp"]) + amount
	while level < MASTERY_LEVEL_CAP:
		var need: int = mastery_xp_to_next(level)
		if need <= 0 or int(entry["xp"]) < need:
			break
		entry["xp"] = int(entry["xp"]) - need
		level += 1
		leveled_up = true
	entry["level"] = level
	if level >= MASTERY_LEVEL_CAP:
		entry["xp"] = 0
	# Character level is derived from these — resync here rather than at each call
	# site so no future mastery-XP source can silently skip it.
	var combat_levels_gained: int = 0
	if leveled_up:
		combat_levels_gained = sync_combat_level()
	return {
		"category": String(category),
		"level": level,
		"xp": int(entry["xp"]),
		"xp_to_next": mastery_xp_to_next(level),
		"leveled_up": leveled_up,
		"started": started,
		"combat_levels_gained": combat_levels_gained,
		"combat_level": self.level,
	}
