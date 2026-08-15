class_name SlayerTaskService
## Server-side Slayer logic: assigning tasks, advancing them on kills, completion
## payout (points + OSRS streak-milestone bonus), and skip/block spends. Pure
## functions over a PlayerResource, exactly like QuestService / DailyQuestService —
## no per-instance state here.
##
## docs/slayer_skill.md has the full design write-up (master tables, the streak
## bonus math, task categories). This file is the mechanical implementation of it.

## OSRS's exact reward-point streak table (Slayer_reward_point wiki, 2026):
## bonus multipliers land on the 10th / 50th / 100th / 250th / 1,000th task IN A
## ROW. Anything else is a flat 1x. Applied on top of the completing master's
## base_points_per_task — so a 0-point master (Turael) still nets 0 on a milestone.
const STREAK_MILESTONES: Dictionary[int, int] = {
	1000: 50,
	250: 35,
	100: 25,
	50: 15,
	10: 5,
}

## Block-slot unlocks by Slayer level. Blocking itself is a future Slayer Shop
## spend (docs/slayer_skill.md "Slayer Shop (next)") — this just caps how many
## task slugs can ever sit in slayer_blocked_tasks at once, so the data model is
## ready the moment the shop ships.
const BLOCK_SLOT_LEVELS: Array[int] = [5, 30, 60, 90]
const BLOCK_POINT_COST: int = 60

## Slayer XP per kill = the killed monster's combat SKILL xp (the stat-derived
## EnemyTypeResource.combat_skill_xp_for, NOT the character-level xp_reward) × this.
## Slayer and weapon mastery ride the SAME SkillXp 1–99 curve (13,034,431 XP), and
## mastery banks that number in FULL on every kill (RewardService._reward), so this
## ratio IS the speed difference between the two: 1/3 = Slayer 1–99 takes ~3× the
## kills mastery does. It can never make Slayer the cheaper skill — even a maxed
## "focused" perk (+15%) only reaches 0.38×. On-task-only accrual pushes the real
## gap slightly past 3×, which is the intended direction.
const SLAYER_XP_RATIO: float = 1.0 / 3.0

## Multiplier on a BOSS kill's Slayer XP when the boss is on your task (the Goblin
## Chief for Goblins, the Fungal Heart for Fungus, ...). A boss is a scheduled,
## respawn-gated fight you cannot grind — without this it pays the same per-kill
## rate as the trash around it, which made hunting the head of a camp strictly
## worse than farming its runts. Applied in [method boss_xp_bonus] so the kill hook
## and the Slayer panel's advertised range agree.
const BOSS_XP_MULTIPLIER: float = 3.0


# ---------------------------------------------------------------------------
# Assignment
# ---------------------------------------------------------------------------

## Assigns a new task from [param master] if the player has none active. Returns
## {"ok": true, "task": StringName, "master": StringName, "amount": int,
## "display_name": String} on success, else {"ok": false, "reason": String}.
static func assign_task(resource: PlayerResource, master: SlayerMasterResource) -> Dictionary:
	if resource == null or master == null:
		return {"ok": false, "reason": "no_master"}
	if not resource.current_slayer_task.is_empty():
		return {"ok": false, "reason": "already_has_task"}
	var slayer_level: int = int(resource.get_skill(&"slayer").get("level", 1))
	if slayer_level < master.min_slayer_level:
		return {"ok": false, "reason": "master_level_too_low"}
	return _roll_and_assign(resource, master, slayer_level)


static func _roll_and_assign(resource: PlayerResource, master: SlayerMasterResource, slayer_level: int) -> Dictionary:
	var entries: Array[SlayerMasterTaskEntry] = master.eligible_entries(slayer_level, resource.slayer_blocked_tasks)
	if entries.is_empty():
		return {"ok": false, "reason": "no_eligible_tasks"}
	var total_weight: int = 0
	for entry: SlayerMasterTaskEntry in entries:
		total_weight += entry.weight
	var roll: int = randi_range(1, total_weight)
	var picked: SlayerMasterTaskEntry = entries[0]
	var running: int = 0
	for entry: SlayerMasterTaskEntry in entries:
		running += entry.weight
		if roll <= running:
			picked = entry
			break
	var amount: int = randi_range(mini(picked.min_amount, picked.max_amount), maxi(picked.min_amount, picked.max_amount))
	resource.current_slayer_task = {
		"task": String(picked.task.task_slug()),
		"master": String(master.master_slug()),
		"remaining": amount,
		"assigned_amount": amount,
	}
	return {
		"ok": true,
		"task": picked.task.task_slug(),
		"master": master.master_slug(),
		"amount": amount,
		"display_name": picked.task.display_name,
	}


