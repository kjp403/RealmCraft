extends ChatCommand
## Give an item to a player by item id OR slug (testing helper).
## Examples: /give self 51 10   |   /give self copper_ore 10
##           /give self wood_wand 1  |   /give self wand.item 1


## Friendly aliases → registry slug (wood starters use inconsistent slug styles).
const SLUG_ALIASES: Dictionary = {
	"wood_wand": "wand.item",
	"wooden_wand": "wand.item",
	"wand": "wand.item",
	"wood_sword": "sword.item",
	"wooden_sword": "sword.item",
	"sword": "sword.item",
	"wood_bow": "wooden_bow.item",
	"wooden_bow": "wooden_bow.item",
	"bow": "wooden_bow.item",
	"wood_hammer": "hammer.item",
	"wooden_hammer": "hammer.item",
	"hammer": "hammer.item",
	"wood_book": "book_wood.item",
	"wooden_book": "book_wood.item",
}


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

	var token: String = args[2]
	var item: Item = _resolve_item(token)
	if item == null:
		return "No item matching '%s'." % token

	var item_id: int = int(item.get_meta(&"id", 0))
	if item_id <= 0:
		return "Item '%s' has no registry id." % token

	Inventory.add_item(target.resource.inventory, item_id, amount)
	# Quiet pickup push → bag UIs refresh without spamming the loot feed.
	var target_peer: int = int(target.resource.current_peer_id)
	if target_peer > 0 and WorldServer.curr != null:
		WorldServer.curr.data_push.rpc_id(target_peer, &"item.picked_up", {
			"id": item_id,
			"amount": amount,
			"name": str(item.item_name),
			"quiet": true,
		})
	return "Gave %d x %s (id %d) to %s." % [amount, str(item.item_name), item_id, target.label()]


func _resolve_item(token: String) -> Item:
	if token.is_valid_int():
		return ContentRegistryHub.load_by_id(&"items", token.to_int()) as Item

	var item: Item = ContentRegistryHub.load_by_slug(&"items", StringName(token)) as Item
	if item != null:
		return item

	var key: String = token.to_lower()
	if SLUG_ALIASES.has(key):
		item = ContentRegistryHub.load_by_slug(&"items", StringName(str(SLUG_ALIASES[key]))) as Item
		if item != null:
			return item

	if not key.ends_with(".item"):
		item = ContentRegistryHub.load_by_slug(&"items", StringName(key + ".item")) as Item
		if item != null:
			return item

	# wood_wand → try wand / wand.item after stripping wood_/wooden_
	var stripped: String = key
	for prefix: String in ["wood_", "wooden_"]:
		if stripped.begins_with(prefix):
			stripped = stripped.substr(prefix.length())
			break
	if stripped != key:
		item = ContentRegistryHub.load_by_slug(&"items", StringName(stripped)) as Item
		if item != null:
			return item
		item = ContentRegistryHub.load_by_slug(&"items", StringName(stripped + ".item")) as Item
		if item != null:
			return item

	return _resolve_by_display_name(key)


## Match "wood wand" / "wood_wand" against item_name (case-insensitive).
func _resolve_by_display_name(token: String) -> Item:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"items")
	if registry == null:
		return null
	var needle: String = token.replace("_", " ").replace("-", " ").strip_edges().to_lower()
	if needle.is_empty():
		return null
	for id: int in registry.all_ids():
		var candidate: Item = ContentRegistryHub.load_by_id(&"items", id) as Item
		if candidate == null:
			continue
		var name_l: String = String(candidate.item_name).strip_edges().to_lower()
		if name_l == needle or name_l.replace(" ", "_") == token:
			return candidate
	return null
