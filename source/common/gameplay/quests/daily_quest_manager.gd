extends Node
## Skilling-only daily board. Autoload (`DailyQuestManager`).
##
## Every 24h (00:00 UTC) each player is offered THREE distinct skills out of the
## nine in [constant SKILLS]. Each slot is offered at three difficulties; the
## player picks one per slot, which stamps a target and starts counting. Progress
## comes from [SkillingEvents], never from an inventory snapshot.
##
## No `class_name`: Godot refuses an autoload whose singleton name collides with
## a global class name, and every autoload in this project follows the same bare
## `extends` convention (client_state.gd, loot_feed.gd). Note the consequence —
## the `DailyQuestManager` identifier only resolves in a run that instantiates
## autoloads, so headless `-s` tools must load this script and `.new()` it
## instead (see tools/verify_progression_pass.gd `_board`). [SkillingEvents] is a
## `class_name` precisely to avoid that limitation on the emitter side.
##
## THIS AUTOLOAD HOLDS NO PER-PLAYER STATE.
## One world process serves many players. An autoload that cached "the" board
## would serve whoever touched it last, and every read after a second player
## logged in would be wrong. All state lives on [PlayerResource] — which is
## already persisted, already per-player, and already server-only — and this node
## owns exactly three things: the skill roster, the deterministic roll, and the
## signal wiring. [method get_board] rebuilds task objects from that state on
## demand; they are values, not cached handles, so a mutation is only real once
## it goes back through [method _store].
##
## DESYNC / RELOG SAFETY
## The daily OFFER is a pure function of (player_id, UTC day) — see
## [method _skills_for]. Nothing about an unaccepted board is persisted, and it
## cannot be rerolled by relogging, crashing, or a failed save: the same three
## skills and the same three candidate quantities regenerate every time. Only an
## ACCEPTED slot writes state (difficulty, target, progress, claimed), and it
## rides inside the existing `dailies_json` blob, so this overhaul ships without
## a database migration.

## The nine skilling jobs the board draws from. These are [JobRegistry] SLUGS,
## not display names — &"outfitting" is shown as "Crafting" and &"harvesting" as
## "Farming". Matching on the label instead of the slug produces a task that no
## XP grant ever advances, so the roster is validated against JobRegistry on boot.
const SKILLS: Array[StringName] = [
	&"mining",
	&"smithing",
	&"fishing",
	&"cooking",
	&"outfitting",   # displayed as "Crafting"
	&"woodcutting",
	&"fletching",
	&"harvesting",   # displayed as "Farming"
	&"herblore",
]

## Slots offered per day. Must not exceed SKILLS.size() — the three skills are
## drawn WITHOUT replacement.
const TASK_COUNT: int = 3

const REWARD_TABLE_PATH: String = "res://source/common/gameplay/quests/resources/daily_rewards.tres"

const DAY_MS: int = 24 * 60 * 60 * 1000

## Paid once, on the claim that finishes all three. The skill-XP half is paid
## into each of the day's three assigned skills, which is the whole point of a
## skilling board — the bonus should move the skills you actually worked.
const BONUS_GOLD: int = 3_000
const BONUS_ADVENTURE_XP: int = 250
const BONUS_SKILL_XP_EACH: int = 2_500

# --- UI-facing signals -------------------------------------------------------
# Server-side listeners; the client HUD hangs off the `daily.progress` network
# push, not these. Every one carries the player for the same reason
# SkillingEvents does — one process, many players.

## A new day's board was generated for this player.
signal board_rolled(player_res: PlayerResource, day_index: int)
## A slot's difficulty was chosen and the task started.
signal task_accepted(player_res: PlayerResource, task: DailyTaskResource)
## A slot's counter moved. Fires only when progress ACTUALLY changed.
signal task_progressed(player_res: PlayerResource, task: DailyTaskResource)
## A slot reached its target. Fires once, on the action that completed it.
signal task_completed(player_res: PlayerResource, task: DailyTaskResource)
## A completed slot's reward was claimed.
signal task_claimed(player_res: PlayerResource, task: DailyTaskResource)

static var _table_cache: DailyRewardTable


func _ready() -> void:
	# One subscription, to the fanned-in stream rather than the per-kind signals,
	# so a gathering/production path added later is tracked without touching this
	# file. See SkillingEvents.skill_action.
	SkillingEvents.bus().skill_action.connect(_on_skill_action)
	_validate_roster()


