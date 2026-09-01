extends DataRequestHandler
## Buy ONE good from the Traveling Peddler. Args: {npc: node_name, id: stock_id}.
##
## Everything a client sends here is a NAME, never a price: the stock id is looked
## up in the server's own catalog and the gold comes off the server's own reading
## of today's roll. A client that edits its copy of the cart gets refused at
## [method PeddlerDesk.lock_reason]; one that edits a price changes nothing at all.
##
## ORDERING. Every gate — alive, in range, stocked today, not already bought, item
## resolvable, bag has room, gold present — clears before a coin moves, and the
## purchase is only written to the daily ledger once the item is actually in the
## bag. A refused sale is free and never burns the day's allowance.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var ctx: Dictionary = PeddlerDesk.resolve(peer_id, instance, args)
	if ctx.has("reason"):
		return {"ok": false, "reason": ctx["reason"]}

	var player: Player = ctx["player"]
	var date: String = ctx["date"]
	var pr: PlayerResource = player.player_resource

	var row: PeddlerItemData = PeddlerCatalog.find(str(args.get("id", "")))
	if row == null:
		return {"ok": false, "reason": "unknown_item"}

	var lock: String = PeddlerDesk.lock_reason(player, row, date)
	if not lock.is_empty():
		# "sold_out" is its own reason so the window can flip that row rather than
		# showing a generic refusal on the thing the player just clicked.
		return {
			"ok": false,
			"reason": "sold_out" if lock == PeddlerDesk.LOCK_SOLD_OUT else "locked",
			"lock": lock,
		}

	var item_id: int = PeddlerDesk.item_id_for(row)
	if item_id <= 0:
		# The stock row names an item the registry does not have. A content error,
		# not a player error — never charge for it.
		push_error("peddler.buy: stock '%s' has no indexed item." % row.id)
		return {"ok": false, "reason": "no_item"}

	var gold_id: int = Economy.gold_id()
	if gold_id <= 0:
		return {"ok": false, "reason": "no_currency"}

	var inventory: Dictionary = pr.inventory
	var active_bag: int = pr.active_inventory_bag
	var bag_count: int = pr.inventory_bags
	if not Inventory.can_add(
		inventory, item_id, 1, Inventory.MAX_SLOTS, false, active_bag, bag_count
	):
		return {"ok": false, "reason": "inventory_full"}
	if Inventory.count(inventory, gold_id) < row.price_gold:
		return {"ok": false, "reason": "cant_afford", "price": row.price_gold}

	if not Inventory.remove_amount_by_id(inventory, gold_id, row.price_gold):
		# can_afford said yes a line ago, so this is a data race with another
		# request rather than a shortfall. Refuse rather than hand out a free good.
		return {"ok": false, "reason": "cant_afford", "price": row.price_gold}

	if not Inventory.try_add_item(
		inventory, item_id, 1, Inventory.MAX_SLOTS, false, active_bag, bag_count
	):
		# Shouldn't happen after can_add — put the gold back rather than leaving
		# the player short and empty-handed.
		Inventory.add_item(inventory, gold_id, row.price_gold, false, active_bag, bag_count)
		return {"ok": false, "reason": "inventory_full"}

	# The good is in the bag. NOW spend the day's allowance.
	PeddlerLedger.record(pr, row.id, date)

	# Persist immediately. The allowance and the 500,000-gold purchase both live
	# in the same save, and a crash between the two would either hand back the
	# gold or eat the item — save once, atomically, at the point they agree.
	if WorldServer.curr != null and WorldServer.curr.database != null:
		WorldServer.curr.database.save_player(pr)

	# A bought item may satisfy a "Bring N item" (COLLECT) objective, which has no
	# advance event of its own. Empty messages = a silent tracker refresh.
	WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": []})

	return {
		"ok": true,
		"id": row.id,
		"item_id": item_id,
		"item_name": row.item_name,
		"paid": row.price_gold,
		"gold": Inventory.count(inventory, gold_id),
	}
