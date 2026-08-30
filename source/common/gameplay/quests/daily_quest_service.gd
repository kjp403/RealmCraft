class_name DailyQuestService
## RETIRED — superseded by DailyQuestManager (the skilling-only daily board).
## NOTHING CALLS THIS ANY MORE: the board handlers, the gather/craft hooks, and
## the kill/spar/dungeon hooks were all repointed or removed in that overhaul.
## It still compiles, which is exactly why this notice is here — do not wire new
## code to it, and do not "fix" a bug in it.
##
## Left on disk rather than deleted because its content resource
## (resources/daily_pool.tres) is registered in registry/indexes/quests_index.tres;
## removing the pool means regenerating that index, which is a separate change.
## Delete this file, daily_quest_pool.gd, daily_quest_template.gd and the pool
## .tres together, then regenerate the index.
##
## --- Original documentation follows ---
##
## Generates and tracks the player's daily quest board state. All methods are
## static; state lives on PlayerResource (daily_quests + dailies_refresh_at_ms).
##
## Every daily is an ACTIVITY counter — kills, gathers, crafts, duels, or dungeon
## clears done AFTER the daily rolled. Progress is stored per entry in
## count_so_far (seeded 0 on roll) and bumped by the on_* hooks below. It is NEVER
## read from a snapshot of current inventory, so a fresh daily can't be already
## complete just because you happen to be holding the target items.
##
## Flow:
##   - Player clicks the QuestBoard -> quest.board.info -> get_or_roll +
##     build_board_payload.
##   - A gameplay event (kill / gather / craft / duel / dungeon clear) calls the
##     matching on_* hook, which bumps counters and pushes daily.progress so an
##     open board updates live.
##   - Player clicks Claim on a complete daily -> quest.board.claim -> reward.
##     The claim that finishes the whole set also pays a one-off completion bonus.
##   - Player clicks Skip on one they can't do -> quest.board.skip -> that slot is
##     rerolled, spending one of the day's MAX_SKIPS_PER_DAY.

const POOL_PATH: String = "res://source/common/gameplay/quests/resources/daily_pool.tres"
const DAILY_COUNT: int = 3

## Paid once when the whole set is claimed (fires on the final claim of the day).
## BONUS_XP is the lifetime adventure counter; BONUS_MASTERY_XP is the one that
## actually progresses a character (see DailyQuestTemplate.reward_mastery_xp).
const BONUS_XP: int = 250
const BONUS_MASTERY_XP: int = 20_000
const BONUS_GOLD: int = 2_500

## Rerolls a player may spend per day. A daily is rolled from a level band, not
## from where the player actually is in the world, so a set can legitimately
## contain something they cannot reach yet ("Defeat 1 Iron Golem" at level 16 with
## no idea where golems live). Skips are the escape hatch for exactly that; three
## is enough to replace the whole set once without making the board a slot machine
## you spin until it says "craft 2 items".
const MAX_SKIPS_PER_DAY: int = 3

static var _pool_cache: DailyQuestPool


# --- Public API ---

## Ensure the player has a current daily set. Rolls if stale or never rolled.
static func get_or_roll(player_res: PlayerResource) -> Array:
	_refresh_if_stale(player_res)
	return player_res.daily_quests


# --- Event hooks (bump matching counters + push live progress) ---

## A mob of [param enemy_type] was killed — advance matching KILL dailies.
static func on_kill(player_res: PlayerResource, enemy_type: StringName) -> void:
	_bump(player_res, DailyQuestTemplate.Kind.KILL, enemy_type, 1)


## [param amount] of [param item_id] entered the bag through GAMEPLAY (mob loot,
## mining) — advance matching COLLECT dailies. Deliberately NOT called for shop
## buys / trades / quest rewards, so "collect" means actually go gather it.
static func on_collect(player_res: PlayerResource, item_id: int, amount: int) -> void:
	_bump(player_res, DailyQuestTemplate.Kind.COLLECT, item_id, amount)


## A craft produced [param amount] items — advance matching CRAFT dailies by that
## many, so "craft N items" tracks items MADE (a stack-output craft counts fully,
## not as a single tick).
static func on_craft(player_res: PlayerResource, amount: int) -> void:
	_bump(player_res, DailyQuestTemplate.Kind.CRAFT, null, amount)


## A sparring match ended for this participant (win OR loss) — advance SPAR dailies.
static func on_spar(player_res: PlayerResource) -> void:
	_bump(player_res, DailyQuestTemplate.Kind.SPAR, null, 1)


## A dungeon run was cleared for this member — advance DUNGEON dailies.
static func on_dungeon_clear(player_res: PlayerResource) -> void:
	_bump(player_res, DailyQuestTemplate.Kind.DUNGEON, null, 1)


# --- Claim ---

