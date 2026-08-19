class_name AdminConfig
## Maps character display names (or numeric player_id) to a server role, granted
## LIVE (read on each permission check, not written to the DB).
##
## Do NOT use Godot ConfigFile here. ConfigFile is a VariantParser: a single
## `#` in a comment or a numeric key can abort the whole load, and then every
## owner grant is silently empty ("Command not found" for /gold). This reader
## is line-based, never fails closed, and falls back to the bundled file.
##
## Lookup:
##   1. user://server_admins.cfg if it exists AND parsed at least one admin
##   2. else res://data/config/server_admins.cfg
##
## Format:
##   [admins]
##   KJP="owner"
##   2="owner"
##   [leaderboard_hide]
##   SomeName=1

const USER_PATH: String = "user://server_admins.cfg"
const RES_PATH: String = "res://data/config/server_admins.cfg"

static var _roles: Dictionary
static var _leaderboard_hide: Dictionary
static var _loaded: bool
static var _source_path: String = ""


## Role granted to this character via the config, or "" if none.
## Matches [param display_name] (case-insensitive) or `player_id` / `#player_id`.
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
	_source_path = ""


static func _is_forbidden_name(name: String) -> bool:
	var key: String = name.to_lower()
	# guest1, guest2, … — auto-created guest usernames.
	if key.begins_with("guest") and key.substr(5).is_valid_int():
		return true
	return false


static func _load() -> void:
	_loaded = true
	_roles.clear()
	_leaderboard_hide.clear()
	_source_path = ""
	if FileAccess.file_exists(USER_PATH) and _read_path(USER_PATH) and not _roles.is_empty():
		_source_path = USER_PATH
	elif FileAccess.file_exists(RES_PATH) and _read_path(RES_PATH):
		_source_path = RES_PATH
	var keys: PackedStringArray = PackedStringArray(_roles.keys())
	print(
		"AdminConfig: %d admin(s) from %s (%s)"
		% [_roles.size(), _source_path if not _source_path.is_empty() else "none", ", ".join(keys)]
	)


static func _read_path(path: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("AdminConfig: cannot open %s" % path)
		return false
	var text: String = file.get_as_text()
	file.close()
	_parse_text(text)
	return true


## Line-based INI. Full-line `;` / `#` comments only. Never aborts the file.
static func _parse_text(text: String) -> void:
	var section: String = ""
	for raw_line: String in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.is_empty() or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges().to_lower()
			continue
		var eq: int = line.find("=")
		if eq <= 0:
			continue
		var key: String = _unquote(line.substr(0, eq).strip_edges())
		var value: String = _unquote(line.substr(eq + 1).strip_edges())
		if key.is_empty():
			continue
		if section == "admins":
			if _is_forbidden_name(key):
				push_warning("AdminConfig: ignoring forbidden guest* admin entry '%s'" % key)
				continue
			if value.is_empty():
				continue
			_roles[key.to_lower()] = value
		elif section == "leaderboard_hide":
			var on: bool = value.to_lower() in ["1", "true", "yes", "on"]
			if on:
				_leaderboard_hide[key.to_lower()] = true


static func _unquote(s: String) -> String:
	if s.length() >= 2 and s.begins_with("\"") and s.ends_with("\""):
		return s.substr(1, s.length() - 2)
	return s


## Headless tests: parse [param text] as if it were a cfg file.
static func load_text_for_verify(text: String) -> void:
	reload()
	_loaded = true
	_parse_text(text)
