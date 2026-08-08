extends ChatCommand
## Grant a server role to an online player and persist it to the DB. Use this for
## staff (moderator/admin). The owner should grant themselves senior_admin via the
## admin config file, not here.


func _init() -> void:
	command_name = "grant"
	command_priority = 100 # senior_admin
	command_usage = "/grant <self|@account|#id> <role>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage

	var role: String = args[2]
	if not server_instance.global_role_definitions.has(role):
		return "Unknown role '%s'. Known roles: %s" % [
			role, ", ".join(server_instance.global_role_definitions.keys())
		]
	# senior_admin is config-file only — never persist it via /grant (closes the
	# selfadmin → /grant @alt senior_admin replication path).
	if role == "senior_admin":
		return "senior_admin can only be granted via server_admins.cfg, not /grant."

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online to grant a role." % target.label()

	target.resource.server_roles[role] = {}
	server_instance.world_server.database.save_player(target.resource)
	_refresh_staff_badge(target, server_instance)
	return "Granted role '%s' to %s." % [role, target.label()]


func _refresh_staff_badge(target: CommandTarget.Result, server_instance: ServerInstance) -> void:
	if not target.online:
		return
	var player: Player = server_instance.players_by_peer_id.get(target.peer_id, null)
	if player == null or player.state_synchronizer == null:
		return
	player.state_synchronizer.set_by_path(
		^":staff_role",
		CommandPermissions.effective_role_slug(target.resource, server_instance)
	)
