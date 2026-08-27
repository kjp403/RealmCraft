class_name MarketStore
extends RefCounted
## SQLite access for the player Trading Post (rules + overview: [Market]).
## Mirrors MailStore: holds the world's SQLite handle, every query goes through
## query_with_bindings.
##
## `market_stores` is one row per character. `market_listings` holds ESCROWED
## stock — a listed stack has already left the seller's bag, so the row is the
## item's only home. That is what makes a stall keep selling while its owner is
## offline, and what makes double-listing impossible.
##
## CONCURRENCY: every data-request handler runs synchronously on the world's main
## loop with no `await`, so a read-then-write pair inside one handler cannot be
## interleaved by another player's request. The guarded WHERE clauses below are
## defence in depth, not the primary lock.

var db: SQLite


func _init(_db: SQLite) -> void:
	db = _db


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


# --- Stores ------------------------------------------------------------------

## This character's store row, or {} if they have never opened one.
func store_for(owner_id: int) -> Dictionary:
	db.query_with_bindings(
		"SELECT store_id, owner_id, store_name, is_open, updated_at_ms FROM market_stores WHERE owner_id = ?;",
		[owner_id]
	)
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Creates the store if missing and applies name / open state. Returns its store_id
## (0 only if the insert somehow failed). Idempotent — safe to call on every edit.
func upsert_store(owner_id: int, store_name: String, is_open: bool) -> int:
	var existing: Dictionary = store_for(owner_id)
	if existing.is_empty():
		db.query_with_bindings(
			"INSERT INTO market_stores(owner_id, store_name, is_open, updated_at_ms) VALUES(?, ?, ?, ?);",
			[owner_id, store_name, 1 if is_open else 0, _now_ms()]
		)
		var created: Dictionary = store_for(owner_id)
		return int(created.get("store_id", 0))
	db.query_with_bindings(
		"UPDATE market_stores SET store_name = ?, is_open = ?, updated_at_ms = ? WHERE owner_id = ?;",
		[store_name, 1 if is_open else 0, _now_ms(), owner_id]
	)
	return int(existing.get("store_id", 0))


## Every open store that currently has stock, newest activity first, each with its
## active listing count, cheapest unit price and total units. Stores with zero
## active listings are hidden — an empty stall is noise on the board.
func open_stores() -> Array:
	db.query(
		"SELECT s.store_id, s.owner_id, s.store_name, s.updated_at_ms, "
		+ "COUNT(l.listing_id) AS listing_count, MIN(l.unit_price) AS cheapest, SUM(l.amount) AS units "
		+ "FROM market_stores s JOIN market_listings l "
		+ "ON l.store_id = s.store_id AND l.state = 0 AND l.amount > 0 "
		+ "WHERE s.is_open = 1 "
		+ "GROUP BY s.store_id ORDER BY s.updated_at_ms DESC;"
	)
	return db.query_result.duplicate(true)


# --- Listings ----------------------------------------------------------------

## Active stock of one store, cheapest first.
func listings_of_store(store_id: int) -> Array:
	db.query_with_bindings(
		"SELECT listing_id, store_id, seller_id, seller_name, item_id, amount, unit_price, created_at_ms "
		+ "FROM market_listings WHERE store_id = ? AND state = 0 AND amount > 0 "
		+ "ORDER BY unit_price ASC, listing_id ASC;",
		[store_id]
	)
	return db.query_result.duplicate(true)


## Every active listing across every OPEN store — the price-comparison feed.
## Bounded so a runaway market cannot blow past the WebSocket buffer; the caller
## filters and trims what it gets.
func all_active_listings(limit: int = 2000) -> Array:
	db.query_with_bindings(
		"SELECT l.listing_id, l.store_id, l.seller_id, l.seller_name, l.item_id, l.amount, "
		+ "l.unit_price, l.created_at_ms, s.store_name "
		+ "FROM market_listings l JOIN market_stores s ON s.store_id = l.store_id "
		+ "WHERE l.state = 0 AND l.amount > 0 AND s.is_open = 1 "
		+ "ORDER BY l.unit_price ASC, l.listing_id ASC LIMIT ?;",
		[limit]
	)
	return db.query_result.duplicate(true)


## This seller's own active listings (shown in My Store even while it is closed).
func listings_of_seller(seller_id: int) -> Array:
	db.query_with_bindings(
		"SELECT listing_id, store_id, seller_id, seller_name, item_id, amount, unit_price, created_at_ms "
		+ "FROM market_listings WHERE seller_id = ? AND state = 0 AND amount > 0 "
		+ "ORDER BY listing_id DESC;",
		[seller_id]
	)
	return db.query_result.duplicate(true)


func active_listing_count(store_id: int) -> int:
	db.query_with_bindings(
		"SELECT COUNT(*) AS c FROM market_listings WHERE store_id = ? AND state = 0 AND amount > 0;",
		[store_id]
	)
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("c", 0))


