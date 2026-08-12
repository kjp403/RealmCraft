extends SceneTree
## Headless checks for Guild Hall Total Level champion statues + the total_level board.
## File/source inspection only — avoids Client / JobRegistry preload cycles.
## Run: godot --headless --path . -s tools/verify_total_level_statues.gd
## Expect: VERIFY_PASS

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	# --- Scoring helper (inline mirror of LeaderboardService.total_skill_level_of) ---
	var svc: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/leaderboard/leaderboard_service.gd"
	)
	if svc.find("\"total_level\"") < 0 and svc.find('"total_level"') < 0:
		failures.append("leaderboard_service missing total_level board branch")
	if svc.find('STATUE_BOARDS: Array[String] = ["total_level"]') < 0:
		failures.append("STATUE_BOARDS must be [total_level] only")
	if svc.find("TOTAL_LEVEL_SKILLS") < 0:
		failures.append("TOTAL_LEVEL_SKILLS constant missing")
	for slug: String in [
		"mining", "harvesting", "woodcutting", "fishing",
		"smithing", "outfitting", "cooking", "slayer",
	]:
		if svc.find('&"%s"' % slug) < 0:
			failures.append("TOTAL_LEVEL_SKILLS missing &\"%s\"" % slug)

	# --- ChampionStatue maps level → total_level --------------------------------
	var statue: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/leaderboard/champion_statue.gd"
	)
	if statue.find('"level": "total_level"') < 0:
		failures.append("ChampionStatue BOARD_BY_CATEGORY level must map to total_level")
	if statue.find("Total Level %d") < 0:
		failures.append("ChampionStatue plaque missing Total Level score line")

	# --- Guild Hall hosts ranks 1–3 ---------------------------------------------
	var hall: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/guild_house/inside_map.tscn"
	)
	if hall.find("champion_statue.tscn") < 0:
		failures.append("Guild Hall does not reference champion_statue.tscn")
	for rank: int in [1, 2, 3]:
		var node_name: String = "TotalLevelChampion%d" % rank
		var at: int = hall.find("[node name=\"%s\"" % node_name)
		if at < 0:
			failures.append("%s missing from Guild Hall" % node_name)
			continue
		var chunk: String = hall.substr(at, 280)
		if chunk.find("category = \"level\"") < 0:
			failures.append("%s category is not level" % node_name)
		if chunk.find("rank = %d" % rank) < 0:
			failures.append("%s rank is not %d" % [node_name, rank])

	# --- Leaderboard menu exposes Total Level under Progression -----------------
	var menu: String = FileAccess.get_file_as_string(
		"res://source/client/ui/menus/leaderboard/leaderboard_menu.gd"
	)
	if menu.find("total_level") < 0:
		failures.append("leaderboard_menu missing total_level board")
	if menu.find("Total Level") < 0:
		failures.append("leaderboard_menu missing Total Level label")

	# --- Staff hide from boards (admins must not occupy Guild Hall statues) ------
	var perms: String = FileAccess.get_file_as_string(
		"res://source/server/world/components/chat_command/command_permissions.gd"
	)
	if perms.find("is_leaderboard_hidden") < 0:
		failures.append("is_hidden_from_leaderboard must consult AdminConfig.is_leaderboard_hidden")
	if perms.find("_db_role_blocked(role)") >= 0 and perms.find("is_hidden_from_leaderboard") >= 0:
		# Hide path must NOT skip live-blocked senior_admin via _db_role_blocked.
		var hide_fn: int = perms.find("static func is_hidden_from_leaderboard")
		var hide_body: String = perms.substr(hide_fn, 900)
		if hide_body.find("_db_role_blocked") >= 0:
			failures.append("leaderboard hide must count DB senior_admin/owner (no _db_role_blocked)")
	if svc.find("invalidate_champions_cache") < 0:
		failures.append("LeaderboardService missing invalidate_champions_cache")
	var admins_cfg: String = FileAccess.get_file_as_string("res://data/config/server_admins.cfg")
	if admins_cfg.find("[leaderboard_hide]") < 0:
		failures.append("server_admins.cfg missing [leaderboard_hide] section")
	if admins_cfg.to_lower().find("tomatoface") < 0:
		failures.append("server_admins.cfg should list Tomatoface for staff/hide")

	if failures.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL")
		for f: String in failures:
			print(" - ", f)
	quit(0 if failures.is_empty() else 1)
