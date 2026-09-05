class_name IpBanList
## Live list of banned client IPs. Persists to user://server_ip_bans.cfg.
## Checked at world authentication alongside account BanList.

const PATH: String = "user://server_ip_bans.cfg"
const LAST_IPS_PATH: String = "user://account_last_ips.cfg"

static var _entries: Dictionary  # ip -> {reason, since_ms, by_id, expires_at_ms}
static var _last_ips: Dictionary  # account_name -> ip
static var _loaded: bool
static var _last_ips_loaded: bool


static func normalize_ip(ip: String) -> String:
	var cleaned: String = ip.strip_edges()
	# Strip accidental :port on IPv4 (never strip IPv6 bare addresses).
	if cleaned.count(":") == 1 and cleaned.contains("."):
		cleaned = cleaned.get_slice(":", 0)
	return cleaned


static func is_usable_ip(ip: String) -> bool:
	var n: String = normalize_ip(ip)
	if n.is_empty():
		return false
	if n in ["127.0.0.1", "::1", "0.0.0.0", "localhost"]:
		return false
	return true


## True when [param token] looks like a raw IP rather than a player target token.
static func looks_like_ip(token: String) -> bool:
	if token.begins_with("@") or token.begins_with("#") or token == "self":
		return false
	# IPv4 or IPv6-ish; player display names won't match this loosely.
	if token.contains(".") and token.get_slice(".", 0).is_valid_int():
		return true
	if token.count(":") >= 2:
		return true
	return false


## The live ban entry for [param ip], or an empty Dictionary when that IP isn't
## banned. Mirrors [method BanList.ban_info]: expiry is purged here, and the
## login path reads reason/expiry off the result to explain the rejection.
static func ban_info(ip: String) -> Dictionary:
	if not _loaded:
		_load()
	var key: String = normalize_ip(ip)
	if key.is_empty() or not _entries.has(key):
		return {}
	var entry: Dictionary = _entries[key]
	var expires_at: int = int(entry.get("expires_at_ms", 0))
	if expires_at > 0 and int(Time.get_unix_time_from_system() * 1000.0) >= expires_at:
		_entries.erase(key)
		_save()
		return {}
	return entry.duplicate()


static func is_banned(ip: String) -> bool:
	return not ban_info(ip).is_empty()


static func ban(ip: String, reason: String, by_id: int, duration_ms: int = 0) -> String:
	if not _loaded:
		_load()
	var key: String = normalize_ip(ip)
	if not is_usable_ip(key):
		return ""
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	_entries[key] = {
		"reason": reason,
		"since_ms": now_ms,
		"by_id": by_id,
		"expires_at_ms": 0 if duration_ms <= 0 else now_ms + duration_ms,
	}
	_save()
	return key


static func unban(ip: String) -> bool:
	if not _loaded:
		_load()
	var key: String = normalize_ip(ip)
	if not _entries.has(key):
		return false
	_entries.erase(key)
	_save()
	return true


static func entries() -> Dictionary:
	if not _loaded:
		_load()
	return _entries.duplicate()


static func remember_account_ip(account_name: String, ip: String) -> void:
	if account_name.is_empty() or not is_usable_ip(ip):
		return
	if not _last_ips_loaded:
		_load_last_ips()
	_last_ips[account_name.to_lower()] = normalize_ip(ip)
	_save_last_ips()


static func last_ip_for_account(account_name: String) -> String:
	if not _last_ips_loaded:
		_load_last_ips()
	return str(_last_ips.get(account_name.to_lower(), ""))


static func _load() -> void:
	_loaded = true
	var config: ConfigFile = ConfigFile.new()
	if not FileAccess.file_exists(PATH):
		return
	if config.load(PATH) != OK or not config.has_section("ip_bans"):
		return
	for key: String in config.get_section_keys("ip_bans"):
		_entries[key] = config.get_value("ip_bans", key, {})


static func _save() -> void:
	var config: ConfigFile = ConfigFile.new()
	for ip: String in _entries:
		config.set_value("ip_bans", ip, _entries[ip])
	config.save(PATH)


static func _load_last_ips() -> void:
	_last_ips_loaded = true
	var config: ConfigFile = ConfigFile.new()
	if not FileAccess.file_exists(LAST_IPS_PATH):
		return
	if config.load(LAST_IPS_PATH) != OK or not config.has_section("ips"):
		return
	for key: String in config.get_section_keys("ips"):
		_last_ips[key.to_lower()] = str(config.get_value("ips", key, ""))


static func _save_last_ips() -> void:
	var config: ConfigFile = ConfigFile.new()
	for account_name: String in _last_ips:
		config.set_value("ips", account_name, _last_ips[account_name])
	config.save(LAST_IPS_PATH)