## The SlayerTaskDef the player is currently assigned, or null if none / stale
## (content was removed from the master's pool since assignment — treated as gone,
## same "prereq id 0 = stale" spirit QuestResource.prerequisites_met uses).
static func current_task_def(resource: PlayerResource) -> SlayerTaskDef:
	if resource == null or resource.current_slayer_task.is_empty():
		return null
	var master: SlayerMasterResource = SlayerMasterRegistry.master_for(StringName(String(resource.current_slayer_task.get("master", ""))))
	if master == null:
		return null
	var task_slug: StringName = StringName(String(resource.current_slayer_task.get("task", "")))
	for entry: SlayerMasterTaskEntry in master.pool:
		if entry != null and entry.task != null and entry.task.task_slug() == task_slug:
			return entry.task
	return null


## UI payload for the Slayer panel: current task name, progress, guide notes, and
## the player's points/streak. {} current task fields when nothing is assigned.
static func status_payload(resource: PlayerResource) -> Dictionary:
	var skill: Dictionary = resource.get_skill(&"slayer")
	var out: Dictionary = {
		"level": int(skill.get("level", 1)),
		"xp": int(skill.get("xp", 0)),
		"points": resource.slayer_points,
		"streak": resource.slayer_streak,
		"tasks_completed": resource.slayer_tasks_completed,
	}
	var task: SlayerTaskDef = current_task_def(resource)
	if task != null:
		out["task"] = String(task.task_slug())
		out["display_name"] = task.display_name
		out["guide_notes"] = task.guide_notes
		out["remaining"] = int(resource.current_slayer_task.get("remaining", 0))
		out["assigned_amount"] = int(resource.current_slayer_task.get("assigned_amount", 0))
		out["master"] = resource.current_slayer_task.get("master", "")
		out["location_hint"] = task.location_hint
		var xp_r: Vector2i = task.xp_per_kill_range()
		var perks: JobPerks = JobRegistry.perks_for(&"slayer")
		var xp_mult: float = 1.0
		if perks != null:
			xp_mult = perks.xp_multiplier(skill.get("perks", {}))
		out["xp_per_kill_min"] = maxi(1, roundi(float(xp_r.x) * xp_mult))
		out["xp_per_kill_max"] = maxi(1, roundi(float(xp_r.y) * xp_mult))
	return out


# ---------------------------------------------------------------------------
# Kill hook — called from RewardService._reward alongside QuestService.on_kill
# and DailyQuestService.on_kill.
# ---------------------------------------------------------------------------

## A player killed an enemy of [param enemy_type], worth [param combat_skill_xp]
## on the 1–99 skill curve (the same number the kill just paid to weapon mastery).
## Advances the active task if it matches, grants Slayer XP for
## THAT kill (multiplied by [constant BOSS_XP_MULTIPLIER] when [param is_boss]),
## and completes + pays out the task on the final kill. Returns {} if
## there's no active task or it doesn't match this enemy; otherwise
## {"advanced": true, "remaining": int, "xp_gained": int, "leveled_up": bool,
## "complete": bool, "points_gained": int (only if complete),
## "streak": int (only if complete)}.
static func on_kill(
	resource: PlayerResource,
	enemy_type: StringName,
	combat_skill_xp: int = 0,
	is_boss: bool = false
) -> Dictionary:
	if resource == null or resource.current_slayer_task.is_empty():
		return {}
	var task: SlayerTaskDef = current_task_def(resource)
	if task == null or not task.matches(enemy_type):
		return {}

	var xp: int = _xp_per_kill(resource, task, enemy_type, combat_skill_xp, is_boss)
	var xp_result: Dictionary = resource.add_skill_xp(&"slayer", xp)

	var remaining: int = int(resource.current_slayer_task.get("remaining", 0)) - 1
	var out: Dictionary = {
		"advanced": true,
		"remaining": maxi(remaining, 0),
		"xp_gained": xp,
		"leveled_up": bool(xp_result.get("leveled_up", false)),
		"complete": false,
	}
	if remaining > 0:
		resource.current_slayer_task["remaining"] = remaining
		return out

	# Final kill — pay out and clear the task.
	var master: SlayerMasterResource = SlayerMasterRegistry.master_for(StringName(String(resource.current_slayer_task.get("master", ""))))
	resource.slayer_tasks_completed += 1
	resource.slayer_streak += 1
	var points: int = _points_for_completion(master, resource.slayer_streak)
	resource.slayer_points += points
	resource.current_slayer_task = {}

	out["complete"] = true
	out["points_gained"] = points
	out["streak"] = resource.slayer_streak
	return out


