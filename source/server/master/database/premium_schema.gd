extends RefCounted
class_name PremiumSchema
## Schema for the master's premium-currency database. Versioned exactly like
## [WorldSchema] so a migration is added, never edited in place.
##
## WHY THE MASTER AND NOT THE WORLD. Currency is per ACCOUNT, and the account
## collection lives here. The world DB (classic.db) is keyed by player_id - one
## row per character - so a balance there would be per-character, and a player
## with three characters would have three wallets.
##
## WHY SQLITE AND NOT THE ACCOUNT .tres. Money needs two things a Godot Resource
## cannot give: a real transaction (deduct and ledger row commit together or not
## at all - ResourceSaver has no such thing, and a crash mid-save either loses
## the charge or double-spends it) and a UNIQUE constraint for idempotency. It
## also puts the data inside the `sqlite3 .backup` routine instead of the
## user:// blind spot that already loses bans on a restore.


static func ensure_schema(db: SQLite) -> void:
	_create_table_if_missing(db, "meta", {
		"key": {"data_type": "text", "primary_key": true, "not_null": true},
		"value": {"data_type": "text", "not_null": true}
	})

	var version: int = _get_schema_version(db)
	if version < 1:
		_migration_v1(db)
		_set_schema_version(db, 1)


## One wallet per account, keyed by the lower-cased username - the same string
## AuthenticationManager keys its collection by and the same one the world sends
## as PlayerResource.account_name. Keying on the name rather than the numeric
## account id keeps this readable in a manual audit and matches what the world
## actually has to hand.
static func _migration_v1(db: SQLite) -> void:
	_create_table_if_missing(db, "premium_balances", {
		"account_name": {"data_type": "text", "primary_key": true, "not_null": true},
		"balance": {"data_type": "int", "not_null": true, "default": 0},
		"updated_ms": {"data_type": "int", "not_null": true, "default": 0},
	})

	# THE LEDGER, AND THE IDEMPOTENCY GUARD IN ONE. transaction_id is the PRIMARY
	# KEY, so a replayed purchase cannot insert a second row - SQLite refuses it
	# and the store reads that refusal as "already settled" rather than charging
	# again. Every debit is also a permanent record of what was bought for what,
	# which is the only way to answer "why is my balance short".
	_create_table_if_missing(db, "premium_transactions", {
		"transaction_id": {"data_type": "text", "primary_key": true, "not_null": true},
		"account_name": {"data_type": "text", "not_null": true},
		"item_id": {"data_type": "text", "not_null": true},
		# Signed: a debit is negative, a top-up positive, so SUM(cost) over an
		# account is its balance and the two can never disagree silently.
		"cost": {"data_type": "int", "not_null": true},
		"balance_after": {"data_type": "int", "not_null": true},
		"kind": {"data_type": "text", "not_null": true},
		"created_ms": {"data_type": "int", "not_null": true},
	})
	db.query(
		"CREATE INDEX IF NOT EXISTS idx_premium_tx_account "
		+ "ON premium_transactions(account_name, created_ms DESC);"
	)


static func _create_table_if_missing(db: SQLite, table: String, dict: Dictionary) -> void:
	db.query_with_bindings(
		"SELECT name FROM sqlite_master WHERE type='table' AND name=?;",
		[table]
	)
	if db.query_result.is_empty():
		db.create_table(table, dict)


static func _get_schema_version(db: SQLite) -> int:
	db.query_with_bindings("SELECT value FROM meta WHERE key=?;", ["schema_version"])
	if db.query_result.is_empty():
		return 0
	var row: Dictionary = db.query_result[0]
	return int(row.get("value", "0"))


static func _set_schema_version(db: SQLite, v: int) -> void:
	db.query_with_bindings(
		"INSERT OR REPLACE INTO meta(key, value) VALUES(?, ?);",
		["schema_version", str(v)]
	)
