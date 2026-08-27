extends Node
## Regression gate for the player Trading Post's escrow ledger (MarketStore).
##
## The market's whole safety story rests on two guarantees that live in SQL, not
## in the handlers:
##   * a unit can be reserved exactly once (two buyers racing the last item means
##     one of them reserves nothing), and
##   * a listing can be pulled exactly once (a replayed pull must not hand the
##     stock back twice), and part of a listing can be taken back without
##     disturbing the rest.
## Plus the two things a live stall depends on: a price can change in place
## without touching stock, and every completed sale lands in the history that
## drives the board's price signal.
## Everything above them — the buy handler, the mailbox payout — is ordered
## around those two facts, so this probes them directly against a real SQLite
## file rather than trusting the handler comments.
##
## Run it as a SCENE, not with `-s`: this extends Node, and `-s` only accepts a
## script that inherits SceneTree / MainLoop (it pops an "doesn't inherit from
## SceneTree or MainLoop" alert otherwise).
##   godot --headless --path . tools/verify_market.tscn

const DB_PATH: String = "user://verify_market.db"

const SELLER_A: int = 9001
const SELLER_B: int = 9002
const ITEM: int = 4242

var _pass: int = 0
var _fail: int = 0
var _db: SQLite
var _market: MarketStore


func _ready() -> void:
	_open()
	_check_store_lifecycle()
	_check_reserve_is_single_use()
	_check_partial_buys()
	_check_reprice_touches_no_stock()
	_check_partial_withdraw()
	_check_pull_is_single_use()
	_check_sold_out_cannot_be_pulled()
	_check_closed_stalls_leave_the_board()
	_check_trade_history()
	_check_everything_is_listable()
	print("%d passed, %d failed" % [_pass, _fail])
	print("VERIFY_PASS" if _fail == 0 else "VERIFY_FAIL")
	get_tree().quit(0 if _fail == 0 else 1)


func _open() -> void:
	# Fresh file every run so a previous failure can't poison the next one.
	if FileAccess.file_exists(DB_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DB_PATH))
	_db = SQLite.new()
	_db.path = DB_PATH
	_db.open_db()
	WorldSchema.ensure_schema(_db)
	_market = MarketStore.new(_db)


func _list(seller_id: int, store_id: int, amount: int, price: int) -> int:
	return _market.create_listing(store_id, seller_id, "Seller%d" % seller_id, ITEM, amount, price)


func _check_store_lifecycle() -> void:
	print("store lifecycle")
	var a: int = _market.upsert_store(SELLER_A, "Ash's Stall", true)
	_ck(a > 0, "creating a stall returns an id")
	var again: int = _market.upsert_store(SELLER_A, "Ash's Emporium", true)
	_ck(again == a, "upsert is idempotent — one stall per character")
	_ck(str(_market.store_for(SELLER_A).get("store_name", "")) == "Ash's Emporium", "rename sticks")
	var b: int = _market.upsert_store(SELLER_B, "Bram's Stall", true)
	_ck(b != a and b > 0, "a second character gets a separate stall")


func _check_reserve_is_single_use() -> void:
	print("reserve is single-use")
	var store: int = _market.upsert_store(SELLER_A, "Ash's Emporium", true)
	var listing: int = _list(SELLER_A, store, 1, 500)
	_ck(_market.reserve(listing, 1), "the only unit reserves once")
	_ck(not _market.reserve(listing, 1), "a second buyer on the same unit gets nothing")
	_ck(int(_market.listing(listing).get("state", -1)) == Market.State.SOLD, "an emptied listing flips to SOLD")
	_ck(int(_market.listing(listing).get("amount", -1)) == 0, "and holds no stock")


func _check_partial_buys() -> void:
	print("partial buys")
	var store: int = _market.upsert_store(SELLER_A, "Ash's Emporium", true)
	var listing: int = _list(SELLER_A, store, 10, 25)
	_ck(not _market.reserve(listing, 11), "over-buying the stack is refused outright")
	_ck(int(_market.listing(listing).get("amount", 0)) == 10, "a refused reserve leaves the stack untouched")
	_ck(_market.reserve(listing, 4), "a partial buy reserves")
	_ck(int(_market.listing(listing).get("amount", 0)) == 6, "and decrements the stack")
	_ck(int(_market.listing(listing).get("state", -1)) == Market.State.ACTIVE, "a part-sold listing stays on sale")
	_ck(not _market.reserve(listing, 0), "a zero-unit buy is refused")
	_ck(not _market.reserve(listing, -3), "a negative-unit buy is refused")
	_ck(int(_market.listing(listing).get("amount", 0)) == 6, "neither degenerate buy moved stock")
	_ck(_market.reserve(listing, 6), "the remainder can be bought out")
	_ck(int(_market.listing(listing).get("state", -1)) == Market.State.SOLD, "which closes the listing")


