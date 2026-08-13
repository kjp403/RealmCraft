extends ChatCommand
## Remove a persisted server role from one online character and save. Roles
## granted via the admin config file are live and can't be revoked here — remove
## that character from server_admins.cfg instead.
##
## Like /grant, the target must name a CHARACTER (exact display name, #id, or
## self); @account is refused so the revoke can't hit the wrong alt.


func _init() -> void:
	command_name = "revoke"
	command_priority = 100 # senior_admin
	command_usage = "/revoke <self|Name|#id> <role>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage

	var role: String = args[2]
	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if target.by_account:
		return (
			"Roles are per character, not per account. Name the character "
			+ "(or its #id) — run /chars %s to list them." % args[1]
		)
	if not target.online:
		return "%s must be online to revoke a role." % target.label()

	if not target.resource.server_roles.has(role):
		# A config grant looks identical in game — same commands, same badge — but
		# it lives in server_admins.cfg, not the DB, so there is no row to erase.
		var config_role: String = AdminConfig.role_for_character(
			target.display_name, target.player_id
		)
		if config_role.to_lower() == role.to_lower():
			return (
				"%s holds '%s' from server_admins.cfg, not the database. "
				% [target.label(), role]
				+ "Remove that entry from the config and run /reloadadmins."
			)
		return "%s does not have the role '%s'." % [target.label(), role]

	target.resource.server_roles.erase(role)
	server_instance.world_server.database.save_player(target.resource)
	var player: Player = server_instance.players_by_peer_id.get(target.peer_id, null)
	if player != null and player.state_synchronizer != null:
		player.state_synchronizer.set_by_path(
			^":staff_role",
			CommandPermissions.effective_role_slug(target.resource, server_instance)
		)
	return "Revoked role '%s' from character %s (#%d) on account @%s." % [
		role, target.display_name, target.player_id, target.account_name
	]
