extends DataRequestHandler
## Open several [LootChestItem]s of the SAME type in one request.
## Args: { "id": item_id, "count": int } — count -1 (or 0) means "all you hold".
##
## WHY A BATCH HANDLER RATHER THAN N CALLS TO chest.open_item
## Opening 200 caskets as 200 round trips is 200 rolls interleaved with 200
## `save_player` writes and 200 `chest.opened` pushes, and the client cannot
## render a coherent total until the last one lands. Here the whole run happens
## inside one tick, saves once at the end, and returns a MERGED ledger the reward
## window can show immediately.
##
## Each chest is still rolled independently — this is a loop over the same
## [method ChestResource.roll_and_grant] a single open uses, not a multiplied
## single roll. Batch-opening must never be luckier or unluckier per chest than
## opening them one at a time.
##
## Loot stages in [member PlayerResource.pending_chest_loot], which is unbounded,
## so a batch cannot fail part-way for want of bag space. Overflow is a CLAIM-time
## concern and `chest.loot_bank` already cascades bank -> bag -> ground.

## Hard ceiling on one request. A player holding thousands of caskets must not be
## able to ask the world server to roll all of them inside a single frame; the
## client re-requests until `remaining` reaches 0, so "Open All" still finishes,
## just in chunks that keep the tick responsive.
const MAX_PER_REQUEST: int = 50


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "player"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var item_id: int = int(args.get("id", 0))
	if item_id <= 0:
		return {"ok": false, "reason": "missing"}

	var chest_item: LootChestItem = ContentRegistryHub.load_by_id(
		&"items", item_id
	) as LootChestItem
	if chest_item == null:
		return {"ok": false, "reason": "not_chest"}
	var table: ChestResource = chest_item.resolve_table()
	if table == null:
		return {"ok": false, "reason": "missing"}

	var resource: PlayerResource = player.player_resource
	var held: int = Inventory.count(resource.inventory, item_id)
	if held <= 0:
		return {"ok": false, "reason": "missing"}

	# count <= 0 means "all". Clamped to what they actually hold AND to the
	# per-request ceiling.
	var requested: int = int(args.get("count", 1))
	var want: int = held if requested <= 0 else mini(requested, held)
	want = mini(want, MAX_PER_REQUEST)

	var gold: int = 0
	var ledger: Dictionary[int, Dictionary] = {}
	var opened: int = 0
	for _i: int in want:
		# Spend the chest BEFORE granting, every iteration, so a mid-loop failure
		# can never duplicate loot — same ordering chest.open_item uses.
		if not Inventory.remove_amount_by_id(resource.inventory, item_id, 1):
			break
		var payout: Dictionary = table.roll_and_grant(player)
		opened += 1
		gold += int(payout.get("gold", 0))
		_merge(ledger, payout.get("items", []))

	if opened <= 0:
		return {"ok": false, "reason": "missing"}

	# One write for the whole run rather than one per chest.
	instance.world_server.database.save_player(resource)

	var items: Array = ledger.values()
	var remaining: int = Inventory.count(resource.inventory, item_id)
	var payload: Dictionary = {
		"ok": true,
		"chest": str(chest_item.item_name),
		"chest_id": item_id,
		"opened": opened,
		# What is LEFT of this chest type. "Open All" loops on this rather than on
		# a count the client tracked itself, so a stack that changed underneath
		# (a trade, another window) cannot make the client ask for chests that
		# are no longer there.
		"remaining": remaining,
		"gold": gold,
		"items": items,
		"pending": PendingChestLoot.to_payload(resource.pending_chest_loot),
		"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
	}

	# Pushed as well as returned: the push is what keeps a SECOND open window
	# (or the loot feed) in step, and it is the same key a single open uses.
	if peer_id > 0 and WorldServer.curr != null:
		WorldServer.curr.data_push.rpc_id(peer_id, &"chest.opened", payload)
	return payload


## Fold one open's items into the running ledger, summing amounts per item and
## keeping the LOUDEST rarity seen for that item — one ultra roll in fifty opens
## has to survive into the summary, or batching would hide the drop it exists to
## celebrate.
static func _merge(ledger: Dictionary[int, Dictionary], items: Variant) -> void:
	if items is not Array:
		return
	for entry_v: Variant in (items as Array):
		if entry_v is not Dictionary:
			continue
		var entry: Dictionary = entry_v
		var id: int = int(entry.get("id", 0))
		var amount: int = int(entry.get("amount", 0))
		if id <= 0 or amount <= 0:
			continue
		if not ledger.has(id):
			ledger[id] = {
				"id": id,
				"amount": 0,
				"name": str(entry.get("name", "Item")),
				"rarity": str(entry.get("rarity", "common")),
			}
		var row: Dictionary = ledger[id]
		row["amount"] = int(row["amount"]) + amount
		var incoming: LootRarity.Tier = LootRarity.from_name(str(entry.get("rarity", "common")))
		if incoming > LootRarity.from_name(str(row["rarity"])):
			row["rarity"] = str(entry.get("rarity", "common"))