func _check_reprice_touches_no_stock() -> void:
	print("re-pricing a live listing")
	var store: int = _market.upsert_store(SELLER_A, "Ash's Emporium", true)
	var listing: int = _list(SELLER_A, store, 25, 100)
	_ck(not _market.reprice(listing, SELLER_B, 90), "another player can't re-price your listing")
	_ck(int(_market.listing(listing).get("unit_price", 0)) == 100, "and the price is untouched")
	_ck(_market.reprice(listing, SELLER_A, 175), "the owner re-prices")
	_ck(int(_market.listing(listing).get("unit_price", 0)) == 175, "the new ask sticks")
	_ck(int(_market.listing(listing).get("amount", 0)) == 25, "stock is untouched by a re-price")
	_ck(int(_market.listing(listing).get("state", -1)) == Market.State.ACTIVE, "and it stays on sale")
	_ck(not _market.reprice(listing, SELLER_A, 0), "a zero price is refused")
	_ck(int(_market.listing(listing).get("unit_price", 0)) == 175, "which leaves the ask alone")
	# The stall never had to close for any of that — the row is the same one.
	_ck(_market.active_listing_count(store) >= 1, "the stall stayed open throughout")
	_market.pull(listing, SELLER_A)


func _check_partial_withdraw() -> void:
	print("taking part of a listing back")
	var store: int = _market.upsert_store(SELLER_A, "Ash's Emporium", true)
	var listing: int = _list(SELLER_A, store, 20, 40)
	_ck(not bool(_market.withdraw(listing, SELLER_B, 5).get("ok", false)), "another player can't withdraw from it")
	_ck(not bool(_market.withdraw(listing, SELLER_A, 21).get("ok", false)), "over-withdrawing is refused")
	_ck(int(_market.listing(listing).get("amount", 0)) == 20, "a refused withdraw moves nothing")
	var part: Dictionary = _market.withdraw(listing, SELLER_A, 8)
	_ck(bool(part.get("ok", false)) and int(part.get("amount", 0)) == 8, "8 units come back")
	_ck(int(_market.listing(listing).get("amount", 0)) == 12, "12 stay on sale")
	_ck(int(_market.listing(listing).get("state", -1)) == Market.State.ACTIVE, "the listing is still live")
	var rest: Dictionary = _market.withdraw(listing, SELLER_A, 12)
	_ck(bool(rest.get("ok", false)) and int(rest.get("amount", 0)) == 12, "withdrawing the remainder works")
	_ck(int(_market.listing(listing).get("state", -1)) == Market.State.PULLED, "and closes the listing as a pull")
	_ck(not bool(_market.withdraw(listing, SELLER_A, 1).get("ok", false)), "nothing is left to withdraw")


func _check_trade_history() -> void:
	print("sale history")
	var store: int = _market.upsert_store(SELLER_A, "Ash's Emporium", true)
	var listing: int = _list(SELLER_A, store, 100, 200)
	_market.reserve(listing, 60)
	_market.record_trade(ITEM, 60, 200, SELLER_A, "Ash", SELLER_B, "Bram")
	_market.reserve(listing, 40)
	_market.record_trade(ITEM, 40, 300, SELLER_A, "Ash", SELLER_B, "Bram")

	var recent: Array = _market.trades_for_item(ITEM, 10)
	_ck(recent.size() >= 2, "both sales are recorded")
	_ck(int(recent[0].get("unit_price", 0)) == 300, "newest sale comes first")
	_ck(int(recent[0].get("total", 0)) == 40 * 300, "total is price x units")

	var stats: Dictionary = _market.price_stats(60 * 60 * 1000)
	var entry: Dictionary = stats.get(ITEM, {})
	_ck(int(entry.get("low", 0)) == 200, "low is the cheapest sale")
	_ck(int(entry.get("high", 0)) == 300, "high is the dearest")
	_ck(int(entry.get("units", 0)) == 100, "units sum across sales")
	_ck(int(entry.get("last", 0)) == 300, "last is the most recent price")
	# Unit-weighted, not per-sale: (60x200 + 40x300) / 100 = 240. A plain mean of
	# the two prices would say 250 and quietly over-weight the small sale.
	_ck(int(entry.get("avg", 0)) == 240, "average is weighted by units (240)")
	_ck(_market.price_stats(0).get(ITEM, null) == null, "an empty window reports nothing")


