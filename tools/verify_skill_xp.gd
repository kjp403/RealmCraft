extends SceneTree
## Headless gate: profession skills use the canonical OSRS XP curve.
## Avoids JobRegistry / Client autoloads — only loads SkillXp.
## Run: godot --headless --path . -s tools/verify_skill_xp.gd
## Expect: VERIFY_PASS

const CHECKPOINTS: Dictionary = {
	1: 0,
	2: 83,
	10: 1154,
	20: 4470,
	50: 101333,
	60: 273742,
	70: 737627,
	85: 3258594,
	92: 6517253,
	99: 13034431,
}

const DIFF_CHECKS: Dictionary = {
	1: 83,
	49: 9612,
	50: 10612,
	91: 614422,
	98: 1228825,
}


func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var skill_xp_script: Script = load("res://source/common/gameplay/jobs/skill_xp.gd") as Script
	if skill_xp_script == null:
		print("VERIFY_FAIL load skill_xp.gd")
		quit(1)
		return

	# Instantiate via class_name is unavailable before full project parse in some
	# -s runs; call static methods through the loaded script directly.
	var level_cap: int = int(skill_xp_script.get_script_constant_map().get("LEVEL_CAP", 0))
	var total_at_cap_const: int = int(
		skill_xp_script.get_script_constant_map().get("TOTAL_XP_AT_CAP", 0)
	)

	if level_cap != 99:
		failures.append("LEVEL_CAP=%d want 99" % level_cap)

	# Force bake by invoking static funcs on the class_name if available.
	var total_at_cap: int = SkillXp.total_xp_for_level(SkillXp.LEVEL_CAP)
	if total_at_cap != SkillXp.TOTAL_XP_AT_CAP:
		failures.append(
			"total_xp(%d)=%d want %d" % [SkillXp.LEVEL_CAP, total_at_cap, SkillXp.TOTAL_XP_AT_CAP]
		)
	if total_at_cap_const != 13034431:
		failures.append("TOTAL_XP_AT_CAP const=%d want 13034431" % total_at_cap_const)

	if SkillXp.XP_TO_NEXT.size() != SkillXp.LEVEL_CAP - 1:
		failures.append(
			"XP_TO_NEXT size=%d want %d" % [SkillXp.XP_TO_NEXT.size(), SkillXp.LEVEL_CAP - 1]
		)

	for level: int in CHECKPOINTS:
		var got: int = SkillXp.total_xp_for_level(level)
		var want: int = int(CHECKPOINTS[level])
		if got != want:
			failures.append("total_xp(%d)=%d want %d" % [level, got, want])

	for level: int in DIFF_CHECKS:
		var got: int = SkillXp.xp_to_next(level)
		var want: int = int(DIFF_CHECKS[level])
		if got != want:
			failures.append("xp_to_next(%d)=%d want %d" % [level, got, want])

	if SkillXp.xp_to_next(99) != 0:
		failures.append("xp_to_next(99) should be 0")

	# Sanity: all JobPerks .tres exist (new skills must drop a .tres under jobs/).
	var jobs_dir := DirAccess.open("res://source/common/gameplay/jobs")
	var job_count: int = 0
	if jobs_dir != null:
		jobs_dir.list_dir_begin()
		var fname: String = jobs_dir.get_next()
		while fname != "":
			if fname.ends_with(".tres") and not fname.begins_with("."):
				job_count += 1
			fname = jobs_dir.get_next()
		jobs_dir.list_dir_end()
	if job_count < 1:
		failures.append("no JobPerks .tres files found under jobs/")

	if failures.is_empty():
		print("VERIFY_PASS skill_xp osrs curve job_tres=%d total99=%d" % [job_count, total_at_cap])
		quit(0)
	else:
		print("VERIFY_FAIL")
		for line: String in failures:
			print("  - ", line)
		quit(1)
