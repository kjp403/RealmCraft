class_name ChatCommand
extends RefCounted


var command_name: String = ""
var command_alias: PackedStringArray = []
var command_priority: int = 0
## One-line usage string, e.g. "/heal <self|@account|#id> <amount>". Set in
## _init(); commands return it on a malformed call AND /help <name> prints it, so
## the format lives in exactly one place. Empty falls back to "/<name>".
var command_usage: String = ""


@warning_ignore("unused_parameter")
func execute(args: PackedStringArray, peer_id: int, server_instance: ServerInstance) -> String:
	return "Unknown command."


## Tell the target's client their bag changed (currency pouch / inventory dock).
## Quiet = no left-side LootFeed pill — used by /give and /gold.
static func notify_inventory_changed(
	peer_id: int,
	item_id: int,
	amount: int,
	item_name: String
) -> void:
	if peer_id <= 0 or WorldServer.curr == null:
		return
	var multiplayer_api: MultiplayerAPI = WorldServer.curr.multiplayer
	if multiplayer_api == null or not multiplayer_api.has_multiplayer_peer():
		return
	if peer_id not in multiplayer_api.get_peers():
		return
	WorldServer.curr.data_push.rpc_id(peer_id, &"item.picked_up", {
		"id": item_id,
		"amount": amount,
		"name": item_name,
		"quiet": true,
	})


## How many stacks a wipe preview names before it summarises the rest.
const WIPE_PREVIEW_STACKS: int = 5


## Decide what wiping [param container] (a bag or a bank, both the same
## { slot_uid: {id, a, ...} } shape) would take, without taking it.
##
## Shared by /empty and /emptybank, and separate from the wipe itself, so that
## the dry run and the deletion can never disagree about what "empty" means and
## so the rule can be exercised against a synthetic container without standing
## up a server.
##
## Currency is KEPT: gold belongs to the pouch, not a slot (see
## [method Inventory.counts_toward_capacity]), and bank.get moves any stray
## currency stack back there on the next open anyway. An item whose registry
## entry has gone away is exactly the junk these commands are for, so a null
## lookup is destroyed rather than kept.
##
## Returns {doomed: Array[slot_uid], stacks: int, items: int,
## kept_currency: int, preview: PackedStringArray}.
static func plan_container_wipe(container: Dictionary) -> Dictionary:
	var doomed: Array = []
	var stacks: int = 0
	var items: int = 0
	var kept_currency: int = 0
	var preview: PackedStringArray = PackedStringArray()
	for slot_uid: Variant in container:
		var slot: Dictionary = container[slot_uid]
		var amount: int = int(slot.get("a", 0))
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(slot.get("id", 0))) as Item
		if item != null and item.is_currency:
			kept_currency += amount
			continue
		doomed.append(slot_uid)
		stacks += 1
		items += amount
		if preview.size() < WIPE_PREVIEW_STACKS:
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


## One line describing a finished or proposed wipe: "7 stacks (30 items):
## Copper Ore x5, ... and 2 more". Shared so /empty and /emptybank read
## identically in chat.
static func describe_wipe(plan: Dictionary) -> String:
	var stacks: int = int(plan.get("stacks", 0))
	var items: int = int(plan.get("items", 0))
	var preview: PackedStringArray = plan.get("preview", PackedStringArray())
	var summary: String = ", ".join(preview)
	if stacks > preview.size():
		summary += " and %d more" % (stacks - preview.size())
	return "%d stack%s (%d item%s): %s" % [
		stacks, "" if stacks == 1 else "s",
		items, "" if items == 1 else "s",
		summary,
	]


## " Kept 4,210 currency in the pouch." — or nothing when there is none, so the
## common case doesn't carry a sentence about zero gold.
static func pouch_note(plan: Dictionary) -> String:
	var kept: int = int(plan.get("kept_currency", 0))
	if kept <= 0:
		return ""
	return " Kept %d currency in the pouch." % kept


## Tell the target's client to re-read its bag, with no LootFeed pill.
##
## [method notify_inventory_changed]'s payload is shaped like a PICKUP, and the
## client turns any non-zero id/amount pair into a "+N item" pill — which would
## announce a wipe as a gain. Zeroes clear that gate on the client
## ([method ClientState._on_item_picked_up]) while still emitting
## inventory_changed, so an open bag redraws and nothing is claimed.
static func notify_inventory_refreshed(peer_id: int) -> void:
	notify_inventory_changed(peer_id, 0, 0, "")


## Parse a duration token like "30s", "10m", "2h", "1d" into milliseconds.
## Returns 0 if the input is empty or has no valid unit suffix — callers use
## that as the "no duration / treat as reason instead" sentinel. Bare numbers
## (no suffix) return 0 on purpose so "/mute 1042 spam" can't be misread as a
## duration when the reason starts with digits.
static func parse_duration_ms(s: String) -> int:
	if s.length() < 2:
		return 0
	var lower: String = s.to_lower()
	var suffix: String = lower.right(1)
	var unit_ms: int = 0
	match suffix:
		"s": unit_ms = 1000
		"m": unit_ms = 60 * 1000
		"h": unit_ms = 60 * 60 * 1000
		"d": unit_ms = 24 * 60 * 60 * 1000
		_: return 0
	var numeric: String = lower.left(lower.length() - 1)
	if not numeric.is_valid_int():
		return 0
	var n: int = numeric.to_int()
	if n <= 0:
		return 0
	return n * unit_ms
