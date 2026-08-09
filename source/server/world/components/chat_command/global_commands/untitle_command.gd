extends ChatCommand
## Remove a vanity title (or clear all) and unequip it if currently displayed.


func _init() -> void:
	command_name = "untitle"
	command_priority = 100 # senior_admin (matches /title)
	command_usage = "/untitle <self|@account|#id> <title|all>   (quote multi-word: \"Iron Warden\")"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 3:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	# Allow quoted multi-word titles spanning args[2..]: /untitle @x "Iron Warden".
	var title_token: String = args[2]
	if title_token.begins_with("\""):
		var pieces: PackedStringArray = [title_token.trim_prefix("\"")]
		for i in range(3, args.size()):
			if args[i].ends_with("\""):
				pieces.append(args[i].trim_suffix("\""))
				break
			pieces.append(args[i])
		title_token = " ".join(pieces)
	elif args.size() > 3:
		# Unquoted multi-word: /untitle self Iron Warden
		title_token = " ".join(args.slice(2))
	title_token = title_token.strip_edges()
	if title_token.is_empty():
		return "Usage: " + command_usage

	var res: PlayerResource = target.resource
	var titles: PackedStringArray = res.titles_unlocked.duplicate()
	if titles.is_empty():
		return "%s has no titles." % target.label()

	var clear_all: bool = title_token.to_lower() == "all"
	var removed: PackedStringArray = PackedStringArray()
	if clear_all:
		removed = titles.duplicate()
		titles.clear()
	else:
		var match_idx: int = -1
		for i: int in titles.size():
			if String(titles[i]).to_lower() == title_token.to_lower():
				match_idx = i
				break
		if match_idx < 0:
			return "%s does not have title '%s'." % [target.label(), title_token]
		removed.append(titles[match_idx])
		titles.remove_at(match_idx)

	res.titles_unlocked = titles

	# Unequip display title / trophies that were removed.
	var removed_lower: Dictionary = {}
	for t: String in removed:
		removed_lower[t.to_lower()] = true
	if not res.display_title.is_empty() and removed_lower.has(res.display_title.to_lower()):
		res.display_title = ""
	var kept_trophies: PackedStringArray = PackedStringArray()
	for t: String in res.displayed_trophies:
		if not removed_lower.has(String(t).to_lower()):
			kept_trophies.append(t)
	res.displayed_trophies = kept_trophies

	server_instance.world_server.database.save_player(res)

	if clear_all:
		return "Cleared all titles from %s (%d removed)." % [target.label(), removed.size()]
	return "Removed title '%s' from %s." % [removed[0], target.label()]
