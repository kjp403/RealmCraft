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


## Instance-free variant of [method effective_priority], for gates that run before a
## ServerInstance is in hand — notably InstanceResource.can_join_instance, which only
## receives the Player. Role priorities live in a STATIC table
## (ServerInstance.global_role_definitions), so the instance was only ever a lookup
## vehicle: this returns the same number, including the live owner/senior_admin DB
## block and the AdminConfig grant.
static func effective_priority_global(player: PlayerResource) -> int:
	if player == null:
		return -1

	var best: int = 0
	for role: String in player.server_roles:
		if _db_role_blocked(role):
			continue
		best = maxi(best, _global_role_priority(role))

	var config_role: String = AdminConfig.role_for_character(
		player.display_name, player.player_id
	)
	if not config_role.is_empty():
		best = maxi(best, _global_role_priority(config_role))

	return best


## Hard floor so a missing/empty role table cannot turn owner into priority 0
## ("Command not found" for every staff command). Table values still win if higher.
const ROLE_PRIORITY_FALLBACK: Dictionary = {
	"owner": 1000,
	"senior_admin": 100,
	"admin": 2,
	"moderator": 1,
}


static func _priority_of(role: String, table: Dictionary) -> int:
	var from_table: int = int(table.get(role, {}).get("priority", 0))
	return maxi(from_table, int(ROLE_PRIORITY_FALLBACK.get(role, 0)))


static func _global_role_priority(role: String) -> int:
	return _priority_of(role, ServerInstance.global_role_definitions)


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
## Every input is CHARACTER-scoped: this character's own persisted [param roles],
## its config grant, and its display name in [leaderboard_hide]. Staff are meant
## to play regular alts and appear on the boards with them, so nothing here keys
## off the login — an alt is judged only by what that character itself holds.
static func is_hidden_from_leaderboard(
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
		best = maxi(best, _priority_of(role, role_definitions))
	if AdminConfig.is_leaderboard_hidden(display_name):
		return true
	var config_role: String = AdminConfig.role_for_character(display_name, player_id)
	if not config_role.is_empty():
		best = maxi(best, _priority_of(config_role, role_definitions))
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
	# Existing API: { player_id: { "name": display_name, ... } }
	var chars: Dictionary = ws.database.store.get_account_characters(account_name)
	for pid: int in chars:
		var info: Dictionary = chars[pid]
		var cr: String = AdminConfig.role_for_character(str(info.get("name", "")), pid)
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
	if instance == null:
		return int(ROLE_PRIORITY_FALLBACK.get(role, 0))
	return _priority_of(role, instance.global_role_definitions)


## Drop unreleased vault VFX from a non-staff character (prestige skin, auras,
## premium titles). Called on spawn so a demoted admin cannot walk the live
## world still wearing them. Returns true when anything was cleared.
static func strip_unreleased_vfx(player: PlayerResource, instance: ServerInstance) -> bool:
	if player == null:
		return false
	if effective_priority(player, instance) >= STAFF_PROTECT_PRIORITY:
		return false
	var changed: bool = false
	# GRANTED cosmetics survive. Everything else here is a leak by definition -
	# this set is unreleased - but a vault skin or a ladder title handed to a donor
	# by an admin is not a leak, and wiping it on their next zone change is how a
	# gift silently becomes a support ticket. See [VaultGrants]; that list is
	# written by admin-gated commands and by nothing else, which is what makes it
	# safe to trust here.
	if player.vault_skin_id != 0 and not VaultGrants.has_skin(player, player.vault_skin_id):
		player.vault_skin_id = 0
		changed = true
	if player.cosmetic_id != 0:
		player.cosmetic_id = 0
		changed = true
	if player.weapon_cosmetic_id != 0:
		player.weapon_cosmetic_id = 0
		changed = true
	if TitleCatalog.is_premium_name(player.display_title) \
			and not VaultGrants.has_title(player, player.display_title):
		player.display_title = ""
		changed = true
	var kept_titles: PackedStringArray = PackedStringArray()
	var dropped_premium: bool = false
	for t: String in player.titles_unlocked:
		if TitleCatalog.is_premium_name(t) and not VaultGrants.has_title(player, t):
			dropped_premium = true
			continue
		kept_titles.append(t)
	if dropped_premium:
		player.titles_unlocked = kept_titles
		changed = true
	var kept_trophies: PackedStringArray = PackedStringArray()
	var dropped_trophy: bool = false
	for t: String in player.displayed_trophies:
		if TitleCatalog.is_premium_name(t) and not VaultGrants.has_title(player, t):
			dropped_trophy = true
			continue
		kept_trophies.append(t)
	if dropped_trophy:
		player.displayed_trophies = kept_trophies
		changed = true
	return changed
