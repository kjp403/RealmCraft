class_name BanNotice
## Turns a BanList / IpBanList entry into the line a banned player actually reads.
##
## One formatter, three places: the chat notice pushed just before a /ban or
## /ipban kick, and the rejection the login path returns on their next attempt
## (world_manager_client.request_login). Same wording either way, so a player who
## was offline when the ban landed sees exactly what an online player saw.
##
## Deliberately plain English rather than translation keys: these are static
## funcs, which can't call tr(), and the string travels to the client as the
## "msg" field of a gateway error — the same channel the version gate uses.

const MS_PER_MINUTE: int = 60 * 1000
const MS_PER_HOUR: int = 60 * MS_PER_MINUTE
const MS_PER_DAY: int = 24 * MS_PER_HOUR


static func account_message(entry: Dictionary) -> String:
	return _compose("This account is", entry)


static func ip_message(entry: Dictionary) -> String:
	return _compose("This IP address is", entry)


static func _compose(subject: String, entry: Dictionary) -> String:
	var line: String = "%s %s." % [subject, _ban_phrase(int(entry.get("expires_at_ms", 0)))]
	var reason: String = str(entry.get("reason", "")).strip_edges()
	if reason.is_empty():
		return line + "\nNo reason was recorded."
	return line + "\nReason: " + reason


static func _ban_phrase(expires_at_ms: int) -> String:
	if expires_at_ms <= 0:
		return "permanently banned"
	var remaining_ms: int = expires_at_ms - int(Time.get_unix_time_from_system() * 1000.0)
	if remaining_ms <= 0:
		return "banned"
	return "banned for another " + _humanize_ms(remaining_ms)


## Coarse two-unit remainder ("6d 4h", "12m"). A popup doesn't need seconds, and
## the floor is 1m so a player with 20s left is never told "0m" while still out.
static func _humanize_ms(remaining_ms: int) -> String:
	var days: int = remaining_ms / MS_PER_DAY
	var hours: int = (remaining_ms % MS_PER_DAY) / MS_PER_HOUR
	var minutes: int = (remaining_ms % MS_PER_HOUR) / MS_PER_MINUTE
	if days > 0:
		if hours > 0:
			return "%dd %dh" % [days, hours]
		return "%dd" % days
	if hours > 0:
		if minutes > 0:
			return "%dh %dm" % [hours, minutes]
		return "%dh" % hours
	return "%dm" % maxi(minutes, 1)
