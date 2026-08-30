class_name DailyTaskResource
extends Resource
## One slot on the skilling daily board: which skill, how hard, how far along.
##
## Lifecycle — OFFERED -> ACTIVE -> COMPLETE -> CLAIMED (see [method state]).
## A slot is OFFERED until the player picks a difficulty; picking one stamps
## [member target_amount] and flips [member accepted]. Progress only counts
## actions performed AFTER that, never a snapshot of what is already in the bag,
## so accepting "Mine 300 ore" while holding 300 ore does not hand you a free
## claim. (Same rule the kill/collect board used before this overhaul; it is the
## single most abusable thing about a counter quest.)
##
## This Resource is the RUNTIME + authoring shape. Persisted state is the plain
## Dictionary from [method to_dict], stored on [member PlayerResource.daily_quests]
## and serialised by the existing `dailies_json` blob — so the whole overhaul
## needs no schema migration. Rehydrate with [method from_dict].

enum Difficulty { EASY, MEDIUM, HARD }
enum State { OFFERED, ACTIVE, COMPLETE, CLAIMED }

## Required actions per difficulty, indexed by [enum Difficulty]. `x` = low bound,
## `y` = high bound; the rolled value is snapped to a multiple of
## [constant QUANTITY_STEP] so targets read as "150", never "147".
const QUANTITY_BANDS: Array[Vector2i] = [
	Vector2i(25, 50),
	Vector2i(100, 200),
	Vector2i(300, 500),
]
const QUANTITY_STEP: int = 5

## What one action in each skill produces, in the player's words. Purely for
## display — the counter itself is skill-scoped and counts any action that pays
## XP into the job, so this must stay a NOUN FOR THE ACTION ("logs cut") and
## never name a specific item ("oak logs"), which would promise a filter the
## task does not apply. Lives server-side so the client never invents wording.
const ACTION_NOUNS: Dictionary[StringName, String] = {
	&"mining": "ore mined",
	&"woodcutting": "logs cut",
	&"fishing": "fish caught",
	&"harvesting": "herbs gathered",
	&"smithing": "bars smithed",
	&"cooking": "meals cooked",
	&"herblore": "potions brewed",
	&"fletching": "items fletched",
	&"outfitting": "items crafted",
}

## Board slot index (0..2). Also the handle the client passes back to pick a
## difficulty or claim — ids are positional because the board is regenerated
## deterministically each day rather than drawn from a template pool.
@export var slot: int = 0
## Job slug from [JobRegistry] — &"mining", &"outfitting", &"harvesting", ...
## NOT the display name: "Crafting" is the label for &"outfitting" and "Farming"
## for &"harvesting". Authoring against the label creates a slug that no XP grant
## will ever match, and the task silently never progresses.
@export var skill: StringName = &""
@export var difficulty: Difficulty = Difficulty.EASY
## Actions required. Stamped from [constant QUANTITY_BANDS] when the difficulty
## is chosen; 0 while the slot is still OFFERED.
@export var target_amount: int = 0
## Actions performed since acceptance. Clamped to [member target_amount].
@export var progress: int = 0
## Optional item filter — 0 (the default) counts ANY successful action that pays
## XP into [member skill]. Reserved for "catch 200 trout" style tasks; the
## generated board leaves it at 0 so a task is never blocked behind one node the
## player cannot find.
@export var target_item_id: int = 0
## True once a difficulty has been chosen. Offered-but-unaccepted slots are
## never persisted (they are re-derived), so this is always true after a load.
@export var accepted: bool = false
@export var claimed: bool = false
## UTC day index the slot belongs to. Guards against a stale entry surviving a
## reset — an entry from another day is discarded rather than counted.
@export var day_index: int = 0
## Payout curve. Shared table, not a per-task copy.
@export var reward_table: DailyRewardTable


## Derived board state. Deliberately computed rather than stored: a `state` field
## plus a `progress` field is two sources of truth for one fact, and they drift
## the first time progress is bumped on a path that forgets to restamp state.
func state() -> State:
	if not accepted:
		return State.OFFERED
	if claimed:
		return State.CLAIMED
	return State.COMPLETE if is_complete() else State.ACTIVE


