class_name CommandPermissions
## Central place that decides whether a player may run a chat command.
##
## A player's effective priority is the HIGHEST priority among:
##   - the roles persisted on THIS character (server_roles), and
##   - the role granted live via the admin config file (AdminConfig) for THIS
##     character's display name or #player_id.
## Other characters on the same login stay regular players. A command runs when
## its command_priority is <= that effective priority (command_priority <= 0
## means "anyone").
##
## LIVE hardening: owner / senior_admin can NEVER come from the DB — only from
## AdminConfig. That closes the old /selfadmin → autosave → permanent
## senior_admin persistence path even if a stale role row somehow remains.
##
## Rank ladder (priority): owner (1000) > senior_admin (100) > admin (2) > mod (1).
## Owners (KJP / kjp403 characters in server_admins.cfg) outrank every other staff tier.


## The highest role priority this character effectively has (commands + badge).
static func effective_priority(player: PlayerResource, instance: ServerInstance) -> int:
	if player == null:
		return -1

	var best: int = 0
	for role: String in player.server_roles:
		if _db_role_blocked(role):
			continue
		best = maxi(best, _role_priority(instance, role))

	# Live, non-persisted grant from the owner's admin config file — this
	# character only, never the whole login account.
	var config_role: String = AdminConfig.role_for_character(
		player.display_name, player.player_id
	)
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
	var config_role: String = AdminConfig.role_for_character(
		player.display_name, player.player_id
	)
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
## command-boosted characters don't crowd out regular players. Moderators (priority 1)
## still appear — they have no leveling commands. Regular alts on a staff login
## are not hidden.
const LEADERBOARD_HIDE_PRIORITY: int = 2 # admin


## If [param issuer] may not kick/ban/ipban [param target], return a player-facing
## error. Empty string means the action is allowed.
## Hierarchy: you may only punish targets with a *strictly lower* effective
## priority than yours. So:
##   - admin cannot punish admin / senior_admin / owner
##   - senior_admin cannot punish senior_admin / owner (can punish admin)
##   - owner (KJP / kjp403) can punish anyone below them, including malicious
##     senior_admins. Fellow owners (equal priority) remain protected.
## Ban/jail/ipban are account-wide, so a regular alt on a staff login is still
## protected — otherwise banning the alt would ban the staff character too.
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


## True when this character should be omitted from public leaderboards.
## Pass either a live PlayerResource or the offline account_name + roles dict.
## Config grants and persisted roles are character-scoped; [leaderboard_hide]
## still matches display name or an explicit account string.
static func is_hidden_from_leaderboard(
	account_name: String,
	roles: Dictionary,
	role_definitions: Dictionary,
	display_name: String = "",
	player_id: int = 0
) -> bool:
	# Count ALL persisted roles for hide — including live-blocked owner /
	# senior_admin. Those ranks no longer grant commands from the DB on LIVE,
	# but boosted staff chars must still stay off public boards.
	var best: int = 0
	for role: String in roles:
		best = maxi(best, int(role_definitions.get(role, {}).get("priority", 0)))
	if AdminConfig.is_leaderboard_hidden(account_name):
		return true
	if AdminConfig.is_leaderboard_hidden(display_name):
		return true
	var config_role: String = AdminConfig.role_for_character(display_name, player_id)
	if not config_role.is_empty():
		best = maxi(best, int(role_definitions.get(config_role, {}).get("priority", 0)))
	return best >= LEADERBOARD_HIDE_PRIORITY


## Effective priority for moderating an online or offline CommandTarget.
## Powers stay character-bound; protection is account-wide because mute/jail/ban
## hit the login, not just the targeted character.
static func effective_priority_for_target(
	target: CommandTarget.Result,
	instance: ServerInstance
) -> int:
	if target == null or not target.ok:
		return 0
	var best: int = 0
	if target.online and target.resource != null:
		best = effective_priority(target.resource, instance)
	else:
		var config_role: String = AdminConfig.role_for_character(
			target.display_name, target.player_id
		)
		if not config_role.is_empty():
			best = maxi(best, _role_priority(instance, config_role))

		var ws: WorldServer = instance.world_server
		if ws != null and ws.database != null and ws.database.store != null:
			if target.player_id > 0:
				best = maxi(best, _priority_from_roles_dict(
					ws.database.store.get_player_roles(target.player_id),
					instance
				))

	if not target.account_name.is_empty():
		best = maxi(best, _account_protect_priority(target.account_name, instance))
	return best


## Highest staff rank among every character on [param account_name] (DB roles +
## config grants). Used so you cannot ban a regular alt and take down a staff
## login with it.
static func _account_protect_priority(account_name: String, instance: ServerInstance) -> int:
	if account_name.is_empty() or instance == null:
		return 0
	var ws: WorldServer = instance.world_server
	if ws == null or ws.database == null or ws.database.store == null:
		return 0
	var best: int = ws.database.store.get_account_max_role_priority(
		account_name,
		instance.global_role_definitions
	)
	for ch: Dictionary in ws.database.store.get_account_characters(account_name):
		var cr: String = AdminConfig.role_for_character(
			str(ch.get("display_name", "")),
			int(ch.get("player_id", 0))
		)
		if not cr.is_empty():
			best = maxi(best, _role_priority(instance, cr))
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
