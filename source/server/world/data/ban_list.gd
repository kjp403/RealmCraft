class_name BanList
## Live list of banned ACCOUNTS. Persists to user://server_bans.cfg.
## Keyed by account_name so a ban survives character switches. Checked at world
## authentication — banned accounts never enter the game.

const PATH: String = "user://server_bans.cfg"

static var _entries: Dictionary  # account_name -> {reason, since_ms, by_id, expires_at_ms}
static var _loaded: bool


## The live ban entry for [param account_name], or an empty Dictionary when the
## account isn't banned. Expired bans are purged here, so this is the one place
## that decides "still banned" — [method is_banned] is a thin wrapper and the
## login path reads reason/expiry straight off the result (see BanNotice).
static func ban_info(account_name: String) -> Dictionary:
	if not _loaded:
		_load()
	var key: String = account_name.to_lower()
	if not _entries.has(key):
		return {}
	var entry: Dictionary = _entries[key]
	var expires_at: int = int(entry.get("expires_at_ms", 0))
	if expires_at > 0 and int(Time.get_unix_time_from_system() * 1000.0) >= expires_at:
		_entries.erase(key)
		_save()
		return {}
	return entry.duplicate()


static func is_banned(account_name: String) -> bool:
	return not ban_info(account_name).is_empty()


static func ban(account_name: String, reason: String, by_id: int, duration_ms: int = 0) -> void:
	if not _loaded:
		_load()
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	_entries[account_name.to_lower()] = {
		"reason": reason,
		"since_ms": now_ms,
		"by_id": by_id,
		"expires_at_ms": 0 if duration_ms <= 0 else now_ms + duration_ms,
	}
	_save()


static func unban(account_name: String) -> bool:
	if not _loaded:
		_load()
	var key: String = account_name.to_lower()
	if not _entries.has(key):
		return false
	_entries.erase(key)
	_save()
	return true


static func entries() -> Dictionary:
	if not _loaded:
		_load()
	return _entries.duplicate()


static func _load() -> void:
	_loaded = true
	var config: ConfigFile = ConfigFile.new()
	if not FileAccess.file_exists(PATH):
		return
	if config.load(PATH) != OK or not config.has_section("bans"):
		return
	for key: String in config.get_section_keys("bans"):
		_entries[key] = config.get_value("bans", key, {})


static func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	for account_name: String in _entries:
		config.set_value("bans", account_name, _entries[account_name])
	config.save(PATH)