## Fail loudly at boot if the roster names a job that does not exist. The
## alternative is a slot that is offered, accepted, and then never advances — a
## bug that only surfaces as a player complaint a day later.
func _validate_roster() -> void:
	for slug: StringName in SKILLS:
		if not JobRegistry.has_job(slug):
			push_error("DailyQuestManager: '%s' is not a registered job; the board would offer a task that can never progress." % slug)
	if TASK_COUNT > SKILLS.size():
		push_error("DailyQuestManager: TASK_COUNT (%d) exceeds the skill roster (%d) — slots are drawn without replacement." % [TASK_COUNT, SKILLS.size()])


# --- Board -------------------------------------------------------------------

## The player's three slots for today: stored state where a difficulty has been
## chosen, freshly-derived OFFERED slots everywhere else. Also stamps the next
## reset time and drops entries left over from a previous day.
##
## Returns fresh objects every call — mutate them, then hand them to
## [method _store]. They are not live handles onto player state.
func get_board(player_res: PlayerResource) -> Array[DailyTaskResource]:
	var out: Array[DailyTaskResource] = []
	if player_res == null:
		return out

	var now_ms: int = _now_ms()
	var day: int = _day_index(now_ms)
	var stored: Dictionary[int, DailyTaskResource] = _stored_by_slot(player_res, day)

	# Keep the countdown fresh whether or not anything was accepted. A player who
	# never opens the board still needs a correct "resets in" on their first look.
	var reset_at: int = (day + 1) * DAY_MS
	if player_res.dailies_refresh_at_ms != reset_at:
		player_res.dailies_refresh_at_ms = reset_at
		board_rolled.emit(player_res, day)

	var skills: Array[StringName] = _skills_for(player_res.player_id, day)
	var table: DailyRewardTable = _load_table()
	for slot: int in TASK_COUNT:
		# An accepted slot wins over the derived roster. If SKILLS is reordered or
		# retuned in a patch that ships mid-day, a task someone already started must
		# not mutate underneath them.
		if stored.has(slot):
			out.append(stored[slot])
			continue
		var task := DailyTaskResource.new()
		task.slot = slot
		task.skill = skills[slot] if slot < skills.size() else SKILLS[0]
		task.day_index = day
		task.reward_table = table
		out.append(task)
	return out


