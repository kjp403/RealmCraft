class_name CommandPermissions
## Central place that decides whether a player may run a chat command.
##
## A player's effective priority is the HIGHEST priority among:
##   - the roles persisted on their PlayerResource (server_roles), and
##   - the role granted live via the admin config file (AdminConfig), if any.
## A command runs when its command_priority is <= that effective priority
## (command_priority <= 0 means "anyone").
##
## LIVE hardening: senior_admin can NEVER come from the DB — only from
## AdminConfig. That closes the old /selfadmin → autosave → permanent
## senior_admin persistence path even if a stale role row somehow remains.


## The highest role priority this player effectively has.
static func effective_priority(player: PlayerResource, instance: ServerInstance) -> int:
	if player == null:
		return -1

	var best: int = 0
	for role: String in player.server_roles:
		if _db_role_blocked(role):
			continue
		best = maxi(best, _role_priority(instance, role))

	# Live, non-persisted grant from the owner's admin config file.
	var config_role: String = AdminConfig.role_for(player.account_name)
	if not config_role.is_empty():
		best = maxi(best, _role_priority(instance, config_role))

	return best


## Highest-priority role name for badges / chat ("" = regular player).
## Maps senior_admin → "admin" so both use the Admin crown badge.
static func effective_role_slug(player: PlayerResource, instance: ServerInstance) -> String:
	if player == null or instance == null:
		return ""
	var best_priority: int = 0
	var best_role: String = ""
	for role: String in player.server_roles:
		if _db_role_blocked(role):
			continue
		var p: int = _role_priority(instance, role)
		if p > best_priority:
			best_priority = p
			best_role = role
	var config_role: String = AdminConfig.role_for(player.account_name)
	if not config_role.is_empty():
		var p: int = _role_priority(instance, config_role)
		if p > best_priority:
			best_priority = p
			best_role = config_role
	if best_role == "senior_admin":
		return "admin"
	if best_role in ["admin", "moderator"]:
		return best_role
	return ""


## Whether this player may run this command right now.
static func can_run(command: ChatCommand, player: PlayerResource, instance: ServerInstance) -> bool:
	if command == null or player == null:
		return false
	if command.command_priority <= 0:
		return true
	return command.command_priority <= effective_priority(player, instance)


static func _db_role_blocked(role: String) -> bool:
	# On live servers, DB-held senior_admin is ignored. Owner bootstrap is
	# AdminConfig-only. Local/dev keeps DB senior_admin for testing.
	if role == "senior_admin" and ServerEnvironment.is_live():
		return true
	return false


static func _role_priority(instance: ServerInstance, role: String) -> int:
	var role_data: Dictionary = instance.global_role_definitions.get(role, {})
	return int(role_data.get("priority", 0))
