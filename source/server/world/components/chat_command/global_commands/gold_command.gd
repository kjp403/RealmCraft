extends ChatCommand
## Add gold to a player's inventory (testing / rewards).


func _init() -> void:
	command_name = "gold"
	command_priority = 2 # admin+ (matches /give — testing helper)
	command_usage = "/gold <self|@account|#id> <amount>"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() != 3:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var amount: int = args[2].to_int()
	if amount <= 0:
		return "Amount must be positive."

	var res: PlayerResource = target.resource
	var gold_id: int = Economy.gold_id()
	Inventory.add_item(res.inventory, gold_id, amount)
	server_instance.world_server.database.save_player(res)
	ChatCommand.notify_inventory_changed(target.peer_id, gold_id, amount, "Gold")
	return "Gave %d gold to %s. New balance: %d." % [
		amount, target.label(), Inventory.count(res.inventory, gold_id)
	]
