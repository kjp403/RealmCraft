extends ChatCommand
## Admin+: destroy everything in YOUR OWN bags.
##
## /give fills a test loadout faster than any UI can clear it — thirty slots is
## thirty right-click-drops, each one a ground item the server then has to tick
## and despawn. This wipes them in one call.
##
## Three deliberate limits, because this destroys items outright with no undo:
##
##   SELF ONLY — no <self|@account|#id> token, unlike every other admin command
##     in this folder. A mistyped target on /give hands a stranger a free ore;
##     the same mistype here ends their bank run. There is no reason for staff
##     to need it on someone else, so the argument simply does not exist.
##   CONFIRM REQUIRED — a bare /empty reports what it WOULD destroy and changes
##     nothing. Costs one extra word to type and makes the wipe deliberate.
##   CURRENCY AND GEAR ARE KEPT — see [method ChatCommand.plan_container_wipe]
##     for the currency rule; worn gear is a separate field
##     ([member PlayerResource.equipment]) and is never read here.
##
## Items offered in a live trade are safe as well, though not by anything here:
## an offer is only moved on completion, and [TradeService] re-checks the bag
## then — a wiped offer fails the trade instead of duplicating anything.
##
## The vault has its own command, /emptybank, rather than a flag on this one:
## "empty" typed in a hurry should never be able to reach a bank.


func _init() -> void:
	command_name = "empty"
	command_priority = 2 # admin+ (destructive, but only ever to the caller)
	command_usage = "/empty [confirm]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	var confirmed: bool = args.size() == 2 and args[1].to_lower() == "confirm"
	if args.size() > 2 or (args.size() == 2 and not confirmed):
		return "Usage: " + command_usage

	var player: PlayerResource = server_instance.world_server.connected_players.get(peer_id)
	if player == null:
		return "You're not connected."

	var plan: Dictionary = ChatCommand.plan_container_wipe(player.inventory)
	var doomed: Array = plan["doomed"]
	if doomed.is_empty():
		return "Your bags are already empty." + ChatCommand.pouch_note(plan)

	if not confirmed:
		return "/empty would destroy %s.%s Run '/empty confirm' to do it." % [
			ChatCommand.describe_wipe(plan), ChatCommand.pouch_note(plan)
		]

	for slot_uid: Variant in doomed:
		player.inventory.erase(slot_uid)
	server_instance.world_server.database.save_player(player)
	ChatCommand.notify_inventory_refreshed(peer_id)
	return "Emptied your bags: destroyed %s.%s" % [
		ChatCommand.describe_wipe(plan), ChatCommand.pouch_note(plan)
	]
