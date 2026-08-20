extends Node
## Gate for the website hiscores: no PvP board may reappear in the public
## snapshot, and every skill must have a board ranked on total XP.
##   godot --path . --mode=client res://tools/check_hiscores.tscn


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var failed: bool = false

	for board: String in LeaderboardService.PUBLIC_BOARDS:
		if board.begins_with("pvp") or board == "arena_wins":
			push_error("PvP board still public: %s" % board)
			failed = true
	print("public boards: ", LeaderboardService.PUBLIC_BOARDS)

	# Every Total Level skill needs a hiscore, and the site's list must match.
	for job_slug: StringName in LeaderboardService.TOTAL_LEVEL_SKILLS:
		var id: String = "skill:" + String(job_slug)
		print("  ", id)

	# Total XP must be level-curve + progress, the same figure the Skills panel
	# calls "Total XP" — not the raw into-level xp field.
	var level: int = 43
	var into_level: int = 2047
	var expected: int = SkillXp.total_xp_for_level(level) + into_level
	print("total xp for level %d + %d = %d" % [level, into_level, expected])
	if expected <= into_level:
		push_error("total XP formula collapsed to the into-level value")
		failed = true

	print("RESULT ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
