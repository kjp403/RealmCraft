class_name CommandPermissions
## Central place that decides whether a player may run a chat command.
##
## A player's effective priority is the HIGHEST priority among:
##   - the roles persisted on their PlayerResource (server_roles), and
##   - the role granted live via the admin config file (AdminConfig), if any.
## A command runs when its command_priority is <= that effective priority
## (command_priority <= 0 means "anyone").
##
## LIVE hardening: owner / senior_admin can NEVER come from the DB — only from
## AdminConfig. That closes the old /selfadmin → autosave → permanent
## senior_admin persistence path even if a stale role row somehow remains.
##
## Rank ladder (priority): owner (1000) > senior_admin (100) > admin (2) > mod (1).
## Owners (kjp403 / KJP in server_admins.cfg) outrank every other staff tier.


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
## Maps owner / senior_admin → "admin" so all top staff use the Admin crown badge.
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
	if best_role in ["owner", "senior_admin"]:
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


## Admin priority floor — anyone at or above this is protected staff.
const STAFF_PROTECT_PRIORITY: int = 2 # admin

## Admin+ (admin / senior_admin / owner) are hidden from player leaderboards so
## command-boosted accounts don't crowd out regular players. Moderators (priority 1)
## still appear — they have no leveling commands.
const LEADERBOARD_HIDE_PRIORITY: int = 2 # admin


## If [param issuer] may not kick/ban/ipban [param target], return a player-facing
## error. Empty string means the action is allowed.
## Hierarchy: you may only punish targets with a *strictly lower* effective
## priority than yours. So:
##   - admin cannot punish admin / senior_admin / owner
##   - senior_admin cannot punish senior_admin / owner (can punish admin)
##   - owner (kjp403 / KJP) can punish anyone below them, including malicious
##     senior_admins. Fellow owners (equal priority) remain protected.
static func staff_moderation_block_reason(
	issuer: PlayerResource,
	target: CommandTarget.Result,
	instance: ServerInstance
) -> String:
	if issuer == null or target == null or not target.ok or instance == null:
		return ""
	var issuer_p: int = effective_priority(issuer, instance)
	var target_p: int = effective_priority_for_target(target, instance)
	if target_p < STAFF_PROTECT_PRIORITY:
		return ""
	if issuer_p > target_p:
		return ""
	if target_p >= 1000:
		return "You can't moderate the server owner."
	if target_p >= 100:
		return "You can't moderate a senior admin."
	return "You can't moderate another admin (or higher)."


## True when this account/roles should be omitted from public leaderboards.
## Pass either a live PlayerResource or the offline account_name + roles dict.
## [param display_name] is optional — used so character names listed in
## server_admins.cfg (or [leaderboard_hide]) still drop off boards even when
## the login account string differs.
static func is_hidden_from_leaderboard(
	account_name: String,
	roles: Dictionary,
	role_definitions: Dictionary,
	display_name: String = ""
) -> bool:
	# Count ALL persisted roles for hide — including live-blocked owner /
	# senior_admin. Those ranks no longer grant commands from the DB on LIVE,
	# but boosted staff chars must still stay off public boards.
	var best: int = 0
	for role: String in roles:
		best = maxi(best, int(role_definitions.get(role, {}).get("priority", 0)))
	for key: String in [account_name, display_name]:
		if key.is_empty():
			continue
		if AdminConfig.is_leaderboard_hidden(key):
			return true
		var config_role: String = AdminConfig.role_for(key)
		if not config_role.is_empty():
			best = maxi(best, int(role_definitions.get(config_role, {}).get("priority", 0)))
	return best >= LEADERBOARD_HIDE_PRIORITY


## Effective priority for an online or offline CommandTarget (AdminConfig + DB roles).
static func effective_priority_for_target(
	target: CommandTarget.Result,
	instance: ServerInstance
) -> int:
	if target == null or not target.ok:
		return 0
	if target.online and target.resource != null:
		return effective_priority(target.resource, instance)

	var best: int = 0
	var config_role: String = AdminConfig.role_for(target.account_name)
	if not config_role.is_empty():
		best = maxi(best, _role_priority(instance, config_role))

	var ws: WorldServer = instance.world_server
	if ws == null or ws.database == null or ws.database.store == null:
		return best

	if target.player_id > 0:
		best = maxi(best, _priority_from_roles_dict(
			ws.database.store.get_player_roles(target.player_id),
			instance
		))
	elif not target.account_name.is_empty():
		best = maxi(best, ws.database.store.get_account_max_role_priority(
			target.account_name,
			instance.global_role_definitions
		))
	return best


static func _priority_from_roles_dict(roles: Dictionary, instance: ServerInstance) -> int:
	var best: int = 0
	for role: String in roles:
		if _db_role_blocked(role):
			continue
		best = maxi(best, _role_priority(instance, role))
	return best


static func _db_role_blocked(role: String) -> bool:
	# On live servers, DB-held owner/senior_admin is ignored. Those ranks are
	# AdminConfig-only. Local/dev keeps them for testing.
	if role in ["owner", "senior_admin"] and ServerEnvironment.is_live():
		return true
	return false


static func _role_priority(instance: ServerInstance, role: String) -> int:
	var role_data: Dictionary = instance.global_role_definitions.get(role, {})
	return int(role_data.get("priority", 0))
