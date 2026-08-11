extends SceneTree
## Headless gate: weapon mastery uses the same 1–99 OSRS XP curve as skills.
## Run: godot --headless --path . -s tools/verify_mastery_xp.gd
## Expect: VERIFY_PASS

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	if PlayerResource.MASTERY_LEVEL_CAP != SkillXp.LEVEL_CAP:
		failures.append(
			"MASTERY_LEVEL_CAP=%d want %d" % [
				PlayerResource.MASTERY_LEVEL_CAP, SkillXp.LEVEL_CAP
			]
		)
	if PlayerResource.MASTERY_LEVEL_CAP != 99:
		failures.append("MASTERY_LEVEL_CAP=%d want 99" % PlayerResource.MASTERY_LEVEL_CAP)

	var res := PlayerResource.new()
	# Fresh category: first practice creates level 1 with no leftover XP.
	var first: Dictionary = res.add_mastery_xp(&"wand", 0)
	if int(first.get("level", 0)) != 1:
		failures.append("fresh mastery level=%s want 1" % first.get("level"))
	if bool(first.get("started", false)) != true:
		failures.append("fresh mastery should set started")

	# Exact OSRS step: level 1→2 needs 83 XP.
	var step: Dictionary = res.add_mastery_xp(&"wand", SkillXp.xp_to_next(1))
	if int(step.get("level", 0)) != 2:
		failures.append("after 83 xp level=%s want 2" % step.get("level"))
	if not bool(step.get("leveled_up", false)):
		failures.append("83 xp should level_up")
	if int(step.get("xp", -1)) != 0:
		failures.append("exact level-up should leave xp=0 got %s" % step.get("xp"))
	if int(step.get("xp_to_next", 0)) != SkillXp.xp_to_next(2):
		failures.append(
			"xp_to_next(2)=%s want %d" % [step.get("xp_to_next"), SkillXp.xp_to_next(2)]
		)

	# Mirror skill curve at several checkpoints via bulk grant.
	var sword := PlayerResource.new()
	var total_to_50: int = SkillXp.total_xp_for_level(50)
	var at_50: Dictionary = sword.add_mastery_xp(&"sword", total_to_50)
	if int(at_50.get("level", 0)) != 50:
		failures.append("total_xp_to_50 → level=%s want 50" % at_50.get("level"))
	if int(at_50.get("xp_to_next", 0)) != SkillXp.xp_to_next(50):
		failures.append(
			"at 50 xp_to_next=%s want %d" % [at_50.get("xp_to_next"), SkillXp.xp_to_next(50)]
		)

	var bow := PlayerResource.new()
	var at_cap: Dictionary = bow.add_mastery_xp(&"bow", SkillXp.TOTAL_XP_AT_CAP + 999)
	if int(at_cap.get("level", 0)) != 99:
		failures.append("cap grant level=%s want 99" % at_cap.get("level"))
	if int(at_cap.get("xp", -1)) != 0:
		failures.append("at cap xp should be 0 got %s" % at_cap.get("xp"))
	if int(at_cap.get("xp_to_next", -1)) != 0:
		failures.append("at cap xp_to_next should be 0 got %s" % at_cap.get("xp_to_next"))

	# Frozen at cap — further XP ignored.
	var still: Dictionary = bow.add_mastery_xp(&"bow", 50000)
	if int(still.get("level", 0)) != 99 or int(still.get("xp", -1)) != 0:
		failures.append("post-cap grant should stay level 99 xp 0")

	if failures.is_empty():
		print(
			"VERIFY_PASS mastery_xp cap=%d xp_to_next(1)=%d total99=%d"
			% [PlayerResource.MASTERY_LEVEL_CAP, SkillXp.xp_to_next(1), SkillXp.TOTAL_XP_AT_CAP]
		)
		quit(0)
	else:
		print("VERIFY_FAIL")
		for line: String in failures:
			print("  - ", line)
		quit(1)
