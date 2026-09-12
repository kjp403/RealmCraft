class_name PremiumStore
extends RefCounted
## Every read and write of premium currency goes through here. Mirrors
## [WorldStoreSqlite]: holds the handle, everything uses query_with_bindings.
##
## THE ONLY METHOD THAT MOVES MONEY IS [method debit], and it is wrapped in a
## real SQL transaction. The master's RPC handlers run synchronously on its main
## loop, so two purchases cannot interleave - but that is not what the
## transaction is for. It is for the crash: without it, a process that dies
## between the balance UPDATE and the ledger INSERT leaves a player charged with
## no record, or a record with no charge. BEGIN/COMMIT makes those one event.
##
## Amounts are ints. No floats anywhere near a balance - 0.1 + 0.2 is not 0.3 and
## a currency that rounds is a currency that leaks.

## Refuses a single movement larger than this. A cost is validated against the
## catalog before it ever reaches here, so this is the backstop against a bad
## call site rather than the primary check - but an int overflow in a balance is
## not a bug anyone should have to debug twice.
const MAX_MOVEMENT: int = 100_000_000

const KIND_PURCHASE: String = "purchase"
const KIND_CREDIT: String = "credit"

var db: SQLite


func _init(_db: SQLite) -> void:
	db = _db


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func begin() -> bool:
	return db.query("BEGIN IMMEDIATE;")


func commit() -> bool:
	return db.query("COMMIT;")


func rollback() -> bool:
	return db.query("ROLLBACK;")


## Current balance. An account with no wallet row reads as 0 rather than an
## error: never having spent anything is not a failure state, and the balance
## endpoint must answer the same way for a new account as for a spent-out one.
func balance_of(account_name: String) -> int:
	var key: String = _normalize(account_name)
	if key.is_empty():
		return 0
	db.query_with_bindings(
		"SELECT balance FROM premium_balances WHERE account_name=?;",
		[key]
	)
	if db.query_result.is_empty():
		return 0
	return int(db.query_result[0].get("balance", 0))


## The settled transaction with this id, or {} when it has not been seen.
## Used to answer a replay with the ORIGINAL outcome instead of a bare conflict.
func transaction(transaction_id: String) -> Dictionary:
	var key: String = transaction_id.strip_edges()
	if key.is_empty():
		return {}
	db.query_with_bindings(
		"SELECT * FROM premium_transactions WHERE transaction_id=?;",
		[key]
	)
	if db.query_result.is_empty():
		return {}
	return db.query_result[0].duplicate()


## Spend [param cost] and record it, atomically.
##
## Returns one of:
##   {"ok": true,  "balance": int, "duplicate": false}
##   {"ok": true,  "balance": int, "duplicate": true }   already settled, unchanged
##   {"ok": false, "reason": "insufficient_funds", "balance": int}
##   {"ok": false, "reason": "bad_args" | "write_failed", "balance": int}
##
## A duplicate is reported as ok:true because it IS the settled state the caller
## asked for - the HTTP layer decides that a replay deserves a 409, but nothing
## here has failed and nothing has been charged twice.
func debit(
	account_name: String,
	item_id: String,
	cost: int,
	transaction_id: String
) -> Dictionary:
	var key: String = _normalize(account_name)
	var tx: String = transaction_id.strip_edges()
	var item: String = item_id.strip_edges()
	if key.is_empty() or tx.is_empty() or item.is_empty():
		return {"ok": false, "reason": "bad_args", "balance": 0}
	if cost <= 0 or cost > MAX_MOVEMENT:
		return {"ok": false, "reason": "bad_args", "balance": balance_of(key)}

	# Checked BEFORE the transaction so the common replay costs one indexed read
	# rather than a write lock. The PRIMARY KEY inside the transaction is what
	# actually guarantees it; this is the fast path, not the guarantee.
	var settled: Dictionary = transaction(tx)
	if not settled.is_empty():
		return {
			"ok": true,
			"duplicate": true,
			"balance": int(settled.get("balance_after", balance_of(key))),
		}

	begin()
	# Re-read INSIDE the transaction. The value read before BEGIN is not the one
	# being decremented, and spending against a stale balance is how a wallet
	# goes negative.
	db.query_with_bindings(
		"SELECT balance FROM premium_balances WHERE account_name=?;",
		[key]
	)
	var current: int = 0
	if not db.query_result.is_empty():
		current = int(db.query_result[0].get("balance", 0))
	if current < cost:
		rollback()
		return {"ok": false, "reason": "insufficient_funds", "balance": current}

	var remaining: int = current - cost
	var now: int = _now_ms()
	# Guarded UPDATE: the WHERE re-asserts the balance we decided against, so if
	# anything did change underneath, zero rows are touched and we abort rather
	# than overwrite someone else's write with our arithmetic.
	db.query_with_bindings(
		"UPDATE premium_balances SET balance=?, updated_ms=? "
		+ "WHERE account_name=? AND balance=?;",
		[remaining, now, key, current]
	)
	if not _rows_changed():
		rollback()
		return {"ok": false, "reason": "write_failed", "balance": current}

	# Negative because it is a debit - see the schema note on SUM(cost).
	var wrote: bool = db.query_with_bindings(
		"INSERT INTO premium_transactions"
		+ "(transaction_id, account_name, item_id, cost, balance_after, kind, created_ms) "
		+ "VALUES(?, ?, ?, ?, ?, ?, ?);",
		[tx, key, item, -cost, remaining, KIND_PURCHASE, now]
	)
	if not wrote:
		# Almost always the PRIMARY KEY rejecting a replay that raced the read
		# above. Either way the charge does not stand.
		rollback()
		var after: Dictionary = transaction(tx)
		if not after.is_empty():
			return {
				"ok": true,
				"duplicate": true,
				"balance": int(after.get("balance_after", current)),
			}
		return {"ok": false, "reason": "write_failed", "balance": current}

	commit()
	return {"ok": true, "duplicate": false, "balance": remaining}


