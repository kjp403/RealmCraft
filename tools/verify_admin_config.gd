extends SceneTree
## Admin cfg parser + owner priority floor.
##   godot --headless --path . -s tools/verify_admin_config.gd

var _fail: int = 0


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), label)
	if not ok:
		_fail += 1


func _initialize() -> void:
	var bundled: String = FileAccess.get_file_as_string("res://data/config/server_admins.cfg")
	_check(not bundled.is_empty(), "bundled server_admins.cfg reads")
	AdminConfig.load_text_for_verify(bundled)
	_check(AdminConfig.role_for_character("KJP", 2) == "owner", "KJP / id 2 is owner")
	_check(AdminConfig.role_for_character("kjp", 0) == "owner", "KJP match is case-insensitive")
	_check(AdminConfig.role_for_character("kjp403", 0) == "owner", "kjp403 is owner")
	_check(AdminConfig.role_for_character("tomatoface", 0) == "senior_admin", "tomatoface is senior_admin")
	_check(AdminConfig.role_for_character("KJP_2", 3).is_empty(), "KJP_2 is not granted")

	var with_hash_comment := """
[admins]
; Format mentions #player_id="role" in a comment
KJP="owner"
2="owner"
"""
	AdminConfig.load_text_for_verify(with_hash_comment)
	_check(AdminConfig.role_for_character("KJP", 2) == "owner", "hash in a comment does not abort the file")

	var numeric_only := """
[admins]
2="owner"
"""
	AdminConfig.load_text_for_verify(numeric_only)
	_check(AdminConfig.role_for_character("Nope", 2) == "owner", "numeric player id key grants owner")

	_check(CommandPermissions.ROLE_PRIORITY_FALLBACK.get("owner", 0) == 1000, "owner fallback priority is 1000")
	_check(
		int(CommandPermissions.ROLE_PRIORITY_FALLBACK.get("admin", 0)) >= CommandPermissions.STAFF_PROTECT_PRIORITY,
		"admin fallback is at the staff floor"
	)

	print("ADMIN_CONFIG_VERIFY_%s failures=%d" % ["FAIL" if _fail else "PASS", _fail])
	quit(_fail)