## One listing by id, whatever its state ({} if there is no such row).
func listing(listing_id: int) -> Dictionary:
	db.query_with_bindings(
		"SELECT l.listing_id, l.store_id, l.seller_id, l.seller_name, l.item_id, l.amount, "
		+ "l.unit_price, l.state, l.created_at_ms, s.store_name, s.is_open "
		+ "FROM market_listings l JOIN market_stores s ON s.store_id = l.store_id "
		+ "WHERE l.listing_id = ?;",
		[listing_id]
	)
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Escrows a stack. The CALLER must already have removed it from the seller's bag;
## returns the new listing_id, or 0 if the row could not be written (in which case
## the caller must put the stack back).
func create_listing(
	store_id: int,
	seller_id: int,
	seller_name: String,
	item_id: int,
	amount: int,
	unit_price: int
) -> int:
	db.query_with_bindings(
		"INSERT INTO market_listings(store_id, seller_id, seller_name, item_id, amount, unit_price, state, created_at_ms) "
		+ "VALUES(?, ?, ?, ?, ?, ?, 0, ?);",
		[store_id, seller_id, seller_name, item_id, amount, unit_price, _now_ms()]
	)
	db.query("SELECT last_insert_rowid() AS id;")
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("id", 0))


## Takes [param amount] units OUT of an active listing, flipping it to SOLD when it
## empties. Returns true only if the full amount was reserved — the caller is then
## on the hook to deliver the goods, or to roll its transaction back.
##
## This is the step that makes a purchase non-duplicable: the decrement is guarded
## on `amount >= ?`, and the re-read below proves it landed, so two buyers racing
## the last unit means the loser reserves nothing.
func reserve(listing_id: int, amount: int) -> bool:
	if amount <= 0:
		return false
	db.query_with_bindings("SELECT amount, state FROM market_listings WHERE listing_id = ?;", [listing_id])
	if db.query_result.is_empty():
		return false
	var before: int = int(db.query_result[0].get("amount", 0))
	if int(db.query_result[0].get("state", -1)) != Market.State.ACTIVE or before < amount:
		return false
	db.query_with_bindings(
		"UPDATE market_listings SET amount = amount - ? WHERE listing_id = ? AND state = 0 AND amount >= ?;",
		[amount, listing_id, amount]
	)
	db.query_with_bindings("SELECT amount FROM market_listings WHERE listing_id = ?;", [listing_id])
	if db.query_result.is_empty() or int(db.query_result[0].get("amount", -1)) != before - amount:
		return false
	if before - amount == 0:
		db.query_with_bindings(
			"UPDATE market_listings SET state = 1 WHERE listing_id = ? AND amount <= 0;",
			[listing_id]
		)
	return true


## Changes an active listing's asking price in place. Touches no stock at all —
## nothing can be lost or duplicated here — which is why a seller can re-price as
## often as they like without taking the stall down. Returns false if the listing
## is not theirs or is no longer active.
func reprice(listing_id: int, seller_id: int, unit_price: int) -> bool:
	if unit_price <= 0:
		return false
	db.query_with_bindings(
		"UPDATE market_listings SET unit_price = ? WHERE listing_id = ? AND seller_id = ? AND state = 0 AND amount > 0;",
		[unit_price, listing_id, seller_id]
	)
	db.query_with_bindings(
		"SELECT unit_price, state FROM market_listings WHERE listing_id = ? AND seller_id = ?;",
		[listing_id, seller_id]
	)
	if db.query_result.is_empty():
		return false
	var row: Dictionary = db.query_result[0]
	return int(row.get("state", -1)) == Market.State.ACTIVE and int(row.get("unit_price", 0)) == unit_price


## Seller takes SOME units back off their own listing, leaving the rest on sale.
## Same guarded decrement as [method reserve] — the units come out exactly once —
## so a seller can trim a stack without pulling the whole thing and re-listing.
## Returns {"ok": true, "item_id", "amount"} for the caller to return by mail.
func withdraw(listing_id: int, seller_id: int, amount: int) -> Dictionary:
	if amount <= 0:
		return {"ok": false}
	db.query_with_bindings(
		"SELECT item_id, amount FROM market_listings "
		+ "WHERE listing_id = ? AND seller_id = ? AND state = 0;",
		[listing_id, seller_id]
	)
	if db.query_result.is_empty():
		return {"ok": false}
	var row: Dictionary = db.query_result[0].duplicate()
	var before: int = int(row.get("amount", 0))
	if before < amount:
		return {"ok": false}
	if before == amount:
		# Taking everything IS a pull — reuse it so the row ends up PULLED rather
		# than sitting ACTIVE with zero stock.
		return pull(listing_id, seller_id)
	db.query_with_bindings(
		"UPDATE market_listings SET amount = amount - ? WHERE listing_id = ? AND seller_id = ? AND state = 0 AND amount >= ?;",
		[amount, listing_id, seller_id, amount]
	)
	db.query_with_bindings("SELECT amount FROM market_listings WHERE listing_id = ?;", [listing_id])
	if db.query_result.is_empty() or int(db.query_result[0].get("amount", -1)) != before - amount:
		return {"ok": false}
	return {"ok": true, "item_id": int(row.get("item_id", 0)), "amount": amount}


