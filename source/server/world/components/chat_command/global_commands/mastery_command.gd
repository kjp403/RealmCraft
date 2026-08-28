extends ChatCommand
## Set a weapon mastery level for testing. Omit level (or pass max/cap) to max it.
## `/mastery self all` maxes every weapon tree (sword / wand / bow / hammer / book).


func _init() -> void:
	command_name = "mastery"
	command_priority = 2 # admin+
	command_usage = "/mastery <self|@account|#id> <category|all> [level|max]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 3 or args.size() > 4:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var level: int = PlayerResource.MASTERY_LEVEL_CAP
	if args.size() == 4:
		level = _parse_level(args[3])
		if level < 1 or level > PlayerResource.MASTERY_LEVEL_CAP:
			return "Mastery level must be between 1 and %d (or 'max')." % PlayerResource.MASTERY_LEVEL_CAP

	var token: String = args[2].to_lower()
	var res: PlayerResource = target.resource
	var player: Player = CommandTarget.player_node(target, server_instance)

	if token == "all":
		var names: PackedStringArray = PackedStringArray()
		for category: StringName in MasteryService.trees():
			_set_mastery_level(res, category, level)
			var tree: MasteryTreeResource = MasteryService.tree_for(category)
			names.append(tree.display_name if tree != null and not tree.display_name.is_empty() else String(category))
			_push_mastery_toast(target, server_instance, category, level)
		if player != null:
			MasteryService.refresh(player)
		server_instance.world_server.database.save_player(res)
		return "Set all masteries for %s to level %d (%s)." % [
			target.label(), level, ", ".join(names)
		]

	var category: StringName = _resolve_category(StringName(token))
	if category == &"":
		return "Unknown mastery '%s'. Try: sword, wand, bow, hammer, book, or all." % args[2]

	_set_mastery_level(res, category, level)
	if player != null:
		MasteryService.refresh(player)
	_push_mastery_toast(target, server_instance, category, level)
	server_instance.world_server.database.save_player(res)

	var tree: MasteryTreeResource = MasteryService.tree_for(category)
	var label: String = tree.display_name if tree != null and not tree.display_name.is_empty() else String(category)
	return "Set %s %s mastery to level %d." % [target.label(), label, level]


func _parse_level(token: String) -> int:
	var lower: String = token.to_lower()
	if lower == "max" or lower == "cap":
		return PlayerResource.MASTERY_LEVEL_CAP
	return token.to_int()


func _resolve_category(token: StringName) -> StringName:
	if MasteryService.tree_for(token) != null:
		return token
	for category: StringName in MasteryService.trees():
		var tree: MasteryTreeResource = MasteryService.tree_for(category)
		if tree == null:
			continue
		if String(tree.display_name).to_lower() == String(token):
			return category
		if String(category) == String(token):
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


func _set_mastery_level(res: PlayerResource, category: StringName, level: int) -> void:
	var entry: Dictionary = res.get_mastery(category)
	entry["level"] = level
	entry["xp"] = 0
	# Keep the canonical StringName key so equip gates and mastery.get agree.
	res.masteries[StringName(String(category))] = entry
	var tree: MasteryTreeResource = MasteryService.tree_for(category)
	if tree != null:
		var budget: int = MasteryService.point_budget(level, tree)
		if MasteryService.spent_cost(entry, tree) > budget:
			entry["spent"] = {}


## Reuse the kill-reward mastery toast so the client bar/UI updates immediately.
func _push_mastery_toast(
	target: CommandTarget.Result,
	server_instance: ServerInstance,
	category: StringName,
	level: int
) -> void:
	if target.peer_id <= 0:
		return
	var mastery_payload: Dictionary = {
		"level": level,
		"xp": 0,
		"xp_to_next": target.resource.mastery_xp_to_next(level),
		"leveled_up": true,
		"started": true,
	}
	if category != &"":
		mastery_payload["category"] = String(category)
	server_instance.world_server.data_push.rpc_id(target.peer_id, &"combat.reward", {
		"xp": 0,
		"loot": [],
		"mastery": mastery_payload,
	})
