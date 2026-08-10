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
	return out


# ---------------------------------------------------------------------------
# Kill hook — called from RewardService._reward alongside QuestService.on_kill
# and DailyQuestService.on_kill.
# ---------------------------------------------------------------------------

## A player killed an enemy of [param enemy_type]. Advances the active task if it
## matches, grants slayer XP for the kill, and completes + pays out the task on
## the final kill. Returns {} if there's no active task or it doesn't match this
## enemy; otherwise {"advanced": true, "remaining": int, "xp_gained": int,
## "leveled_up": bool, "complete": bool, "points_gained": int (only if complete),
## "streak": int (only if complete)}.
static func on_kill(resource: PlayerResource, enemy_type: StringName) -> Dictionary:
	if resource == null or resource.current_slayer_task.is_empty():
		return {}
	var task: SlayerTaskDef = current_task_def(resource)
	if task == null or not task.matches(enemy_type):
		return {}

	var xp: int = _xp_per_kill(resource, task)
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


## Slayer XP for one kill under [param task]: JobPerks-driven multiplier over the
## task's flat xp_per_kill, exactly how JobPerks.xp_multiplier scales gathering XP
## (mining.tres's "diligent" perk, etc.) — the &"slayer" job's "focused" perk is the
## combat-skill equivalent.
static func _xp_per_kill(resource: PlayerResource, task: SlayerTaskDef) -> int:
	var perks: JobPerks = JobRegistry.perks_for(&"slayer")
	if perks == null:
		return task.xp_per_kill
	var skill: Dictionary = resource.get_skill(&"slayer")
	var mult: float = perks.xp_multiplier(skill.get("perks", {}))
	return maxi(1, roundi(float(task.xp_per_kill) * mult))


## base_points_per_task × the OSRS streak-milestone multiplier for THIS completion
## (checked against [param streak_after], the count including the task just
## finished). 0-point masters (Turael) always net 0 — the multiplier has nothing
## to multiply, matching real OSRS exactly.
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
# Skip / reassignment
# ---------------------------------------------------------------------------

## Reassigns the current task. Turael-style masters (free_reassign) do this for
## free but RESET THE STREAK TO ZERO — the one real OSRS action that does (per the
## wiki's Slayer_task_streak page; skipping via points on a paid master, or
## switching which master you use, does NOT reset it). Paid masters charge
## reassign_point_cost (discounted by the &"slayer" job's skip_discount perk) and
## do NOT touch the streak.
static func skip_task(resource: PlayerResource, master: SlayerMasterResource) -> Dictionary:
	if resource == null or master == null:
		return {"ok": false, "reason": "no_master"}
	if resource.current_slayer_task.is_empty():
		return {"ok": false, "reason": "no_active_task"}
	if String(resource.current_slayer_task.get("master", "")) != String(master.master_slug()):
		return {"ok": false, "reason": "wrong_master"} # walk back to whoever assigned it

	if master.free_reassign:
		resource.current_slayer_task = {}
		resource.slayer_streak = 0
		var assigned: Dictionary = _roll_and_assign(resource, master, int(resource.get_skill(&"slayer").get("level", 1)))
		assigned["cost"] = 0
		assigned["streak_reset"] = true
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
