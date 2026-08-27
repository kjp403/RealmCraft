extends ChatCommand
## Owner-only character rename. Writes `players.display_name` (unique, case-
## insensitive) and, if they're online, syncs the nametag. Player-facing
## renames stay disabled — this is the staff tool for a bad/stuck name.
##
## Target a CHARACTER (exact name, #id, or self). @account is refused so an
## alt doesn't get renamed by accident. Offline characters are fine: the DB
## row updates and they log in under the new name.

const CredentialsUtils: GDScript = preload("res://source/common/utils/credentials_utils.gd")


func _init() -> void:
	command_name = "rename"
	command_priority = 1000 # owner only
	command_usage = "/rename <self|Name|#id> <newname>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 3:
		return "Usage: " + command_usage

	# Names can contain spaces, so the new name is everything after the target.
	var new_name: String = " ".join(args.slice(2)).strip_edges()
	var check: Dictionary = CredentialsUtils.validate_username(new_name)
	if check.get("code", CredentialsUtils.UsernameError.EMPTY) != CredentialsUtils.UsernameError.OK:
		return str(check.get("message", "Invalid name."))

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if target.by_account:
		return (
			"Names are per character, not per account. Name the character "
			+ "(or its #id) — run /chars %s to list them." % args[1]
		)

	var ws: WorldServer = server_instance.world_server
	var res: PlayerResource = target.resource
	if res == null:
		if target.player_id <= 0:
			return "Couldn't resolve that character. Try /chars and target by #id."
		res = ws.database.get_player_resource(target.player_id)
	if res == null:
		return "No character found for %s." % target.label()

	var old_name: String = res.display_name
	if old_name == new_name:
		return "%s is already named %s." % [target.label(), old_name]

	if ws.database.is_display_name_taken(new_name, res.player_id):
		return "The name '%s' is already taken." % new_name

	res.display_name = new_name
	ws.database.save_player(res)

	if target.online:
		var player: Player = CommandTarget.player_node(target, server_instance)
		if player != null and player.state_synchronizer != null:
			player.state_synchronizer.set_by_path(^":display_name", new_name)
		ws.chat_service.push_system_to_player(
			server_instance,
			res.player_id,
			"An owner renamed your character from %s to %s." % [old_name, new_name]
		)

	ServerLog.info("Owner (peer %d) renamed #%d '%s' -> '%s'." % [
		peer_id, res.player_id, old_name, new_name
	])

	var when: String = " Nametag updated." if target.online else " Offline — they log in as %s." % new_name
	var note: String = _admin_cfg_note(old_name, res.player_id)
	return "Renamed %s (#%d) to %s.%s%s" % [old_name, res.player_id, new_name, when, note]


## server_admins.cfg keys by display name (or #id). Renaming a name-keyed
## owner/senior_admin character would drop their config grant until the file
## is updated — say so instead of a silent lockout.
func _admin_cfg_note(old_name: String, player_id: int) -> String:
	if AdminConfig.role_for(old_name).is_empty():
		return ""
	if not AdminConfig.role_for("#%d" % player_id).is_empty():
		return ""
	if not AdminConfig.role_for(str(player_id)).is_empty():
		return ""
	return (
		" NOTE: '%s' is listed in server_admins.cfg by name — update the cfg "
		+ "(prefer #id) and /reloadadmins or their config role drops."
	) % old_name