## Difficulty options for an un-accepted slot: the exact quantity the player will
## be held to if they pick that difficulty, plus what it pays. Deterministic, so
## the numbers on the card cannot be rerolled by closing and reopening the board.
func difficulty_options(player_res: PlayerResource, slot: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if player_res == null or slot < 0 or slot >= TASK_COUNT:
		return out
	var day: int = _day_index(_now_ms())
	var table: DailyRewardTable = _load_table()
	var skill: StringName = _skill_for_slot(player_res, slot, day)
	var skill_level: int = _skill_level(player_res, skill)
	for difficulty: int in [
		DailyTaskResource.Difficulty.EASY,
		DailyTaskResource.Difficulty.MEDIUM,
		DailyTaskResource.Difficulty.HARD,
	]:
		var target: int = DailyTaskResource.roll_target(
			difficulty, _rng(player_res.player_id, day, slot, difficulty)
		)
		out.append({
			"difficulty": difficulty,
			"name": DailyTaskResource.difficulty_name(difficulty),
			"target": target,
			"reward_gold": table.gold_for(difficulty) if table != null else 0,
			"reward_xp": table.adventure_xp_for(difficulty) if table != null else 0,
			"reward_skill_xp": table.skill_xp_for(difficulty, skill_level) if table != null else 0,
			# Chest the difficulty pays out, so the picker can show what it buys.
			# Sourced from the rewarder rather than restated here — the board must
			# not become a second place that knows what a T3 chest is.
			"chest_tier": difficulty + 1,
			"chest_name": str(SkillingChestRewarder.TIERS[difficulty]["name"]),
			"outfit_chance": SkillingChestRewarder.outfit_chance(difficulty),
		})
	return out


## Pick a difficulty for [param slot] and start the task. Choosing the difficulty
## IS accepting: the target is stamped here and is final. Letting a player
## re-pick later would let them ride a Hard counter to 290/300 and then drop to
## Easy for an instant claim.
func accept(player_res: PlayerResource, slot: int, difficulty: int) -> Dictionary:
	if player_res == null:
		return {"ok": false, "reason": "no_player"}
	if slot < 0 or slot >= TASK_COUNT:
		return {"ok": false, "reason": "bad_slot"}
	if difficulty < DailyTaskResource.Difficulty.EASY or difficulty > DailyTaskResource.Difficulty.HARD:
		return {"ok": false, "reason": "bad_difficulty"}

	var board: Array[DailyTaskResource] = get_board(player_res)
	var task: DailyTaskResource = board[slot]
	if task.accepted:
		return {"ok": false, "reason": "already_accepted"}

	var day: int = _day_index(_now_ms())
	task.difficulty = difficulty as DailyTaskResource.Difficulty
	task.target_amount = DailyTaskResource.roll_target(
		difficulty, _rng(player_res.player_id, day, slot, difficulty)
	)
	task.progress = 0
	task.day_index = day
	task.accepted = true
	task.claimed = false
	_store(player_res, board)
	task_accepted.emit(player_res, task)
	return {
		"ok": true,
		"slot": slot,
		"skill": String(task.skill),
		"difficulty": int(task.difficulty),
		"target": task.target_amount,
	}


# --- Progress ----------------------------------------------------------------

## [SkillingEvents] listener. Advances every accepted, unfinished slot matching
## the skill, persists, then pushes the board so an open UI updates live.
func _on_skill_action(
	player_res: PlayerResource, skill: StringName, item_id: int, amount: int
) -> void:
	if player_res == null or amount <= 0:
		return
	var board: Array[DailyTaskResource] = get_board(player_res)
	var advanced: Array[DailyTaskResource] = []
	var finished: Array[DailyTaskResource] = []
	for task: DailyTaskResource in board:
		if not task.matches(skill, item_id):
			continue
		# advance() returns what was actually applied, so a task already at its
		# target contributes nothing and cannot trigger a pointless network push.
		if task.advance(amount) <= 0:
			continue
		advanced.append(task)
		if task.is_complete():
			finished.append(task)

	if advanced.is_empty():
		return
	# Persist BEFORE announcing. If a listener throws, the progress the player
	# earned is already committed rather than lost with the frame.
	_store(player_res, board)
	for task: DailyTaskResource in advanced:
		task_progressed.emit(player_res, task)
	for task: DailyTaskResource in finished:
		task_completed.emit(player_res, task)
	push_board(player_res)


# --- Claim -------------------------------------------------------------------

## Claim one COMPLETE slot. Marks it claimed and returns the payout for the
## caller to grant; this method deliberately grants nothing itself, so every
## currency/XP mutation stays in the request handler alongside the reward push.
##
## The claim that finishes all three folds in the completion bonus. A claimed
## slot can never be re-claimed, so that transition happens exactly once a day
## with no extra flag to persist.
func claim(player_res: PlayerResource, slot: int) -> Dictionary:
	if player_res == null:
		return {"ok": false, "reason": "no_player"}
	if slot < 0 or slot >= TASK_COUNT:
		return {"ok": false, "reason": "bad_slot"}
	var board: Array[DailyTaskResource] = get_board(player_res)
	var task: DailyTaskResource = board[slot]
	if not task.accepted:
		return {"ok": false, "reason": "not_accepted"}
	if task.claimed:
		return {"ok": false, "reason": "already_claimed"}
	if not task.is_complete():
		return {"ok": false, "reason": "incomplete"}

	var table: DailyRewardTable = _load_table()
	if table == null:
		return {"ok": false, "reason": "no_reward_table"}

	task.claimed = true
	_store(player_res, board)

	var skill_xp: Array[Dictionary] = [{
		"skill": String(task.skill),
		"xp": table.skill_xp_for(task.difficulty, _skill_level(player_res, task.skill)),
	}]
	var result: Dictionary = {
		"ok": true,
		"slot": slot,
		"skill": String(task.skill),
		"difficulty": int(task.difficulty),
		"gold": table.gold_for(task.difficulty),
		"adventure_xp": table.adventure_xp_for(task.difficulty),
		"skill_xp": skill_xp,
		"all_claimed": false,
	}
	if _all_claimed(board):
		result["all_claimed"] = true
		result["gold"] = int(result["gold"]) + BONUS_GOLD
		result["adventure_xp"] = int(result["adventure_xp"]) + BONUS_ADVENTURE_XP
		# Bonus skill XP into each of the day's three skills. This adds a SECOND
		# entry for the skill just claimed; the handler sums per skill, so that is
		# a bonus on top rather than a lost grant.
		for other: DailyTaskResource in board:
			skill_xp.append({"skill": String(other.skill), "xp": BONUS_SKILL_XP_EACH})
	task_claimed.emit(player_res, task)
	return result


# --- Client payload ----------------------------------------------------------

## Full board state for the client: `quest.board.info` returns it and the live
## `daily.progress` push carries it.
func build_board_payload(player_res: PlayerResource) -> Dictionary:
	if player_res == null:
		return {"ok": false, "reason": "no_player"}
	var board: Array[DailyTaskResource] = get_board(player_res)
	var table: DailyRewardTable = _load_table()
	var entries: Array[Dictionary] = []
	for task: DailyTaskResource in board:
		var level: int = _skill_level(player_res, task.skill)
		var entry: Dictionary = {
			"slot": task.slot,
			"skill": String(task.skill),
			"skill_name": JobRegistry.display_name(task.skill),
			"skill_level": level,
			"state": int(task.state()),
			"accepted": task.accepted,
			"claimed": task.claimed,
			"description": task.describe(),
			# The unit the counter is in ("logs cut"), so the client renders
			# "145 / 300 logs cut" without inventing the wording itself.
			"progress_noun": task.progress_noun(),
			"progress": task.progress,
			"required": task.target_amount,
			"complete": task.is_complete(),
		}
		if task.accepted:
			entry["difficulty"] = int(task.difficulty)
			entry["difficulty_name"] = DailyTaskResource.difficulty_name(task.difficulty)
			entry["chest_tier"] = int(task.difficulty) + 1
			entry["chest_name"] = str(SkillingChestRewarder.TIERS[int(task.difficulty)]["name"])
			entry["outfit_chance"] = SkillingChestRewarder.outfit_chance(int(task.difficulty))
			entry["reward_gold"] = table.gold_for(task.difficulty) if table != null else 0
			entry["reward_xp"] = table.adventure_xp_for(task.difficulty) if table != null else 0
			entry["reward_skill_xp"] = (
				table.skill_xp_for(task.difficulty, level) if table != null else 0
			)
		else:
			# Un-accepted slots ship the three choices so the card can render the
			# real target and payout for each before the player commits.
			entry["options"] = difficulty_options(player_res, task.slot)
		entries.append(entry)
	# Dungeon charges ride along on the daily board rather than on `dungeon.info`.
	# They ARE daily state and they reset on the same 00:00 UTC boundary, but
	# `dungeon.info` is station-gated (you must be stood at a dungeon keeper), so
	# it cannot answer a Character-menu panel. Carrying them here also means the
	# live `daily.progress` push keeps them current for free.
	var charges: Dictionary = DungeonService.charge_status(player_res)
	return {
		"ok": true,
		"entries": entries,
		"refresh_at_ms": player_res.dailies_refresh_at_ms,
		"dungeon_charges": charges,
		"all_claimed": _all_claimed(board),
		"bonus_gold": BONUS_GOLD,
		"bonus_xp": BONUS_ADVENTURE_XP,
		"bonus_skill_xp": BONUS_SKILL_XP_EACH,
	}


## Push the board to this player's client. No-op off-server or for an offline
## player, so gameplay code can call it without knowing which it is.
func push_board(player_res: PlayerResource) -> void:
	if WorldServer.curr == null or player_res == null:
		return
	var peer: int = int(player_res.current_peer_id)
	if peer <= 0:
		return
	WorldServer.curr.data_push.rpc_id(peer, &"daily.progress", build_board_payload(player_res))


# --- Persistence -------------------------------------------------------------

## Canonical save shape for the daily board. The sqlite store writes this under
## `dailies_json`; keeping the shape here rather than inline in the store means
## the reader and the writer cannot drift apart.
func save_state(player_res: PlayerResource) -> Dictionary:
	if player_res == null:
		return {}
	return {
		"quests": player_res.daily_quests,
		"refresh_at_ms": player_res.dailies_refresh_at_ms,
	}


## Restore from [method save_state]. Tolerates every legacy and malformed shape
## it can: a missing blob, the pre-overhaul kill/collect entries (dropped — they
## carry no skill), JSON ints that came back as floats, duplicate slots, and
## entries from a day that has already rolled over. A player must never lose a
## session because one field of one row parsed badly.
func load_state(player_res: PlayerResource, data: Variant) -> void:
	if player_res == null:
		return
	player_res.daily_quests = []
	player_res.dailies_refresh_at_ms = 0
	if data is not Dictionary:
		return
	var dict: Dictionary = data
	player_res.dailies_refresh_at_ms = int(dict.get("refresh_at_ms", 0))
	var quests: Variant = dict.get("quests", [])
	if quests is not Array:
		return
	var day: int = _day_index(_now_ms())
	var kept: Array = []
	var seen_slots: Dictionary[int, bool] = {}
	for raw: Variant in quests:
		if raw is not Dictionary:
			continue
		var task: DailyTaskResource = DailyTaskResource.from_dict(raw)
		# from_dict returns null for a pre-overhaul entry (no skill key) or an
		# unknown slug — exactly the rows this overhaul retires.
		if task == null or task.day_index != day:
			continue
		if task.slot < 0 or task.slot >= TASK_COUNT or seen_slots.has(task.slot):
			continue
		seen_slots[task.slot] = true
		kept.append(task.to_dict())
	player_res.daily_quests = kept


# --- internals ---------------------------------------------------------------

## Write the accepted slots back to player state. Un-accepted slots are NOT
## persisted — they are re-derived, which is what makes an unaccepted board
## immune to a lost save.
func _store(player_res: PlayerResource, board: Array[DailyTaskResource]) -> void:
	var out: Array = []
	for task: DailyTaskResource in board:
		if task.accepted:
			out.append(task.to_dict())
	player_res.daily_quests = out


## Accepted slots for [param day], keyed by slot. Entries from another day are
## skipped, which is what makes the daily reset happen.
func _stored_by_slot(player_res: PlayerResource, day: int) -> Dictionary[int, DailyTaskResource]:
	var out: Dictionary[int, DailyTaskResource] = {}
	var table: DailyRewardTable = _load_table()
	for raw: Variant in player_res.daily_quests:
		if raw is not Dictionary:
			continue
		var task: DailyTaskResource = DailyTaskResource.from_dict(raw, table)
		if task == null or task.day_index != day:
			continue
		if task.slot < 0 or task.slot >= TASK_COUNT or out.has(task.slot):
			continue
		out[task.slot] = task
	return out


## The three skills offered to [param player_id] on [param day]. Pure function —
## same inputs, same answer, forever. Drawn without replacement, so the three are
## always distinct.
func _skills_for(player_id: int, day: int) -> Array[StringName]:
	var pool: Array[StringName] = SKILLS.duplicate()
	var rng: RandomNumberGenerator = _rng(player_id, day, -1, -1)
	# Hand-rolled Fisher-Yates: Array.shuffle() draws from the GLOBAL RNG, which
	# would make the roll depend on how much other randomness the server happened
	# to consume first — i.e. not reproducible, which defeats the whole design.
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: StringName = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, mini(TASK_COUNT, pool.size()))