func is_complete() -> bool:
	return accepted and target_amount > 0 and progress >= target_amount


func remaining() -> int:
	return maxi(0, target_amount - progress)


## True if a successful action in [param action_skill] producing [param item_id]
## should advance this task. [member target_item_id] of 0 matches any item.
func matches(action_skill: StringName, item_id: int) -> bool:
	if skill != action_skill:
		return false
	return target_item_id == 0 or target_item_id == item_id


## Add [param amount] actions, clamped to the target. Returns how much was
## ACTUALLY applied (0 once complete), so callers can skip a pointless network
## push when an already-finished task "advances".
func advance(amount: int) -> int:
	if amount <= 0 or not accepted or claimed or is_complete():
		return 0
	var before: int = progress
	progress = mini(progress + amount, target_amount)
	return progress - before


## Human-readable objective line, e.g. "Farming — perform 150 actions".
## Uses the JobRegistry display name so the player sees "Crafting", not the
## &"outfitting" slug the engine matches on.
func describe() -> String:
	var label: String = JobRegistry.display_name(skill)
	if target_amount <= 0:
		return "%s — choose a difficulty" % label
	return "%s — %d %s" % [label, target_amount, progress_noun()]


## Display noun for this task's actions ("logs cut"). Falls back to the generic
## word so an unmapped skill reads sensibly rather than blank.
func progress_noun() -> String:
	return ACTION_NOUNS.get(skill, "actions")


static func difficulty_name(difficulty: int) -> String:
	match difficulty:
		Difficulty.EASY: return "Easy"
		Difficulty.MEDIUM: return "Medium"
		Difficulty.HARD: return "Hard"
	return "?"


## Quantity band for [param difficulty], falling back to EASY for a bad index so
## a malformed client request can never produce a 0-target (instantly complete)
## task.
static func band_for(difficulty: int) -> Vector2i:
	if difficulty < 0 or difficulty >= QUANTITY_BANDS.size():
		return QUANTITY_BANDS[Difficulty.EASY]
	return QUANTITY_BANDS[difficulty]


## Roll a target for [param difficulty] from [param rng]. Deterministic for a
## given rng state — the board seeds one per (player, day, slot) so the numbers
## a player is offered cannot be rerolled by relogging.
static func roll_target(difficulty: int, rng: RandomNumberGenerator) -> int:
	var band: Vector2i = band_for(difficulty)
	var raw: int = rng.randi_range(band.x, band.y)
	return clampi(snappedi(raw, QUANTITY_STEP), band.x, band.y)


# --- Persistence -------------------------------------------------------------

## Compact persisted form. Keys are short because this rides inside the existing
## `dailies_json` blob for every player row.
func to_dict() -> Dictionary:
	return {
		"slot": slot,
		"skill": String(skill),
		"diff": int(difficulty),
		"target": target_amount,
		"progress": progress,
		"item": target_item_id,
		"claimed": claimed,
		"day": day_index,
	}


## Rebuild from [method to_dict]. Every field is defensively coerced: this data
## round-trips through JSON, where ints come back as floats and a hand-edited or
## truncated row can carry anything at all. Returns null for an entry with no
## usable skill, which the caller drops.
static func from_dict(data: Dictionary, table: DailyRewardTable = null) -> DailyTaskResource:
	var skill_slug := StringName(str(data.get("skill", "")))
	if skill_slug == &"" or not JobRegistry.has_job(skill_slug):
		return null
	var task := DailyTaskResource.new()
	task.slot = int(data.get("slot", 0))
	task.skill = skill_slug
	task.difficulty = clampi(
		int(data.get("diff", Difficulty.EASY)), Difficulty.EASY, Difficulty.HARD
	) as Difficulty
	task.target_amount = maxi(0, int(data.get("target", 0)))
	task.target_item_id = maxi(0, int(data.get("item", 0)))
	# Clamp on load, not just on write: a target that shrank (a band retune between
	# releases) would otherwise leave progress permanently above it, which reads as
	# 320/300 on the board.
	task.progress = clampi(int(data.get("progress", 0)), 0, task.target_amount)
	task.claimed = bool(data.get("claimed", false))
	task.day_index = int(data.get("day", 0))
	task.accepted = true
	task.reward_table = table
	return task
