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
##     nothing. Costs one extra line to type and makes the wipe deliberate.
##   CURRENCY IS KEPT — gold lives in the pouch, not a bag square (see
##     [method Inventory.counts_toward_capacity]), so "empty your inventory"
##     never quietly means "and your gold". Worn gear is a separate field
##     ([member PlayerResource.equipment]) and is untouched for the same reason.
##
## Items offered in a live trade are safe as well, though not by anything here:
## an offer is only moved on completion, and [TradeService] re-checks the bag
## then — a wiped offer fails the trade instead of duplicating anything.

## How many stacks the preview names before it summarises the rest.
const PREVIEW_STACKS: int = 5


func _init() -> void:
	command_name = "empty"
	command_priority = 2 # admin+ (destructive, but only ever to the caller)
	command_usage = "/empty [confirm]"


func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	if args.size() > 2:
		return "Usage: " + command_usage
	var confirmed: bool = args.size() == 2 and args[1].to_lower() == "confirm"
	if args.size() == 2 and not confirmed:
		return "Usage: " + command_usage

	var player: PlayerResource = server_instance.world_server.connected_players.get(peer_id)
	if player == null:
		return "You're not connected."

	var plan: Dictionary = plan_wipe(player.inventory)
	var doomed: Array = plan["doomed"]
	var stacks: int = int(plan["stacks"])
	var items: int = int(plan["items"])
	var kept_currency: int = int(plan["kept_currency"])
	var preview: PackedStringArray = plan["preview"]

	if doomed.is_empty():
		return "Your bags are already empty." + _pouch_note(kept_currency)

	var summary: String = ", ".join(preview)
	if stacks > preview.size():
		summary += " and %d more" % (stacks - preview.size())

	if not confirmed:
		return "/empty would destroy %d stack%s (%d item%s): %s.%s Run '/empty confirm' to do it." % [
			stacks, "" if stacks == 1 else "s",
			items, "" if items == 1 else "s",
			summary,
			_pouch_note(kept_currency),
		]

	for slot_uid: Variant in doomed:
		player.inventory.erase(slot_uid)
	server_instance.world_server.database.save_player(player)
	ChatCommand.notify_inventory_refreshed(peer_id)
	return "Emptied your bags: destroyed %d stack%s (%d item%s).%s" % [
		stacks, "" if stacks == 1 else "s",
		items, "" if items == 1 else "s",
		_pouch_note(kept_currency),
	]


## Decide what a wipe would take, without taking it.
##
## Split out of [method execute] so the dry run and the wipe can never disagree
## about what "empty" means, and so the rule can be exercised against a
## synthetic bag without standing up a server.
##
## Returns {doomed: Array[slot_uid], stacks: int, items: int,
## kept_currency: int, preview: PackedStringArray}.
static func plan_wipe(inventory: Dictionary) -> Dictionary:
	var doomed: Array = []
	var stacks: int = 0
	var items: int = 0
	var kept_currency: int = 0
	var preview: PackedStringArray = PackedStringArray()
	for slot_uid: Variant in inventory:
		var slot: Dictionary = inventory[slot_uid]
		var amount: int = int(slot.get("a", 0))
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(slot.get("id", 0))) as Item
		# An item whose registry entry has gone away is exactly the junk this
		# command is for, so a null lookup is destroyed rather than kept.
		if item != null and item.is_currency:
			kept_currency += amount
			continue
		doomed.append(slot_uid)
		stacks += 1
		items += amount
		if preview.size() < PREVIEW_STACKS:
			preview.append("%s x%d" % [
				str(item.item_name) if item != null else "Unknown item", amount
			])
	return {
		"doomed": doomed,
		"stacks": stacks,
		"items": items,
		"kept_currency": kept_currency,
		"preview": preview,
	}


## " Kept 4,210 currency in the pouch." — or nothing when there is none, so the
## common case doesn't carry a sentence about zero gold.
func _pouch_note(kept_currency: int) -> String:
	if kept_currency <= 0:
		return ""
	return " Kept %d currency in the pouch." % kept_currency
