extends ChatCommand
## Grant a donation-tier vanity title. Titles are character-bound; the player
## can display one on their profile and pin extras as trophies. Online only,
## same as /title — load the character if you need an offline grant later.
##
## TWO FAMILIES OF TIER, and they are granted differently.
##
##   [SupporterTitles] — the gem tiers and the custom gold one. Ordinary titles.
##       Adding them to titles_unlocked is the whole grant.
##   [TitleCatalog] ladder — Silver / Golden / Platinum / Diamond. These are
##       PREMIUM, which means CommandPermissions.strip_unreleased_vfx deletes
##       them from every non-staff player on every instance spawn. Adding one to
##       titles_unlocked and stopping there produces a title the donor wears
##       until their next zone change and then silently does not. So a ladder
##       grant ALSO records a [VaultGrants] entitlement, which is the one thing
##       the strip honours.
##
## That is the entire reason this command knows about the ladder at all: the
## vault shelf can already equip one on a staff account, but only a grant makes
## it stick on a player's.


func _init() -> void:
	command_name = "supporter"
	command_priority = 100 # senior_admin (matches /title)
	command_usage = "/supporter <self|Name|#id|@account> <tier>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage + "\nTiers:\n" + _all_tiers()

	var entry: Dictionary = SupporterTitles.resolve(args[2])
	# A ladder rung resolves through the catalog instead. Checked second so the
	# long-standing gem slugs always win a name collision.
	var ladder: Dictionary = _resolve_ladder(args[2]) if entry.is_empty() else {}
	if entry.is_empty() and ladder.is_empty():
		return "Unknown tier '%s'. Tiers:\n%s" % [args[2], _all_tiers()]

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var title: String = str((ladder if entry.is_empty() else entry).get("name", ""))
	var res: PlayerResource = target.resource
	if not ladder.is_empty():
		# The load-bearing line. Without it the strip takes this straight back.
		VaultGrants.grant_title(res, title)
	var already: bool = false
	for existing: String in res.titles_unlocked:
		if existing.to_lower() == title.to_lower():
			already = true
			break
	if not already:
		res.titles_unlocked.append(title)
	res.display_title = title
	var pnode: Player = server_instance.players_by_peer_id.get(target.peer_id, null)
	if pnode != null:
		pnode.display_title = title
		pnode.state_synchronizer.set_by_path(^":display_title", title)
	server_instance.world_server.database.save_player(res)

	var ws: WorldServer = server_instance.world_server
	ws.chat_service.push_system_to_player(
		server_instance,
		target.player_id,
		"You were granted the title %s. It shows over your name, on your profile, and in chat." % title
	)

	var extra: String = " (already unlocked)" if already else ""
	var kind: String = " [vault ladder — entitlement recorded]" if not ladder.is_empty() else ""
	return "Granted '%s' to %s%s.%s" % [title, target.label(), extra, kind]


## A ladder rung by slug ("diamond-donator"), by its tier key ("diamond"), or by
## display name ("Diamond Donator"). Empty when the token is not one of the four.
func _resolve_ladder(token: String) -> Dictionary:
	var needle: String = token.strip_edges().to_lower()
	if needle.is_empty():
		return {}
	for slug: String in TitleCatalog.vip_tier_slugs():
		var row: Dictionary = TitleCatalog.PREMIUM[slug]
		if needle == slug \
				or needle == str(row.get("vip_tier", "")) \
				or needle == str(row.get("name", "")).to_lower():
			return row
	return {}


func _all_tiers() -> String:
	var lines: PackedStringArray = PackedStringArray([SupporterTitles.usage_tiers()])
	for slug: String in TitleCatalog.vip_tier_slugs():
		var row: Dictionary = TitleCatalog.PREMIUM[slug]
		lines.append("%s = %s" % [str(row.get("vip_tier", "")), str(row.get("name", ""))])
	return "\n".join(lines)
