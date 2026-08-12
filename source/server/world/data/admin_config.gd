class_name AdminConfig
## Maps character display names (or #player_id) to a server role, granted LIVE
## (read on each permission check, not written to the DB). Lets the server owner
## grant admin by editing a config file — no DB edits, no debug-only hacks —
## and removing a character revokes it immediately.
##
## Grants are CHARACTER-bound: other characters on the same login stay regular
## players. Use /grant and /revoke for in-game moderator/admin on a specific
## character.
##
## Looks for "user://server_admins.cfg" first (editable next to a deployed build), then the
## bundled "res://data/config/server_admins.cfg". Format (role names come from ServerRoles):
##   [admins]
##   MyStaffChar="owner"
##   #1042="senior_admin"
##   [leaderboard_hide]
##   SomeDisplayName=1
##
## SECURITY: guest* names are never honored — they previously matched auto-created
## guest logins and granted free senior_admin. owner / senior_admin belong only here.

const USER_PATH: String = "user://server_admins.cfg"
const RES_PATH: String = "res://data/config/server_admins.cfg"

static var _roles: Dictionary
static var _leaderboard_hide: Dictionary
static var _loaded: bool


## Role granted to this character via the config, or "" if none.
## Matches [param display_name] (case-insensitive) or `#player_id` / `player_id`.
static func role_for_character(display_name: String, player_id: int = 0) -> String:
	if not _loaded:
		_load()
	if player_id > 0:
		var by_hash: String = str(_roles.get("#%d" % player_id, ""))
		if not by_hash.is_empty():
			return by_hash
		var by_id: String = str(_roles.get(str(player_id), ""))
		if not by_id.is_empty():
			return by_id
	if display_name.is_empty():
		return ""
	return str(_roles.get(display_name.to_lower(), ""))


## Lookup a single config key (character display name or `#id`). Case-insensitive.
static func role_for(key: String) -> String:
	if key.is_empty():
		return ""
	if not _loaded:
		_load()
	return str(_roles.get(key.to_lower(), ""))


## True when [param name] (character display name, or an explicit hide-list
## account) is listed under [leaderboard_hide] in server_admins.cfg.
static func is_leaderboard_hidden(name: String) -> bool:
	if name.is_empty():
		return false
	if not _loaded:
		_load()
	return _leaderboard_hide.has(name.to_lower())


## All config-granted entries (character key -> role), for the /staff roster. A copy, so
## callers can't mutate the cache.
static func all() -> Dictionary:
	if not _loaded:
		_load()
	return _roles.duplicate()


## Re-read the file (e.g. after editing it without restarting the server).
static func reload() -> void:
	_roles.clear()
	_leaderboard_hide.clear()
	_loaded = false


static func _is_forbidden_name(name: String) -> bool:
	var key: String = name.to_lower()
	# guest1, guest2, … — auto-created guest usernames.
	if key.begins_with("guest") and key.substr(5).is_valid_int():
		return true
	return false


static func _load() -> void:
	_loaded = true
	var config: ConfigFile = ConfigFile.new()
	var path: String = USER_PATH if FileAccess.file_exists(USER_PATH) else RES_PATH
	if config.load(path) != OK:
		return
	if config.has_section("admins"):
		for entry: String in config.get_section_keys("admins"):
			if _is_forbidden_name(entry):
				push_warning(
					"AdminConfig: ignoring forbidden guest* admin entry '%s' in %s"
					% [entry, path]
				)
				continue
			var role: String = str(config.get_value("admins", entry, "")).strip_edges()
			if role.is_empty():
				continue
			_roles[entry.to_lower()] = role
	if config.has_section("leaderboard_hide"):
		for key: String in config.get_section_keys("leaderboard_hide"):
			var raw: Variant = config.get_value("leaderboard_hide", key, 0)
			var on: bool = false
			if raw is bool:
				on = raw
			elif raw is int or raw is float:
				on = int(raw) != 0
			else:
				var s: String = str(raw).strip_edges().to_lower()
				on = s in ["1", "true", "yes", "on"]
			if on:
				_leaderboard_hide[key.to_lower()] = true
