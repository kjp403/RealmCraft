extends ChatCommand
## Give an item to a player by item id OR slug (testing helper).
## Examples: /give self 51 10   |   /give self copper_ore 10


func _init() -> void:
	command_name = "give"
	command_priority = 2 # admin+ (testing / content QA — spawn items into bags)
	command_usage = "/give <self|@account|#id> <item_id|slug> [amount]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() < 3 or args.size() > 4:
		return "Usage: " + command_usage

	var target: CommandTarget.Result = CommandTarget.resolve(args[1], peer_id, server_instance)
	if not target.ok:
		return target.error
	if not target.online:
		return "%s must be online." % target.label()

	var amount: int = args[3].to_int() if args.size() == 4 else 1
	if amount <= 0:
		return "Invalid amount."

	var item: Item = null
	var token: String = args[2]
	if token.is_valid_int():
		item = ContentRegistryHub.load_by_id(&"items", token.to_int()) as Item
	else:
		item = ContentRegistryHub.load_by_slug(&"items", StringName(token)) as Item
	if item == null:
		return "No item matching '%s'." % token

	var item_id: int = int(item.get_meta(&"id", 0))
	if item_id <= 0:
		return "Item '%s' has no registry id." % token

	Inventory.add_item(target.resource.inventory, item_id, amount)
	ChatCommand.notify_inventory_changed(
		target.peer_id, item_id, amount, str(item.item_name)
	)
	return "Gave %d x %s (id %d) to %s." % [amount, str(item.item_name), item_id, target.label()]
