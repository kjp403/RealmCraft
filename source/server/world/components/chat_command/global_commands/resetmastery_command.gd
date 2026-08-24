extends ChatCommand
## Force-wipe a player's mastery spend (and loadout picks) for free, no gold cost.
## Staff tool for correcting stuck/bugged mastery state (e.g. a character sitting on
## legacy stat leakage from a fixed passive-stacking bug) without waiting on the
## player to afford/perform their own respec. Mirrors the in-game respec
## (MasteryService.reset) but skips MasteryResetInteraction.COST and works on any
## online player.


func _init() -> void:
	command_name = "resetmastery"
	command_priority = 100 # senior_admin+ (irreversible spend wipe, matches /resetstats)
	command_usage = "/resetmastery <self|@account|#id> [category|all]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 2 or args.size() > 3:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var token: String = (args[2] if args.size() == 3 else "all").to_lower()
	var res: PlayerResource = target.resource
	var player: Player = CommandTarget.player_node(target, server_instance)

	var names: PackedStringArray = PackedStringArray()
	if token == "all":
		for category: StringName in MasteryService.trees():
			if MasteryService.reset(res, category).get("ok", false):
				names.append(String(category))
	else:
		var category: StringName = _resolve_category(StringName(token))
		if category == &"":
			return "Unknown mastery '%s'. Try: sword, wand, bow, hammer, book, or all." % args[2]
		if not MasteryService.reset(res, category).get("ok", false):
			return "%s has nothing spent in %s." % [target.label(), String(category)]
		names.append(String(category))

	if names.is_empty():
		return "%s has nothing spent to reset." % target.label()

	if player != null:
		MasteryService.refresh(player)
	server_instance.world_server.database.save_player(res)
	ServerLog.info("Admin (peer %d) reset mastery for %s: %s" % [peer_id, target.label(), ", ".join(names)])
	return "Reset mastery for %s: %s." % [target.label(), ", ".join(names)]


func _resolve_category(token: StringName) -> StringName:
	if MasteryService.tree_for(token) != null:
		return token
	for category: StringName in MasteryService.trees():
		var tree: MasteryTreeResource = MasteryService.tree_for(category)
		if tree == null:
			continue
		if String(tree.display_name).to_lower() == String(token):
			return category
	match String(token):
		"magic", "arcane", "arcanist":
			return &"wand" if MasteryService.tree_for(&"wand") != null else &""
		"archery", "archer":
			return &"bow" if MasteryService.tree_for(&"bow") != null else &""
		"heavy", "heavies":
			return &"hammer" if MasteryService.tree_for(&"hammer") != null else &""
		"battlemage", "mage":
			return &"book" if MasteryService.tree_for(&"book") != null else &""
		_:
			return &""