## Slayer XP for ONE kill of [param enemy_type] under [param task], resolved in
## priority order:
##   1. task.xp_overrides[enemy_type]  — hand-tuned exception (trpg_necromancer)
##   2. combat_skill_xp × SLAYER_XP_RATIO — the normal path, so a 1,000 HP boss and
##      a 200 HP zombie in the same task pay out proportionally instead of both
##      paying the group's flat average
##   3. task.xp_per_kill — fallback when the kill reported no combat skill XP
## then multiplied by the boss bonus (see [method boss_xp_bonus]) and scaled by
## JobPerks.xp_multiplier, exactly how gathering XP scales (mining's
## "diligent" perk) — the &"slayer" job's "focused" perk is the combat equivalent.
static func _xp_per_kill(
	resource: PlayerResource,
	task: SlayerTaskDef,
	enemy_type: StringName,
	combat_skill_xp: int,
	is_boss: bool = false
) -> int:
	var base: int = 0
	if task.xp_overrides.has(enemy_type):
		base = int(task.xp_overrides[enemy_type])
	elif combat_skill_xp > 0:
		base = roundi(float(combat_skill_xp) * SLAYER_XP_RATIO)
	else:
		base = task.xp_per_kill
	base = maxi(1, roundi(float(base) * boss_xp_bonus(is_boss)))

	var perks: JobPerks = JobRegistry.perks_for(&"slayer")
	if perks == null:
		return base
	var skill: Dictionary = resource.get_skill(&"slayer")
	var mult: float = perks.xp_multiplier(skill.get("perks", {}))
	return maxi(1, roundi(float(base) * mult))


## Slayer-XP multiplier for one kill: [constant BOSS_XP_MULTIPLIER] for a boss on
## task, 1.0 for everything else. One function so the kill payout and the range the
## Slayer panel advertises (SlayerTaskDef.xp_per_kill_range) can never disagree.
static func boss_xp_bonus(is_boss: bool) -> float:
	return BOSS_XP_MULTIPLIER if is_boss else 1.0


## base_points_per_task × the OSRS streak-milestone multiplier for THIS completion
## (checked against [param streak_after], the count including the task just
## finished). Points are paid on COMPLETION only — never per kill, never on skip.
## Every master pays something (Turael 3, Durael 6); a 0-point master would still
## correctly net 0, the multiplier just has nothing to multiply.
static func _points_for_completion(master: SlayerMasterResource, streak_after: int) -> int:
	if master == null or master.base_points_per_task <= 0:
		return 0
	var mult: int = 1
	for milestone: int in [1000, 250, 100, 50, 10]:
		if streak_after > 0 and streak_after % milestone == 0:
			mult = STREAK_MILESTONES[milestone]
			break
	return master.base_points_per_task * mult


# ---------------------------------------------------------------------------
# On-task defence — the "task_ward" perk
# ---------------------------------------------------------------------------

## Multiplier applied to damage [param resource]'s player is about to take from a
## monster of [param enemy_type]. 1.0 for everything except the monsters their
## ACTIVE task targets, which the &"slayer" job's "Task Ward" perk softens by
## per_rank × rank (capped by JobPerks.abs_max_task_resist). The defensive
## counterpart to "Focused Hunter": both only ever pay out while on task.
##
## Called from Character.take_damage on every hit, so the cheap outs (no task, no
## ranks spent) come first — the task/pool lookup only runs for a player who has
## actually bought the perk.
static func task_damage_factor(resource: PlayerResource, enemy_type: StringName) -> float:
	if resource == null or enemy_type == &"" or resource.current_slayer_task.is_empty():
		return 1.0
	var perks: JobPerks = JobRegistry.perks_for(&"slayer")
	if perks == null:
		return 1.0
	var skill: Dictionary = resource.get_skill(&"slayer")
	var reduction: float = perks.task_damage_reduction(skill.get("perks", {}))
	if reduction <= 0.0:
		return 1.0
	var task: SlayerTaskDef = current_task_def(resource)
	if task == null or not task.matches(enemy_type):
		return 1.0
	return maxf(0.0, 1.0 - reduction)


