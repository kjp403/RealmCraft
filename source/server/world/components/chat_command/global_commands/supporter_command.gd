extends ChatCommand
## Grant a donation-tier vanity title. Titles are character-bound; the player
## can display one on their profile and pin extras as trophies. Online only,
## same as /title — load the character if you need an offline grant later.


func _init() -> void:
	command_name = "supporter"
	command_priority = 100 # senior_admin (matches /title)
	command_usage = "/supporter <self|Name|#id|@account> <tier>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage + "\nTiers:\n" + SupporterTitles.usage_tiers()

	var entry: Dictionary = SupporterTitles.resolve(args[2])
	if entry.is_empty():
		return "Unknown tier '%s'. Tiers:\n%s" % [args[2], SupporterTitles.usage_tiers()]

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var title: String = str(entry.get("name", ""))
	var res: PlayerResource = target.resource
	var already: bool = false
	for existing: String in res.titles_unlocked:
		if existing.to_lower() == title.to_lower():
			already = true
			break
	if not already:
		res.titles_unlocked.append(title)
	res.display_title = title
	server_instance.world_server.database.save_player(res)

	var ws: WorldServer = server_instance.world_server
	ws.chat_service.push_system_to_player(
		server_instance,
		target.player_id,
		"You were granted the title %s. It's shown on your profile." % title
	)

	var extra: String = " (already unlocked)" if already else ""
	return "Granted '%s' to %s%s." % [title, target.label(), extra]
