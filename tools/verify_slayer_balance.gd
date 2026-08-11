extends SceneTree
## Headless checks for the Slayer XP/points rebalance:
##   - Slayer XP is granted PER KILL, derived from that kill's stat-based combat
##     skill XP (NOT the character-level xp_reward — the two curves stay decoupled)
##   - the ratio never makes Slayer cheaper than weapon mastery
##   - 99 is actually reachable
##   - points land on completion only, for BOTH masters
##   - nothing resets the streak (reassign, master switch, blocking)

const TASK_DIR := "res://source/common/gameplay/slayer/tasks/"


func _init() -> void:
	var failures: Array[String] = []

	var res := PlayerResource.new()
	res.skills[&"slayer"] = {"level": 50, "xp": 0, "perks": {}}

	var turael: SlayerMasterResource = load("res://source/common/gameplay/slayer/masters/turael.tres")
	var durael: SlayerMasterResource = load("res://source/common/gameplay/slayer/masters/durael.tres")
	if turael == null or durael == null:
		print("VERIFY_FAIL masters failed to load")
		quit(1)
		return

	# --- Turael now pays points -------------------------------------------
	if turael.base_points_per_task <= 0:
		failures.append("Turael still pays 0 points/task")
	if turael.base_points_per_task > durael.base_points_per_task:
		failures.append("Turael out-pays Durael (%d vs %d)" % [turael.base_points_per_task, durael.base_points_per_task])

	# --- XP is per kill, scaled off THIS monster's combat xp ---------------
	# The two curves must stay decoupled: character xp_reward is NOT skill XP.
	var zombie_skill: int = EnemyTypeResource.combat_skill_xp_for(200.0, 3.0)   # 230 effHP
	var necro_skill: int = EnemyTypeResource.combat_skill_xp_for(1000.0, 18.0)  # 1900 effHP
	if zombie_skill != 920:
		failures.append("zombie skill xp %d, expected 230 effHP x 4 = 920" % zombie_skill)
	if necro_skill != 7600:
		failures.append("necromancer skill xp %d, expected 1900 effHP x 4 = 7600" % necro_skill)
	# Armor must lengthen the kill and pay for it.
	if EnemyTypeResource.combat_skill_xp_for(100.0, 20.0) <= EnemyTypeResource.combat_skill_xp_for(100.0, 0.0):
		failures.append("armor did not increase combat skill XP")

	res.current_slayer_task = {
		"task": "undead_legion", "master": "durael", "remaining": 5, "assigned_amount": 5,
	}
	var weak: Dictionary = SlayerTaskService.on_kill(res, &"trpg_zombie_giant", zombie_skill)
	var boss: Dictionary = SlayerTaskService.on_kill(res, &"trpg_necromancer", necro_skill)
	if int(weak.get("xp_gained", 0)) == int(boss.get("xp_gained", 0)):
		failures.append("flat XP: zombie and necromancer both paid %d" % int(weak.get("xp_gained", 0)))
	if int(boss.get("xp_gained", 0)) != roundi(float(necro_skill) / 3.0):
		failures.append("necromancer paid %d, expected %d" % [int(boss.get("xp_gained", 0)), roundi(float(necro_skill) / 3.0)])
	if int(weak.get("xp_gained", 0)) != roundi(float(zombie_skill) / 3.0):
		failures.append("zombie paid %d, expected %d" % [int(weak.get("xp_gained", 0)), roundi(float(zombie_skill) / 3.0)])
	# 99 must be reachable: a mid-tier on-task kill should clear the curve in
	# well under 200k kills, not the ~1.9M the old xp_reward-fed rule gave.
	var kills_to_99: int = int(SkillXp.TOTAL_XP_AT_CAP / maxi(1, int(weak.get("xp_gained", 1))))
	if kills_to_99 > 200000:
		failures.append("Slayer 1-99 still needs %d mid-tier kills" % kills_to_99)
	# Both kills must have advanced the counter (XP is per kill, not per completion).
	if int(res.current_slayer_task.get("remaining", 0)) != 3:
		failures.append("counter at %d after 2 kills, expected 3" % int(res.current_slayer_task.get("remaining", 0)))
	if int(res.get_skill(&"slayer").get("xp", 0)) <= 0:
		failures.append("no Slayer XP banked mid-task — XP is not being paid per kill")

	# --- Slayer must never out-earn combat XP for the same kill ------------
	for combat_xp: int in [4, 15, 140, 3200]:
		var probe := PlayerResource.new()
		probe.skills[&"slayer"] = {"level": 99, "xp": 0, "perks": {&"focused": 3}}
		probe.current_slayer_task = {
			"task": "skeletons", "master": "turael", "remaining": 9, "assigned_amount": 9,
		}
		var got: Dictionary = SlayerTaskService.on_kill(probe, &"skeleton", combat_xp)
		var gained: int = int(got.get("xp_gained", 0))
		if gained > combat_xp and combat_xp > 1:
			failures.append("Slayer XP %d > combat XP %d (max perks) — Slayer is the cheaper skill" % [gained, combat_xp])

	# --- Points on completion only, never per kill ------------------------
	var comp := PlayerResource.new()
	comp.skills[&"slayer"] = {"level": 50, "xp": 0, "perks": {}}
	comp.current_slayer_task = {
		"task": "skeletons", "master": "turael", "remaining": 2, "assigned_amount": 2,
	}
	var mid: Dictionary = SlayerTaskService.on_kill(comp, &"skeleton", 400)
	if mid.has("points_gained"):
		failures.append("points paid mid-task (per kill), should be completion only")
	if comp.slayer_points != 0:
		failures.append("points banked mid-task: %d" % comp.slayer_points)
	var done: Dictionary = SlayerTaskService.on_kill(comp, &"skeleton", 400)
	if not bool(done.get("complete", false)):
		failures.append("final kill did not complete the task")
	if int(done.get("points_gained", 0)) != turael.base_points_per_task:
		failures.append("completion paid %d points, expected Turael's %d" % [int(done.get("points_gained", 0)), turael.base_points_per_task])
	if comp.slayer_streak != 1:
		failures.append("streak %d after 1 completion, expected 1" % comp.slayer_streak)

	# --- Nothing resets the streak ----------------------------------------
	var st := PlayerResource.new()
	st.skills[&"slayer"] = {"level": 50, "xp": 0, "perks": {}}
	st.slayer_streak = 7
	st.slayer_points = 500
	# Free (Turael-style) reassign — the one OSRS resets. Must NOT reset here.
	SlayerTaskService.assign_task(st, turael)
	var reassigned: Dictionary = SlayerTaskService.skip_task(st, turael)
	if st.slayer_streak != 7:
		failures.append("free reassign reset streak to %d (expected 7 kept)" % st.slayer_streak)
	if bool(reassigned.get("streak_reset", false)):
		failures.append("free reassign still reports streak_reset = true")
	# Switching masters mid-streak.
	st.current_slayer_task = {}
	SlayerTaskService.assign_task(st, durael)
	if st.slayer_streak != 7:
		failures.append("switching masters reset streak to %d" % st.slayer_streak)
	# Paid skip.
	SlayerTaskService.skip_task(st, durael)
	if st.slayer_streak != 7:
		failures.append("paid skip reset streak to %d" % st.slayer_streak)
	# Blocking.
	SlayerTaskService.block_task(st, &"rats")
	if st.slayer_streak != 7:
		failures.append("blocking reset streak to %d" % st.slayer_streak)

	# --- No task still carries the stale placeholder guide note -----------
	var dir := DirAccess.open(TASK_DIR)
	if dir != null:
		for f: String in dir.get_files():
			if not f.ends_with(".tres"):
				continue
			var t: SlayerTaskDef = load(TASK_DIR + f)
			if t == null:
				failures.append("%s failed to load" % f)
				continue
			if t.guide_notes.contains("PLACEHOLDER"):
				failures.append("%s still has a PLACEHOLDER guide note (shown to players)" % f)
			if t.xp_per_kill <= 0:
				failures.append("%s has xp_per_kill %d" % [f, t.xp_per_kill])

	if failures.is_empty():
		print("VERIFY_PASS slayer_balance")
		quit(0)
	else:
		for f2: String in failures:
			print("VERIFY_FAIL ", f2)
		quit(1)
