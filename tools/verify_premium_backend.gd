extends SceneTree
## Drives [PremiumStore] against a throwaway database and asserts the money rules.
##
## WHY A REAL DATABASE AND NOT MOCKS. Every property worth checking here is a
## property of SQLite, not of the GDScript: that the ledger PRIMARY KEY refuses a
## replay, that a guarded UPDATE touches nothing when the balance moved, that a
## rolled-back debit leaves the balance where it was. A mock would assert that my
## own code does what I already wrote it to do.
##
## Runs against a temp file under user:// and deletes it first, so a previous run
## can never make this one pass.

const DB_PATH: String = "user://premium_verify.db"

var _failures: int = 0


func _init() -> void:
	_reset_db()
	var db: SQLite = SQLite.new()
	db.path = DB_PATH
	db.open_db()
	db.query("PRAGMA journal_mode=WAL;")
	PremiumSchema.ensure_schema(db)
	var store: PremiumStore = PremiumStore.new(db)

	_check_empty_wallet(store)
	_check_credit(store)
	_check_debit(store)
	_check_idempotency(store)
	_check_insufficient(store)
	_check_bad_args(store)
	_check_ledger_sums(store)
	_check_catalog_prices()

	print("")
	if _failures == 0:
		print("verify_premium_backend: PASS")
	else:
		print("verify_premium_backend: FAIL (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


func _reset_db() -> void:
	for suffix: String in ["", "-wal", "-shm"]:
		var path: String = DB_PATH + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok    %s" % label)
		return
	_failures += 1
	push_error("FAILED: %s %s" % [label, detail])
	print("  FAIL  %s  %s" % [label, detail])


## An account nobody has ever funded reads as 0, not as an error. The balance
## endpoint must answer the same for a new account as for a spent-out one.
func _check_empty_wallet(store: PremiumStore) -> void:
	print("empty wallet")
	_ok("unknown account reads 0", store.balance_of("nobody") == 0)
	_ok("blank account reads 0", store.balance_of("   ") == 0)


func _check_credit(store: PremiumStore) -> void:
	print("credit")
	var r: Dictionary = store.credit("kyle", 2000, "tx-credit-1", "manual")
	_ok("first credit applies", bool(r.get("ok")) and int(r.get("balance")) == 2000, str(r))
	_ok("balance reads back", store.balance_of("kyle") == 2000)
	# Case folding: AuthenticationManager lower-cases on create and on lookup, so
	# "Kyle" and "kyle" are ONE account and must be one wallet.
	_ok("case-insensitive wallet", store.balance_of("KYLE") == 2000)
	var again: Dictionary = store.credit("kyle", 2000, "tx-credit-1", "manual")
	_ok("replayed credit is a no-op", bool(again.get("duplicate")), str(again))
	_ok("replay did not double the balance", store.balance_of("kyle") == 2000)


func _check_debit(store: PremiumStore) -> void:
	print("debit")
	var r: Dictionary = store.debit("kyle", "skin:10001", 750, "tx-buy-1")
	_ok("debit succeeds", bool(r.get("ok")) and not bool(r.get("duplicate")), str(r))
	_ok("returns new balance", int(r.get("balance")) == 1250, str(r))
	_ok("balance persisted", store.balance_of("kyle") == 1250)
	var row: Dictionary = store.transaction("tx-buy-1")
	_ok("ledger row written", not row.is_empty())
	_ok("ledger records the item", str(row.get("item_id", "")) == "skin:10001", str(row))
	_ok("debit is stored negative", int(row.get("cost", 0)) == -750, str(row))
	_ok("ledger records balance_after", int(row.get("balance_after", 0)) == 1250, str(row))


## The property the whole design hangs on: the same transaction_id settles once.
func _check_idempotency(store: PremiumStore) -> void:
	print("idempotency")
	var replay: Dictionary = store.debit("kyle", "skin:10001", 750, "tx-buy-1")
	_ok("replay reports duplicate", bool(replay.get("duplicate")), str(replay))
	_ok("replay charges nothing", store.balance_of("kyle") == 1250)
	_ok("replay returns original balance", int(replay.get("balance")) == 1250, str(replay))
	# A replayed id must win even when the rest of the request differs — the id is
	# the identity of the settlement, not the arguments.
	var mutated: Dictionary = store.debit("kyle", "title:gilded", 500, "tx-buy-1")
	_ok("replay ignores changed args", bool(mutated.get("duplicate")), str(mutated))
	_ok("still nothing charged", store.balance_of("kyle") == 1250)


func _check_insufficient(store: PremiumStore) -> void:
	print("insufficient funds")
	var before: int = store.balance_of("kyle")
	var r: Dictionary = store.debit("kyle", "cosmetic:5", 999_999, "tx-toobig")
	_ok("refused", not bool(r.get("ok")), str(r))
	_ok("reason is insufficient_funds", str(r.get("reason")) == "insufficient_funds", str(r))
	_ok("balance untouched", store.balance_of("kyle") == before)
	# A refused debit must leave NO ledger row: a rolled-back transaction that
	# still recorded itself would burn the id and block the real retry.
	_ok("no ledger row for a refusal", store.transaction("tx-toobig").is_empty())
	# And the id must still be usable once the account can afford it.
	var retry: Dictionary = store.debit("kyle", "title:gilded", 500, "tx-toobig")
	_ok("id reusable after refusal", bool(retry.get("ok")) and not bool(retry.get("duplicate")), str(retry))
	_ok("balance now reduced", store.balance_of("kyle") == before - 500)


func _check_bad_args(store: PremiumStore) -> void:
	print("bad args")
	var before: int = store.balance_of("kyle")
	for bad: Array in [
		["kyle", "skin:10001", 0, "tx-zero"],
		["kyle", "skin:10001", -5, "tx-neg"],
		["kyle", "skin:10001", 750, ""],
		["kyle", "", 750, "tx-noitem"],
		["", "skin:10001", 750, "tx-noacct"],
		["kyle", "skin:10001", 999_999_999, "tx-overflow"],
	]:
		var r: Dictionary = store.debit(bad[0], bad[1], bad[2], bad[3])
		_ok("refused %s" % str(bad), not bool(r.get("ok")), str(r))
	_ok("balance untouched by bad args", store.balance_of("kyle") == before)


## SUM(cost) over the ledger must equal the wallet. If these ever disagree, one
## of them wrote without the other and the balance is not trustworthy.
func _check_ledger_sums(store: PremiumStore) -> void:
	print("ledger reconciles")
	store.db.query_with_bindings(
		"SELECT COALESCE(SUM(cost), 0) AS total FROM premium_transactions WHERE account_name=?;",
		["kyle"]
	)
	var summed: int = int(store.db.query_result[0].get("total", 0))
	var wallet: int = store.balance_of("kyle")
	_ok("SUM(ledger) == balance (%d)" % wallet, summed == wallet, "sum=%d wallet=%d" % [summed, wallet])
	_ok("history returns rows", store.history("kyle", 50).size() >= 3)


## The master re-derives price from the same catalog the world quotes from. If
## these two ever resolved differently, every purchase would fail price_mismatch.
func _check_catalog_prices() -> void:
	print("catalog is reachable from the master side")
	var entry: Dictionary = PremiumCatalog.resolve("skin:10001")
	_ok("skin resolves", not entry.is_empty())
	_ok("skin has a positive cost", int(entry.get("cost", 0)) > 0, str(entry))
	_ok("junk does not resolve", PremiumCatalog.resolve("cosmetic:0").is_empty())
