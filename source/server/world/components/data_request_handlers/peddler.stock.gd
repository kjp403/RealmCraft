extends DataRequestHandler
## Price the Traveling Peddler's cart for ONE player. Args: {npc: node_name}.
##
## The client computes nothing. The stock is a function of the server's UTC date,
## the SOLD OUT state is a function of a ledger only the server holds, and the
## balance is read off the authoritative inventory — so the window is drawn
## entirely from this reply, which by construction means what a player sees is
## what [code]peddler.buy[/code] will charge and refuse.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var ctx: Dictionary = PeddlerDesk.resolve(peer_id, instance, args)
	if ctx.has("reason"):
		return {"ok": false, "reason": ctx["reason"]}

	var player: Player = ctx["player"]
	var date: String = ctx["date"]
	var pr: PlayerResource = player.player_resource
	var gold_id: int = Economy.gold_id()
	var gold: int = Inventory.count(pr.inventory, gold_id) if gold_id > 0 else 0

	var rows: Array = []
	for row: PeddlerItemData in PeddlerStock.for_date(date):
		var lock: String = PeddlerDesk.lock_reason(player, row, date)
		rows.append({
			"id": row.id,
			"item_name": row.item_name,
			"description": row.description,
			"tier": row.tier,
			"price": row.price_gold,
			"item_id": PeddlerDesk.item_id_for(row),
			"lock": lock,
			"sold_out": lock == PeddlerDesk.LOCK_SOLD_OUT,
			"affordable": gold >= row.price_gold,
		})

	return {
		"ok": true,
		"gold": gold,
		"date": date,
		"stock": rows,
		# How long the cart is still standing, so the window can show the clock
		# that is actually driving the despawn rather than a guess.
		"closes_in_s": PeddlerSchedule.seconds_remaining(),
	}