## The skill on [param slot] — the accepted one if there is one, otherwise the
## derived offer.
func _skill_for_slot(player_res: PlayerResource, slot: int, day: int) -> StringName:
	var stored: Dictionary[int, DailyTaskResource] = _stored_by_slot(player_res, day)
	if stored.has(slot):
		return stored[slot].skill
	var skills: Array[StringName] = _skills_for(player_res.player_id, day)
	return skills[slot] if slot >= 0 and slot < skills.size() else SKILLS[0]


## Seeded RNG for one (player, day, slot, difficulty) draw. Pass -1 for slot and
## difficulty to get the day's skill-selection stream.
func _rng(player_id: int, day: int, slot: int, difficulty: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("daily:%d:%d:%d:%d" % [player_id, day, slot, difficulty])
	return rng


func _skill_level(player_res: PlayerResource, skill: StringName) -> int:
	if player_res == null:
		return 1
	var entry: Dictionary = player_res.get_skill(skill)
	return maxi(1, int(entry.get("level", 1)))


## True only when there are slots and every one is accepted AND claimed. An
## un-accepted slot means the day is not finished, so it must block the bonus.
func _all_claimed(board: Array[DailyTaskResource]) -> bool:
	if board.is_empty():
		return false
	for task: DailyTaskResource in board:
		if not task.accepted or not task.claimed:
			return false
	return true


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


@warning_ignore("integer_division")
func _day_index(now_ms: int) -> int:
	return now_ms / DAY_MS


func _load_table() -> DailyRewardTable:
	if _table_cache != null:
		return _table_cache
	if not ResourceLoader.exists(REWARD_TABLE_PATH):
		push_error("DailyQuestManager: reward table missing at %s — claims will be refused." % REWARD_TABLE_PATH)
		return null
	_table_cache = ResourceLoader.load(REWARD_TABLE_PATH) as DailyRewardTable
	return _table_cache
