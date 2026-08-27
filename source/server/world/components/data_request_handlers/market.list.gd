extends DataRequestHandler
## Puts one bag stack on the caller's market stall (the ESCROW-IN step).
##
## The stack leaves the bag, the bag is persisted, and the listing row is written
## — all inside ONE SQLite transaction, so the item is in exactly one of the two
## places at every commit point. A failure anywhere rolls the transaction back and
## puts the stack straight back into the live PlayerResource, leaving the seller
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

	var slot_uid: int = int(args.get("uid", -1))
	var inventory: Dictionary = pr.inventory
	if slot_uid < 0 or not inventory.has(slot_uid):
		return {"ok": false, "reason": "missing"}

	var slot: Dictionary = inventory[slot_uid]
	var item_id: int = int(slot.get("id", 0))
	var have: int = int(slot.get("a", 0))
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item_id <= 0 or have <= 0 or item == null:
		return {"ok": false, "reason": "missing"}
	if not Market.is_listable(item):
		return {"ok": false, "reason": "not_listable", "message": Market.listing_block_reason(item)}

	var amount: int = int(args.get("amount", have))
	if amount <= 0 or amount > have:
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
	if market.active_listing_count(store_id) >= Market.MAX_LISTINGS_PER_STORE:
		return {"ok": false, "reason": "store_full", "max_listings": Market.MAX_LISTINGS_PER_STORE}

	# --- Escrow in. Nothing above this line has mutated anything. ---
	var db_store: WorldStoreSqlite = instance.world_server.database.store
	db_store.begin()

	var removed: int = Inventory.remove_from_slot(inventory, slot_uid, amount)
	if removed != amount:
		# Partial take — put back exactly what came out and abort untouched.
		db_store.rollback()
		if removed > 0:
			Inventory.add_item(inventory, item_id, removed, false, pr.active_inventory_bag, pr.inventory_bags)
		return {"ok": false, "reason": "missing"}

	# Saved inside the transaction: the bag without the stack and the stall row
	# holding it commit together, or neither does.
	instance.world_server.database.save_player(pr)

	var listing_id: int = market.create_listing(
		store_id, pr.player_id, pr.display_name, item_id, amount, unit_price
	)
	if listing_id <= 0:
		db_store.rollback()
		Inventory.add_item(inventory, item_id, amount, false, pr.active_inventory_bag, pr.inventory_bags)
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