## Add currency. There is no automated top-up path yet - this is what a manual
## grant (and, later, a payment webhook) calls. Idempotent on transaction_id for
## the same reason a debit is: a retried webhook must not pay out twice.
func credit(
	account_name: String,
	amount: int,
	transaction_id: String,
	reason: String = "grant"
) -> Dictionary:
	var key: String = _normalize(account_name)
	var tx: String = transaction_id.strip_edges()
	if key.is_empty() or tx.is_empty():
		return {"ok": false, "reason": "bad_args", "balance": 0}
	if amount <= 0 or amount > MAX_MOVEMENT:
		return {"ok": false, "reason": "bad_args", "balance": balance_of(key)}

	var settled: Dictionary = transaction(tx)
	if not settled.is_empty():
		return {
			"ok": true,
			"duplicate": true,
			"balance": int(settled.get("balance_after", balance_of(key))),
		}

	begin()
	db.query_with_bindings(
		"SELECT balance FROM premium_balances WHERE account_name=?;",
		[key]
	)
	var current: int = 0
	var exists: bool = not db.query_result.is_empty()
	if exists:
		current = int(db.query_result[0].get("balance", 0))
	var total: int = current + amount
	var now: int = _now_ms()

	if exists:
		db.query_with_bindings(
			"UPDATE premium_balances SET balance=?, updated_ms=? "
			+ "WHERE account_name=? AND balance=?;",
			[total, now, key, current]
		)
	else:
		db.query_with_bindings(
			"INSERT INTO premium_balances(account_name, balance, updated_ms) VALUES(?, ?, ?);",
			[key, total, now]
		)
	if not _rows_changed():
		rollback()
		return {"ok": false, "reason": "write_failed", "balance": current}

	var wrote: bool = db.query_with_bindings(
		"INSERT INTO premium_transactions"
		+ "(transaction_id, account_name, item_id, cost, balance_after, kind, created_ms) "
		+ "VALUES(?, ?, ?, ?, ?, ?, ?);",
		[tx, key, reason, amount, total, KIND_CREDIT, now]
	)
	if not wrote:
		rollback()
		return {"ok": false, "reason": "write_failed", "balance": current}

	commit()
	return {"ok": true, "duplicate": false, "balance": total}


## Most recent movements on an account, newest first. For an audit / support
## question, not for the game client.
func history(account_name: String, limit: int = 50) -> Array:
	var key: String = _normalize(account_name)
	if key.is_empty():
		return []
	db.query_with_bindings(
		"SELECT * FROM premium_transactions WHERE account_name=? "
		+ "ORDER BY created_ms DESC LIMIT ?;",
		[key, clampi(limit, 1, 500)]
	)
	return db.query_result.duplicate(true)


## Account names are lower-cased everywhere they are stored - AuthenticationManager
## normalizes on create and on lookup, so "Kyle" and "kyle" are one account and
## must be one wallet.
static func _normalize(account_name: String) -> String:
	return account_name.strip_edges().to_lower()


## True when the statement actually touched a row. A guarded UPDATE that matches
## nothing is not an error to SQLite, so without this a no-op write reads as a
## success and the ledger row gets written against a balance that never moved.
func _rows_changed() -> bool:
	db.query("SELECT changes() AS n;")
	if db.query_result.is_empty():
		return false
	return int(db.query_result[0].get("n", 0)) > 0
