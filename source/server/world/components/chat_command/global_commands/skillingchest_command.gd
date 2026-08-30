extends ChatCommand
## Grant a Daily Skilling Chest directly, without a board claim.
##
## The skilling chests are the only chests in the game that are not objects:
## there is no ChestResource and no item, just a tier spec in
## [constant SkillingChestRewarder.TIERS] rolled at claim time. So they cannot
## be handed over with /give or /chest — the only way to produce one is to call
## the same [method SkillingChestRewarder.grant] a real claim calls, which is
## what this does.
##
## Use it to restore chests a player earned but lost to a bug. It rolls fresh,
## so the package is authentic (banded draws, gem roll, outfit roll) rather than
## a hand-picked pile, and it stages into pending_chest_loot exactly like the
## board does — a full bag defers the haul instead of voiding it.
##
## Examples: /skillingchest @kyle mining 3   |   /skillingchest self fishing 3 2


## Chests granted in one invocation. A restore is a handful; the cap only exists
## so a typo in the count cannot dump a hundred rolls into someone's staging.
const MAX_COUNT: int = 10


func _init() -> void:
	command_name = "skillingchest"
	command_priority = 2 # admin+ (matches /give — grants real reward value)
	command_usage = "/skillingchest <self|@account|#id> <skill> <1-3> [count]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 4 or args.size() > 5:
		return "Usage: " + command_usage + "\nSkills: " + _skill_list()

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		# grant() needs the live Player node (the outfit roll reads owned pieces
		# off it), so this cannot be done against a DB-only target.
		return "%s must be online." % target.label()

	# Slugs, not display names — Crafting is "outfitting" and Farming is
	# "harvesting". Validated against POOLS rather than JobRegistry because a
	# skill with no authored pool would return ok:false and grant nothing.
	var skill: StringName = StringName(args[2].strip_edges().to_lower())
	if not SkillingChestRewarder.POOLS.has(skill):
		return "Unknown skill '%s'. Skills: %s" % [String(skill), _skill_list()]

	# Typed 1-3 to match what players see on the board; TIERS is 0-indexed.
	var tier: int = args[3].to_int()
	if tier < 1 or tier > SkillingChestRewarder.TIERS.size():
		return "Difficulty must be 1-3 (3 = Greater)."
	var difficulty: int = tier - 1

	var count: int = args[4].to_int() if args.size() == 5 else 1
	if count < 1 or count > MAX_COUNT:
		return "Count must be 1-%d." % MAX_COUNT

	var player: Player = server_instance.players_by_peer_id.get(target.peer_id, null)
	if player == null:
		return "Couldn't locate %s in this instance." % target.label()

	var chest_name: String = str(SkillingChestRewarder.TIERS[difficulty]["name"])
	var total_gold: int = 0
	var outfits: int = 0
	for i: int in count:
		var chest: Dictionary = SkillingChestRewarder.grant(player, skill, difficulty)
		if not bool(chest.get("ok", false)):
			return "Grant failed: %s." % str(chest.get("reason", "unknown"))
		total_gold += int(chest.get("gold", 0))
		if not (chest.get("outfit", {}) as Dictionary).is_empty():
			outfits += 1
		# Same push a real chest open sends. grant()'s payload already carries
		# the keys the reward window reads, so the player gets the normal window
		# instead of silently finding loot in staging later.
		if WorldServer.curr != null:
			WorldServer.curr.data_push.rpc_id(target.peer_id, &"chest.opened", chest)

	server_instance.world_server.database.save_player(target.resource)

	var extra: String = " %d outfit piece(s)!" % outfits if outfits > 0 else ""
	return "Gave %d x %s (%s) to %s. %d gold, items staged for claim.%s" % [
		count, chest_name, JobRegistry.display_name(skill),
		target.label(), total_gold, extra
	]


func _skill_list() -> String:
	var names: PackedStringArray = []
	for slug: StringName in SkillingChestRewarder.POOLS:
		names.append(String(slug))
	return ", ".join(names)