## Claim a completed daily: validates it's complete + not already claimed, returns
## the reward. The claim that finishes the whole set adds a completion bonus.
static func claim(player_res: PlayerResource, template_id: int) -> Dictionary:
	_refresh_if_stale(player_res)
	var pool: DailyQuestPool = _load_pool()
	if pool == null:
		return {"ok": false, "reason": "no_pool"}
	var template: DailyQuestTemplate = pool.by_id(template_id)
	if template == null:
		return {"ok": false, "reason": "no_template"}
	for entry: Variant in player_res.daily_quests:
		if entry is not Dictionary:
			continue
		var d: Dictionary = entry
		if int(d.get("template_id", 0)) != template_id:
			continue
		if bool(d.get("claimed", false)):
			return {"ok": false, "reason": "already_claimed"}
		if _progress(player_res, d, template) < template.required_amount:
			return {"ok": false, "reason": "incomplete"}
		d["claimed"] = true
		var result: Dictionary = {
			"ok": true,
			"xp": template.reward_xp,
			"mastery_xp": template.reward_mastery_xp,
			"gold": template.reward_gold,
		}
		# The claim that completes the set pays a one-off bonus. A claimed daily
		# can't be re-claimed, so this transition happens exactly once per day —
		# no extra flag to persist.
		if _all_claimed(player_res):
			result["bonus_xp"] = BONUS_XP
			result["bonus_mastery_xp"] = BONUS_MASTERY_XP
			result["bonus_gold"] = BONUS_GOLD
		return result
	return {"ok": false, "reason": "not_in_set"}


# --- Skip / reroll ---

## Rerolls one unclaimed daily for a different template the player is eligible for,
## spending one of the day's [constant MAX_SKIPS_PER_DAY]. Returns
## {"ok": true, "template_id": int (the replacement), "skips_left": int} or
## {"ok": false, "reason": String}.
##
## The replacement is drawn from the templates NOT already in the set, so a skip
## always changes the board — rerolling "Defeat 1 Iron Golem" into itself would
## burn a skip for nothing. When the player's level band holds no other template,
## the skip is refused (and NOT spent) rather than silently no-opping.
static func skip(player_res: PlayerResource, template_id: int) -> Dictionary:
	_refresh_if_stale(player_res)
	if skips_left(player_res) <= 0:
		return {"ok": false, "reason": "no_skips_left"}
	var pool: DailyQuestPool = _load_pool()
	if pool == null:
		return {"ok": false, "reason": "no_pool"}

	var slot: int = -1
	var in_set: Dictionary[int, bool] = {}
	for i: int in player_res.daily_quests.size():
		var entry: Variant = player_res.daily_quests[i]
		if entry is not Dictionary:
			continue
		var d: Dictionary = entry
		var id: int = int(d.get("template_id", 0))
		in_set[id] = true
		if id == template_id:
			if bool(d.get("claimed", false)):
				return {"ok": false, "reason": "already_claimed"}
			slot = i
	if slot < 0:
		return {"ok": false, "reason": "not_in_set"}

	var candidates: Array[DailyQuestTemplate] = []
	for t: DailyQuestTemplate in pool.eligible_for_level(player_res.level):
		if not in_set.has(t.template_id):
			candidates.append(t)
	if candidates.is_empty():
		return {"ok": false, "reason": "no_alternative"}

	var replacement: DailyQuestTemplate = candidates[randi() % candidates.size()]
	player_res.daily_quests[slot] = {
		"template_id": replacement.template_id,
		"count_so_far": 0,
		"claimed": false,
	}
	player_res.dailies_skips_used += 1
	return {
		"ok": true,
		"template_id": replacement.template_id,
		"skips_left": skips_left(player_res),
	}


## Rerolls the player has left today. Clamped both ways so a legacy save carrying a
## count above the cap reads as 0 rather than a negative.
static func skips_left(player_res: PlayerResource) -> int:
	return clampi(MAX_SKIPS_PER_DAY - player_res.dailies_skips_used, 0, MAX_SKIPS_PER_DAY)


# --- Board payload (shared by the info handler + the live-progress push) ---

## Build the client-facing board state from the CURRENT set (does NOT roll).
## quest.board.info calls get_or_roll first; the live push does not.
static func build_board_payload(player_res: PlayerResource) -> Dictionary:
	var pool: DailyQuestPool = _load_pool()
	if pool == null:
		return {"ok": false, "reason": "no_pool"}
	var entries: Array = []
	for entry: Variant in player_res.daily_quests:
		if entry is not Dictionary:
			continue
		var d: Dictionary = entry
		var template: DailyQuestTemplate = pool.by_id(int(d.get("template_id", 0)))
		if template == null:
			continue
		var progress: int = _progress(player_res, d, template)
		entries.append({
			"template_id": template.template_id,
			"kind": template.kind,
			"description": template.describe(),
			"location_hint": template.location_hint,
			"required": template.required_amount,
			"progress": progress,
			"complete": progress >= template.required_amount,
			"claimed": bool(d.get("claimed", false)),
			"reward_xp": template.reward_xp,
			"reward_mastery_xp": template.reward_mastery_xp,
			"reward_gold": template.reward_gold,
		})
	return {
		"ok": true,
		"entries": entries,
		"refresh_at_ms": player_res.dailies_refresh_at_ms,
		"all_claimed": not entries.is_empty() and _all_claimed(player_res),
		"bonus_xp": BONUS_XP,
		"bonus_mastery_xp": BONUS_MASTERY_XP,
		"bonus_gold": BONUS_GOLD,
		"skips_left": skips_left(player_res),
		"skips_per_day": MAX_SKIPS_PER_DAY,
	}