# ---------------------------------------------------------------------------
# Skip / reassignment
# ---------------------------------------------------------------------------

## Reassigns the current task. Turael-style masters (free_reassign) do this for
## free; paid masters charge reassign_point_cost (see _skip_cost).
##
## NOTHING here touches the streak. Arkenelle deliberately diverges from OSRS, where
## a Turael-style reassign is the one action that zeroes it: here the streak only
## ever counts completions, so reassigning, blocking, and switching which master you
## take work from all leave it alone. A streak is a record of tasks finished, not a
## loyalty pledge to one master.
static func skip_task(resource: PlayerResource, master: SlayerMasterResource) -> Dictionary:
	if resource == null or master == null:
		return {"ok": false, "reason": "no_master"}
	if resource.current_slayer_task.is_empty():
		return {"ok": false, "reason": "no_active_task"}
	if String(resource.current_slayer_task.get("master", "")) != String(master.master_slug()):
		return {"ok": false, "reason": "wrong_master"} # walk back to whoever assigned it

	if master.free_reassign:
		resource.current_slayer_task = {}
		var assigned: Dictionary = _roll_and_assign(resource, master, int(resource.get_skill(&"slayer").get("level", 1)))
		assigned["cost"] = 0
		assigned["streak_reset"] = false
		return assigned

	var cost: int = _skip_cost(resource, master)
	if resource.slayer_points < cost:
		return {"ok": false, "reason": "not_enough_points", "cost": cost}
	resource.slayer_points -= cost
	resource.current_slayer_task = {}
	var result: Dictionary = _roll_and_assign(resource, master, int(resource.get_skill(&"slayer").get("level", 1)))
	result["cost"] = cost
	result["streak_reset"] = false
	return result


## The master's flat cost, less any &"skip_discount" the player has. No perk grants
## that effect today (the slot the old "Efficient Reassignment" perk filled now
## holds "Task Ward"), so this is the full price until something else feeds it —
## sum_effect returns 0.0 for an effect nothing targets.
static func _skip_cost(resource: PlayerResource, master: SlayerMasterResource) -> int:
	var perks: JobPerks = JobRegistry.perks_for(&"slayer")
	if perks == null:
		return master.reassign_point_cost
	var skill: Dictionary = resource.get_skill(&"slayer")
	var discount: float = perks.sum_effect(skill.get("perks", {}), &"skip_discount")
	return maxi(0, roundi(float(master.reassign_point_cost) * (1.0 - clampf(discount, 0.0, 0.9))))


# ---------------------------------------------------------------------------
# Blocking — data model only; the spend UI ships with the Slayer Shop
# (docs/slayer_skill.md "Slayer Shop (next)"). Included now so PlayerResource
# never needs another migration when that lands.
# ---------------------------------------------------------------------------

static func max_block_slots(slayer_level: int) -> int:
	var slots: int = 0
	for lvl: int in BLOCK_SLOT_LEVELS:
		if slayer_level >= lvl:
			slots += 1
	return slots


static func block_task(resource: PlayerResource, task_slug: StringName) -> Dictionary:
	if resource == null or task_slug.is_empty():
		return {"ok": false, "reason": "bad_task"}
	if resource.slayer_blocked_tasks.has(task_slug):
		return {"ok": false, "reason": "already_blocked"}
	var level: int = int(resource.get_skill(&"slayer").get("level", 1))
	if resource.slayer_blocked_tasks.size() >= max_block_slots(level):
		return {"ok": false, "reason": "no_free_slots"}
	if resource.slayer_points < BLOCK_POINT_COST:
		return {"ok": false, "reason": "not_enough_points", "cost": BLOCK_POINT_COST}
	resource.slayer_points -= BLOCK_POINT_COST
	resource.slayer_blocked_tasks[task_slug] = true
	return {"ok": true, "cost": BLOCK_POINT_COST}


static func unblock_task(resource: PlayerResource, task_slug: StringName) -> void:
	resource.slayer_blocked_tasks.erase(task_slug)
