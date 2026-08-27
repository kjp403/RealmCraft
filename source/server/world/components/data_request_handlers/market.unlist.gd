extends DataRequestHandler
## Seller pulls stock off their own stall: one listing, part of one listing
## ({"listing_id", "amount"}), or every listing ({"all": true}). A partial pull
## leaves the rest on sale, so trimming a stack never means taking the stall down
## and re-listing what is left.
##
## Pulled goods go to the MAILBOX, never straight to the bag:
## the bag can be full, and a pull that fails halfway would have already flipped
## the listing off the board. Mail can't bounce. See [Market].
##
## Each pull is one transaction: flip the row to PULLED (verified), then write the
## delivery mail. Both land or neither does, so the stock is always in exactly one
## place — never both, never neither.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var pr: PlayerResource = instance.world_server.connected_players.get(peer_id, null)
	if pr == null:
		return {"ok": false, "reason": "no_player"}

	var market: MarketStore = instance.world_server.database.market_store

	var targets: Array[int] = []
	if bool(args.get("all", false)):
		for row: Dictionary in market.listings_of_seller(pr.player_id):
			targets.append(int(row.get("listing_id", 0)))
	else:
		var listing_id: int = int(args.get("listing_id", 0))
		if listing_id <= 0:
			return {"ok": false, "reason": "missing"}
		targets.append(listing_id)

	if targets.is_empty():
		return {"ok": false, "reason": "missing"}

	# A partial pull only makes sense for a single named listing; "all" always
	# takes whole listings.
	var want: int = 0 if bool(args.get("all", false)) else maxi(0, int(args.get("amount", 0)))

	var db_store: WorldStoreSqlite = instance.world_server.database.store
	var pulled: Array = []
	for listing_id: int in targets:
		# One transaction per listing: pulling five stacks and failing on the third
		# should still leave the first two safely delivered.
		db_store.begin()
		var result: Dictionary = (
			market.withdraw(listing_id, pr.player_id, want)
			if want > 0
			else market.pull(listing_id, pr.player_id)
		)
		if not bool(result.get("ok", false)):
			db_store.rollback()
			continue # not theirs, already sold, already pulled, or too few units
		var item_id: int = int(result.get("item_id", 0))
		var amount: int = int(result.get("amount", 0))
		var mail_id: int = MarketService.return_stock(
			instance, pr.player_id, item_id, amount, "You pulled this stock from your stall."
		)
		if mail_id <= 0:
			# Delivery failed — roll back so the stock stays on the stall rather
			# than ending up with nowhere to live.
			db_store.rollback()
			ServerLog.error(
				"Market: return mail failed for listing #%d (player #%d); listing left active."
				% [listing_id, pr.player_id]
			)
			continue
		db_store.commit()
		pulled.append({"item_id": item_id, "amount": amount})

	if pulled.is_empty():
		return {"ok": false, "reason": "missing"}

	MarketService.broadcast_change(&"unlist")
	ServerLog.info(
		"Market: player #%d (%s) pulled %d listing(s) back to their mailbox."
		% [pr.player_id, pr.display_name, pulled.size()]
	)
	return {"ok": true, "pulled": pulled}
