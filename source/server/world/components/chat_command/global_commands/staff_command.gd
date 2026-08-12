extends ChatCommand
## List everyone holding a server role, from BOTH sources:
##   - config-granted (server_admins.cfg) — character display name or #id, and
##   - DB-persisted roles (granted via /grant, or written any other way).
## A DB role you didn't grant is a red flag (e.g. an exploit). Online holders are
## tagged so you can see who's on right now.


func _init() -> void:
	command_name = "staff"
	command_priority = 1 # moderator+
	command_usage = "/staff"


func execute(_args: PackedStringArray, _peer_id: int, server_instance: ServerInstance) -> String:
	var lines: PackedStringArray = PackedStringArray()

	# Online characters so we can tag who's currently connected.
	var online_names: Dictionary = {}
	var online_ids: Dictionary = {}
	for online_peer: int in server_instance.world_server.connected_players:
		var p: PlayerResource = server_instance.world_server.connected_players[online_peer]
		if p != null:
			online_names[p.display_name.to_lower()] = true
			online_ids[p.player_id] = true

	# Config-granted (live, never written to the DB) — character display name or #id.
	var config_roles: Dictionary = AdminConfig.all()
	if not config_roles.is_empty():
		lines.append("Config (server_admins.cfg):")
		for key: String in config_roles:
			var tag: String = ""
			if key.begins_with("#"):
				var pid: int = key.substr(1).to_int()
				if online_ids.has(pid):
					tag = " [online]"
			elif online_names.has(key.to_lower()):
				tag = " [online]"
			elif key.is_valid_int() and online_ids.has(key.to_int()):
				tag = " [online]"
			lines.append("- %s: %s%s" % [key, str(config_roles[key]), tag])

	# DB-persisted roles.
	var holders: Array = server_instance.world_server.database.store.get_role_holders()
	if not holders.is_empty():
		lines.append("Database roles:")
		for h: Dictionary in holders:
			var roles: Dictionary = h.get("roles", {})
			var tag: String = " [online]" if online_ids.has(int(h.get("player_id", 0))) else ""
			lines.append("- %s @%s (#%d): %s%s" % [
				str(h.get("name", "")),
				str(h.get("account", "")),
				int(h.get("player_id", 0)),
				", ".join(PackedStringArray(roles.keys())),
				tag,
			])

	if lines.is_empty():
		return "No roles assigned (no config admins, no DB roles)."
	return "\n".join(lines)
