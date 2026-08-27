extends DataRequestHandler
## Buys units off a market listing. This is the one place in the Trading Post
## where gold and goods change hands, so it is written to be all-or-nothing.
##
## ORDER (everything after `begin()` is one SQLite transaction):
##   1. validate the listing, the price and the buyer's gold — no mutation yet
##   2. reserve the units (guarded decrement; a racing buyer loses here)
##   3. take the buyer's gold in memory
##   4. save_player  — the gold deduction now lives in the same transaction
##   5. mail the goods to the buyer, mail the gold to the seller
##   6. commit
##
## Any failure before the commit rolls the transaction back AND restores the
## in-memory gold, so the buyer is left exactly as they started. Because the
## player row is saved INSIDE the transaction, a crash mid-way cannot leave the
## gold spent with nothing delivered, or the goods delivered for free.
##
## Delivery is by mail on both sides — a full bag can never bounce a payout.
## See [Market] and [MarketService].


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}
	var pr: PlayerResource = player.player_resource

	var listing_id: int = int(args.get("listing_id", 0))
	var amount: int = int(args.get("amount", 1))
	if listing_id <= 0 or amount <= 0 or amount > Market.MAX_BUY_AMOUNT:
		return {"ok": false, "reason": "bad_args"}

	var market: MarketStore = instance.world_server.database.market_store
	var row: Dictionary = market.listing(listing_id)
	if row.is_empty() or int(row.get("state", -1)) != Market.State.ACTIVE:
		return {"ok": false, "reason": "gone"}
	if int(row.get("is_open", 0)) != 1:
		return {"ok": false, "reason": "closed"}

	var seller_id: int = int(row.get("seller_id", 0))
	if seller_id == pr.player_id:
		return {"ok": false, "reason": "own_store"}

	var stock: int = int(row.get("amount", 0))
	if amount > stock:
		return {"ok": false, "reason": "not_enough_stock", "stock": stock}

	var item_id: int = int(row.get("item_id", 0))
	var unit_price: int = int(row.get("unit_price", 0))
	if item_id <= 0 or unit_price <= 0:
		return {"ok": false, "reason": "gone"}
	# unit_price is capped at Market.MAX_UNIT_PRICE and amount at MAX_BUY_AMOUNT, so
	# this product stays far inside int64 — no wrap-to-negative past the gold check.
	var total: int = unit_price * amount

	var gold_id: int = Economy.gold_id()
	if gold_id <= 0:
		return {"ok": false, "reason": "no_currency"}
	if Inventory.count(pr.inventory, gold_id) < total:
		return {"ok": false, "reason": "cant_afford", "total": total}

	var store: WorldStoreSqlite = instance.world_server.database.store
	store.begin()

	if not market.reserve(listing_id, amount):
		store.rollback()
		return {"ok": false, "reason": "gone"}

	if not Inventory.remove_amount_by_id(pr.inventory, gold_id, total):
		# Balance moved between the check and here (shouldn't be possible without
		# an await, but the buyer's gold is not something to assume about).
		store.rollback()
		return {"ok": false, "reason": "cant_afford", "total": total}

	# Persist the deduction INSIDE the transaction so gold and delivery commit or
	# fail together.
	instance.world_server.database.save_player(pr)

	var goods_label: String = MarketService.item_label(item_id, amount)
	var seller_name: String = str(row.get("seller_name", "a trader"))
	var store_name: String = str(row.get("store_name", "a stall"))

	var buyer_mail: int = MarketService.deliver(
		instance,
		pr.player_id,
		seller_name,
		"Purchase: %s" % goods_label,
		"You bought %s from %s (%s) at the Trading Post.\n\nPrice: %s gold total (%s each).\n\nClaim below to move it into your bag."
			% [
				goods_label, store_name, seller_name,
				MarketService.format_gold(total), MarketService.format_gold(unit_price)
			],
		[{"type": "item", "id": item_id, "amount": amount}]
	)
	var seller_mail: int = -1
	if buyer_mail > 0:
		seller_mail = MarketService.deliver(
			instance,
			seller_id,
			MarketService.SENDER_MARKET,
			"Sold: %s" % goods_label,
			"%s bought %s from your stall '%s'.\n\nYour take: %s gold (%s each).\n\nClaim below to collect it."
				% [
					pr.display_name, goods_label, store_name,
					MarketService.format_gold(total), MarketService.format_gold(unit_price)
				],
			[{"type": "currency", "amount": total}]
		)

	# History is written inside the SAME transaction as the sale, so a rolled-back
	# purchase can never leave a phantom price on the ticker.
	if buyer_mail > 0 and seller_mail > 0:
		market.record_trade(
			item_id, amount, unit_price, seller_id, seller_name, pr.player_id, pr.display_name
		)

	if buyer_mail <= 0 or seller_mail <= 0:
		# Rolling back the transaction undoes the reservation, the saved gold
		# deduction and any mail row that did land. The in-memory refund keeps the
		# live PlayerResource in step with the reverted row.
		store.rollback()
		Inventory.add_item(pr.inventory, gold_id, total, false, pr.active_inventory_bag, pr.inventory_bags)
		ServerLog.error(
			"Market: delivery failed for listing #%d (buyer #%d, seller #%d); purchase rolled back."
			% [listing_id, pr.player_id, seller_id]
		)
		return {"ok": false, "reason": "failed"}

	store.commit()

	# Everyone browsing the board sees the new stock level immediately, not on
	# their next click.
	MarketService.broadcast_change(&"buy", listing_id)
	ServerLog.info(
		"Market: player #%d (%s) bought %s from #%d for %s gold (listing #%d)."
		% [pr.player_id, pr.display_name, goods_label, seller_id, MarketService.format_gold(total), listing_id]
	)
	MarketService.notify_seller(
		instance,
		seller_id,
		"%s bought %s — %s gold is in your mailbox." % [pr.display_name, goods_label, MarketService.format_gold(total)]
	)

	return {
		"ok": true,
		"listing_id": listing_id,
		"item_id": item_id,
		"amount": amount,
		"unit_price": unit_price,
		"total": total,
		"seller_name": seller_name,
		"store_name": store_name,
		"stock_left": stock - amount,
		"gold": Inventory.count(pr.inventory, gold_id),
	}