## Seller pulls their own listing. Marks it PULLED and returns
## {"ok": true, "item_id", "amount"} so the caller can return the escrowed goods.
## Guarded on seller_id + state, and the flip is VERIFIED before the caller hands
## anything back: returning goods off a still-ACTIVE listing would duplicate them.
func pull(listing_id: int, seller_id: int) -> Dictionary:
	db.query_with_bindings(
		"SELECT item_id, amount FROM market_listings "
		+ "WHERE listing_id = ? AND seller_id = ? AND state = 0 AND amount > 0;",
		[listing_id, seller_id]
	)
	if db.query_result.is_empty():
		return {"ok": false}
	var row: Dictionary = db.query_result[0].duplicate()
	db.query_with_bindings(
		"UPDATE market_listings SET state = 2 WHERE listing_id = ? AND seller_id = ? AND state = 0;",
		[listing_id, seller_id]
	)
	db.query_with_bindings("SELECT state FROM market_listings WHERE listing_id = ?;", [listing_id])
	if db.query_result.is_empty() or int(db.query_result[0].get("state", 0)) != Market.State.PULLED:
		return {"ok": false}
	return {"ok": true, "item_id": int(row.get("item_id", 0)), "amount": int(row.get("amount", 0))}


# --- Sale history ------------------------------------------------------------

## Records one completed sale. Called INSIDE the buy transaction, so a rolled-back
## purchase never leaves a phantom price on the ticker.
func record_trade(
	item_id: int,
	amount: int,
	unit_price: int,
	seller_id: int,
	seller_name: String,
	buyer_id: int,
	buyer_name: String
) -> void:
	db.query_with_bindings(
		"INSERT INTO market_trades(item_id, amount, unit_price, total, seller_id, seller_name, buyer_id, buyer_name, sold_at_ms) "
		+ "VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?);",
		[
			item_id, amount, unit_price, unit_price * amount,
			seller_id, seller_name, buyer_id, buyer_name, _now_ms()
		]
	)


## Most recent sales of ONE item, newest first — the price history a seller reads
## before setting their own ask.
func trades_for_item(item_id: int, limit: int = 12) -> Array:
	db.query_with_bindings(
		"SELECT trade_id, item_id, amount, unit_price, total, seller_name, buyer_name, sold_at_ms "
		+ "FROM market_trades WHERE item_id = ? ORDER BY trade_id DESC LIMIT ?;",
		[item_id, limit]
	)
	return db.query_result.duplicate(true)


## Most recent sales across the whole market — the "what is moving right now"
## ticker on the board.
func recent_trades(limit: int = 30) -> Array:
	db.query_with_bindings(
		"SELECT trade_id, item_id, amount, unit_price, total, seller_name, buyer_name, sold_at_ms "
		+ "FROM market_trades ORDER BY trade_id DESC LIMIT ?;",
		[limit]
	)
	return db.query_result.duplicate(true)


## Rolling price stats per item over [param window_ms], as
## {item_id: {"low", "high", "avg", "units", "trades", "last"}}. One query for the
## whole board so the client can annotate every row without an N+1 round trip.
## `avg` is unit-weighted (total gold / total units), which is the number that
## actually describes the market — a single 1-unit outlier should not move it as
## much as a 500-unit block.
func price_stats(window_ms: int) -> Dictionary:
	var cutoff: int = _now_ms() - maxi(0, window_ms)
	db.query_with_bindings(
		"SELECT item_id, MIN(unit_price) AS low, MAX(unit_price) AS high, "
		+ "SUM(total) AS gold, SUM(amount) AS units, COUNT(*) AS trades "
		+ "FROM market_trades WHERE sold_at_ms >= ? GROUP BY item_id;",
		[cutoff]
	)
	var stats: Dictionary = {}
	for row: Dictionary in db.query_result:
		var units: int = int(row.get("units", 0))
		stats[int(row.get("item_id", 0))] = {
			"low": int(row.get("low", 0)),
			"high": int(row.get("high", 0)),
			"avg": int(round(float(row.get("gold", 0)) / float(maxi(1, units)))),
			"units": units,
			"trades": int(row.get("trades", 0)),
		}
	# Latest traded price per item — the single most useful anchor, and not
	# something a GROUP BY can give us without a window function.
	db.query_with_bindings(
		"SELECT t.item_id, t.unit_price FROM market_trades t "
		+ "JOIN (SELECT item_id, MAX(trade_id) AS newest FROM market_trades WHERE sold_at_ms >= ? GROUP BY item_id) m "
		+ "ON m.item_id = t.item_id AND m.newest = t.trade_id;",
		[cutoff]
	)
	for row: Dictionary in db.query_result:
		var item_id: int = int(row.get("item_id", 0))
		if stats.has(item_id):
			stats[item_id]["last"] = int(row.get("unit_price", 0))
	return stats
