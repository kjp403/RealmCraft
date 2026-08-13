extends ChatCommand
## Grant a server role to one online character and persist it to that character's
## DB row. Other characters on the same login are unchanged. Use this for staff
## (moderator/admin). owner / senior_admin are config-file only
## (server_admins.cfg, by character name) — never via /grant.
##
## The target must name a CHARACTER (exact display name, #id, or self). @account
## is refused: it resolves to whichever character on that login is online, so the
## role would silently land on an alt instead of the intended staff character.


func _init() -> void:
	command_name = "grant"
	command_priority = 100 # senior_admin
	command_usage = "/grant <self|Name|#id> <role>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage

	var role: String = args[2]
	if not server_instance.global_role_definitions.has(role):
		return "Unknown role '%s'. Known roles: %s" % [
			role, ", ".join(server_instance.global_role_definitions.keys())
		]
	# owner / senior_admin are config-file only — never persist via /grant.
	if role in ["owner", "senior_admin"]:
		return "%s can only be granted via server_admins.cfg, not /grant." % role

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	# Roles are character-bound. @account would hand the role to whichever
	# character on that login is online right now — name the character instead.
	if target.by_account:
		return (
			"Roles are per character, not per account. Name the character "
			+ "(or its #id) — run /chars %s to list them." % args[1]
		)
	if not target.online:
		return "%s must be online to grant a role." % target.label()

	target.resource.server_roles[role] = {}
	server_instance.world_server.database.save_player(target.resource)
	_refresh_staff_badge(target, server_instance)
	# Spell out the character vs account split — the label leads with the
	# character name, which is easy to misread as the login you targeted.
	return (
		"Granted role '%s' to character %s (#%d) on account @%s. "
		% [role, target.display_name, target.player_id, target.account_name]
		+ "Other characters on that account are unaffected."
	)


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