func _check_pull_is_single_use() -> void:
	print("pull is single-use")
	var store: int = _market.upsert_store(SELLER_A, "Ash's Emporium", true)
	var listing: int = _list(SELLER_A, store, 7, 80)
	_ck(not bool(_market.pull(listing, SELLER_B).get("ok", false)), "another player can't pull your listing")
	_ck(int(_market.listing(listing).get("state", -1)) == Market.State.ACTIVE, "a rejected pull leaves it on sale")
	var first: Dictionary = _market.pull(listing, SELLER_A)
	_ck(bool(first.get("ok", false)), "the owner pulls it")
	_ck(int(first.get("amount", 0)) == 7, "and gets the whole stack back")
	_ck(int(first.get("item_id", 0)) == ITEM, "with the right item")
	_ck(not bool(_market.pull(listing, SELLER_A).get("ok", false)), "a replayed pull returns nothing")


func _check_sold_out_cannot_be_pulled() -> void:
	print("sold stock can't be pulled")
	var store: int = _market.upsert_store(SELLER_A, "Ash's Emporium", true)
	var listing: int = _list(SELLER_A, store, 2, 10)
	_ck(_market.reserve(listing, 2), "buyer takes the lot")
	_ck(not bool(_market.pull(listing, SELLER_A).get("ok", false)), "the seller can't then pull it back")


func _check_closed_stalls_leave_the_board() -> void:
	print("board visibility")
	var store: int = _market.upsert_store(SELLER_B, "Bram's Stall", true)
	_list(SELLER_B, store, 3, 60)
	_ck(_market.active_listing_count(store) == 1, "an active listing counts against the stall cap")
	_ck(_store_on_board(store), "an open stall with stock is on the board")
	_market.upsert_store(SELLER_B, "Bram's Stall", false)
	_ck(not _store_on_board(store), "closing takes it off the board")
	_ck(_market.listings_of_seller(SELLER_B).size() == 1, "but the owner still sees their escrowed stock")
	_ck(_market.all_active_listings().all(func(row: Dictionary) -> bool:
		return int(row.get("store_id", 0)) != store), "and its rows leave the price feed")
	_market.upsert_store(SELLER_B, "Bram's Stall", true)
	_ck(_store_on_board(store), "reopening puts it back, stock intact")


## The Trading Post's listing rule is deliberately a two-item DENY list, not an
## allow list — so this walks the entire item registry and asserts it. A new item
## is tradeable the day it ships; only quest items and currency are ever blocked,
## and a stray `can_trade = false` on some gear piece must not quietly exclude it.
func _check_everything_is_listable() -> void:
	print("every item is listable except quest items and currency")
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"items")
	if registry == null:
		_ck(false, "the items registry is available")
		return

	var listable: int = 0
	var quest_blocked: int = 0
	var currency_blocked: int = 0
	var wrongly_blocked: PackedStringArray = PackedStringArray()
	for item_id: int in registry.all_ids():
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item == null:
			continue
		var is_quest: bool = item is QuestItem or item.inventory_tab() == Item.InventoryTab.QUEST
		if Market.is_listable(item):
			listable += 1
			if is_quest or item.is_currency:
				wrongly_blocked.append("%s should NOT be listable" % item.item_name)
			continue
		if is_quest:
			quest_blocked += 1
		elif item.is_currency:
			currency_blocked += 1
		else:
			wrongly_blocked.append(String(item.item_name))

	_ck(listable > 0, "%d items are listable" % listable)
	_ck(quest_blocked > 0, "%d quest items are blocked" % quest_blocked)
	_ck(currency_blocked > 0, "%d currencies are blocked" % currency_blocked)
	_ck(
		wrongly_blocked.is_empty(),
		"nothing else is blocked%s" % ("" if wrongly_blocked.is_empty() else ": " + ", ".join(wrongly_blocked))
	)


func _store_on_board(store_id: int) -> bool:
	for row: Dictionary in _market.open_stores():
		if int(row.get("store_id", 0)) == store_id:
			return true
	return false


func _ck(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  ok    %s" % label)
	else:
		_fail += 1
		printerr("  FAIL  %s" % label)
