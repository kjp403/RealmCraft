extends ChatCommand
## Admin+: destroy everything in YOUR OWN bank vault. The /empty rules, applied
## to the other container — self only, confirm required, currency kept.
##
## Its own command rather than a flag on /empty ("/empty bank") on purpose: a
## vault holds a test account's whole history, and the argument that reaches it
## should not be one typo away from the argument that empties a bag. The confirm
## word itself is deliberately the same one /empty uses — one habit for both,
## rather than a second token to misremember in front of a full vault.
##
## A bank slot should never hold currency (bank.get moves stray stacks back to
## the pouch on every open), but the shared planner keeps it anyway rather than
## relying on that being true.
##
## The bank UI reads its rows once, when it becomes visible, and takes no server
## push — so a bank window that is already open keeps drawing the old vault
## until it is reopened. The reply says so rather than leaving staff to wonder
## whether the command ran.


func _init() -> void:
	command_name = "emptybank"
	command_priority = 2 # admin+, same as /empty
	command_usage = "/emptybank [confirm]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	var confirmed: bool = args.size() == 2 and args[1].to_lower() == "confirm"
	if args.size() > 2 or (args.size() == 2 and not confirmed):
		return "Usage: " + command_usage

	var player: PlayerResource = server_instance.world_server.connected_players.get(peer_id)
	if player == null:
		return "You're not connected."

	var plan: Dictionary = ChatCommand.plan_container_wipe(player.bank)
	var doomed: Array = plan["doomed"]
	if doomed.is_empty():
		return "Your bank is already empty." + ChatCommand.pouch_note(plan)

	if not confirmed:
		return "/emptybank would destroy %s.%s Run '/emptybank confirm' to do it." % [
			ChatCommand.describe_wipe(plan), ChatCommand.pouch_note(plan)
		]

	for slot_uid: Variant in doomed:
		player.bank.erase(slot_uid)
	server_instance.world_server.database.save_player(player)
	return "Emptied your bank: destroyed %s.%s Reopen the bank window to refresh it." % [
		ChatCommand.describe_wipe(plan), ChatCommand.pouch_note(plan)
	]
