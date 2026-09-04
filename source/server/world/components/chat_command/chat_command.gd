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
