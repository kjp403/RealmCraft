extends DataRequestHandler
## Puts goods on the caller's market stall (the ESCROW-IN step).
##
## Addressed by ITEM, not by bag square. `Item.stack_limit` caps a bag square, and
## honouring it here is what made a seller with 900 cooked shrimp post ninety
## ten-count offers. The sellable amount is [method Inventory.count] across every
## bag, and the units are taken from as many squares as it takes.
##
## The goods leave the bag, the bag is persisted, and the listing row is written
## — all inside ONE SQLite transaction, so the item is in exactly one of the two
## places at every commit point. A failure anywhere rolls the transaction back and
## puts the goods straight back into the live PlayerResource, leaving the seller
## exactly as they started. See [Market].


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

	var inventory: Dictionary = pr.inventory
	var item_id: int = int(args.get("item_id", 0))
	if item_id <= 0:
		# Slot-addressed callers (an older client) name a bag square; take its
		# item and then sell from the whole bag like everyone else.
		var slot_uid: int = int(args.get("uid", -1))
		if slot_uid < 0 or not inventory.has(slot_uid):
			return {"ok": false, "reason": "missing"}
		item_id = int(inventory[slot_uid].get("id", 0))

	# Everything the seller owns of this item, however many squares it sits in.
	var have: int = Inventory.count(inventory, item_id)
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item_id <= 0 or have <= 0 or item == null:
		return {"ok": false, "reason": "missing"}
	if not Market.is_listable(item):
		return {"ok": false, "reason": "not_listable", "message": Market.listing_block_reason(item)}

	var amount: int = int(args.get("amount", have))
	if amount <= 0 or amount > have or amount > Market.MAX_LISTING_AMOUNT:
		return {"ok": false, "reason": "bad_amount"}

	var unit_price: int = int(args.get("unit_price", 0))
	var min_price: int = maxi(1, item.market_minimum_price)
	if unit_price < min_price:
		return {"ok": false, "reason": "min_price", "min_price": min_price}
	if unit_price > Market.MAX_UNIT_PRICE:
		return {"ok": false, "reason": "max_price", "max_price": Market.MAX_UNIT_PRICE}

	var market: MarketStore = instance.world_server.database.market_store
	var store: Dictionary = market.store_for(pr.player_id)
	var store_id: int = int(store.get("store_id", 0))
	if store_id <= 0:
		# Listing without ever pressing "Open Store" still means "I want to sell".
		store_id = market.upsert_store(
			pr.player_id, Market.sanitize_store_name("", pr.display_name), true
		)
		if store_id <= 0:
			return {"ok": false, "reason": "failed"}
	# The board cap counts ROWS, so it only applies when this listing opens one.
	# Topping up an offer the stall already has adds no row and is never blocked.
	var merge_into: int = market.matching_listing(store_id, pr.player_id, item_id, unit_price)
	if merge_into <= 0 and market.active_listing_count(store_id) >= Market.MAX_LISTINGS_PER_STORE:
		return {"ok": false, "reason": "store_full", "max_listings": Market.MAX_LISTINGS_PER_STORE}

	# --- Escrow in. Nothing above this line has mutated anything. ---
	var db_store: WorldStoreSqlite = instance.world_server.database.store
	db_store.begin()

	# All-or-nothing across every bag square holding the item: remove_amount_by_id
	# re-counts first and mutates nothing when the total falls short, so there is
	# no partial take to unwind here.
	if not Inventory.remove_amount_by_id(inventory, item_id, amount):
		db_store.rollback()
		return {"ok": false, "reason": "missing"}

	# Saved inside the transaction: the bag without the goods and the stall row
	# holding them commit together, or neither does.
	instance.world_server.database.save_player(pr)

	# Merge when the stall already asks this price for this item, so re-listing
	# after a restock grows one row instead of adding a duplicate line.
	var listing_id: int = 0
	if merge_into > 0:
		listing_id = market.restock(store_id, pr.player_id, item_id, amount, unit_price)
	# A refused merge (the target filled to MAX_LISTING_AMOUNT, or emptied under
	# us) falls back to a new row — but that IS a new row, so the board cap the
	# merge let us skip has to be honoured before opening it.
	var capped: bool = false
	if listing_id <= 0:
		if market.active_listing_count(store_id) >= Market.MAX_LISTINGS_PER_STORE:
			capped = true
		else:
			listing_id = market.create_listing(
				store_id, pr.player_id, pr.display_name, item_id, amount, unit_price
			)
	if listing_id <= 0:
		db_store.rollback()
		Inventory.add_item(inventory, item_id, amount, false, pr.active_inventory_bag, pr.inventory_bags)
		if capped:
			return {
				"ok": false, "reason": "store_full", "max_listings": Market.MAX_LISTINGS_PER_STORE
			}
		ServerLog.error(
			"Market: listing insert failed for player #%d (%s); %s returned to bag."
			% [pr.player_id, pr.display_name, MarketService.item_label(item_id, amount)]
		)
		return {"ok": false, "reason": "failed"}

	db_store.commit()

	MarketService.broadcast_change(&"list", listing_id)
	ServerLog.info(
		"Market: player #%d (%s) listed %s at %s each (listing #%d)."
		% [
			pr.player_id, pr.display_name, MarketService.item_label(item_id, amount),
			MarketService.format_gold(unit_price), listing_id
		]
	)
	return {
		"ok": true,
		"listing_id": listing_id,
		"item_id": item_id,
		"amount": amount,
		"unit_price": unit_price,
		"inventory": pr.inventory,
	}