## Progress for one entry (thin public wrapper over _progress). Kept for any
## external caller; the board payload uses _progress directly.
static func progress_for(player_res: PlayerResource, entry: Dictionary) -> int:
	var pool: DailyQuestPool = _load_pool()
	if pool == null:
		return 0
	var template: DailyQuestTemplate = pool.by_id(int(entry.get("template_id", 0)))
	return _progress(player_res, entry, template) if template != null else 0


# --- internals ---

## Bump count_so_far on every daily matching [param kind] (and [param key] for the
## targeted kinds — pass null for generic action kinds). Pushes live progress to
## the player's client if anything actually advanced.
static func _bump(player_res: PlayerResource, kind: int, key: Variant, amount: int) -> void:
	if player_res == null or amount <= 0:
		return
	var pool: DailyQuestPool = _load_pool()
	if pool == null:
		return
	var changed: bool = false
	for entry: Variant in player_res.daily_quests:
		if entry is not Dictionary:
			continue
		var d: Dictionary = entry
		var template: DailyQuestTemplate = pool.by_id(int(d.get("template_id", 0)))
		if template == null or template.kind != kind:
			continue
		if key != null and template.target_key() != key:
			continue
		var count: int = int(d.get("count_so_far", 0))
		if count >= template.required_amount:
			continue # already done — nothing to bump or push
		d["count_so_far"] = mini(count + amount, template.required_amount)
		changed = true
	if changed:
		_notify_progress(player_res)


## Push the current board to the player's client so an OPEN board updates live.
## Gated: only called when a counter actually advanced (see _bump).
static func _notify_progress(player_res: PlayerResource) -> void:
	if WorldServer.curr == null or player_res == null:
		return
	var peer: int = int(player_res.current_peer_id)
	if peer <= 0:
		return
	WorldServer.curr.data_push.rpc_id(peer, &"daily.progress", build_board_payload(player_res))


static func _progress(_player_res: PlayerResource, entry: Dictionary, template: DailyQuestTemplate) -> int:
	return mini(int(entry.get("count_so_far", 0)), template.required_amount)


## True only if there's at least one daily and every one is claimed.
static func _all_claimed(player_res: PlayerResource) -> bool:
	var any: bool = false
	for entry: Variant in player_res.daily_quests:
		if entry is not Dictionary:
			continue
		any = true
		if not bool((entry as Dictionary).get("claimed", false)):
			return false
	return any


## Roll DAILY_COUNT new dailies for the player and stamp the next refresh time.
static func _refresh_if_stale(player_res: PlayerResource) -> void:
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	if now_ms < player_res.dailies_refresh_at_ms and not player_res.daily_quests.is_empty():
		return
	var pool: DailyQuestPool = _load_pool()
	if pool == null:
		player_res.daily_quests = []
		return
	var eligible: Array[DailyQuestTemplate] = pool.eligible_for_level(player_res.level)
	eligible.shuffle()
	var picks: Array = []
	var taken: Dictionary = {}
	for t: DailyQuestTemplate in eligible:
		if picks.size() >= DAILY_COUNT:
			break
		if taken.has(t.template_id):
			continue
		taken[t.template_id] = true
		picks.append({
			"template_id": t.template_id,
			"count_so_far": 0,
			"claimed": false,
		})
	player_res.daily_quests = picks
	player_res.dailies_refresh_at_ms = _next_utc_midnight_ms(now_ms)
	# Same statement that stamps the next refresh — so the skip budget can never
	# drift out of sync with the set it belongs to.
	player_res.dailies_skips_used = 0


## Next 00:00 UTC after the given unix-ms.
static func _next_utc_midnight_ms(now_ms: int) -> int:
	const DAY_MS: int = 24 * 60 * 60 * 1000
	@warning_ignore("integer_division")
	var today_start: int = (now_ms / DAY_MS) * DAY_MS
	return today_start + DAY_MS


static func _load_pool() -> DailyQuestPool:
	if _pool_cache != null:
		return _pool_cache
	if not ResourceLoader.exists(POOL_PATH):
		return null
	_pool_cache = ResourceLoader.load(POOL_PATH) as DailyQuestPool
	return _pool_cache
