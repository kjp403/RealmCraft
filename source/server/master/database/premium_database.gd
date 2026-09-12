class_name PremiumDatabase
extends Node
## Owns the master's premium-currency SQLite handle. Mirrors [WorldDatabase]:
## resolve a path, open, ensure schema, hand out a store.
##
## Separate file from the world's classic.db on purpose. Different lifecycle
## (the master outlives every world restart), different key (account, not
## character), and a wallet must not be inside a database that a world rollback
## would take with it.

var database_path: String
var db: SQLite
var store: PremiumStore


func _ready() -> void:
	start_database()


func start_database() -> void:
	configure_database()
	open_database()
	PremiumSchema.ensure_schema(db)
	store = PremiumStore.new(db)
	ServerLog.info("Premium currency database ready (%s)." % database_path)


func configure_database() -> void:
	const FILE_NAME: String = "premium.db"
	var legacy_res_path: String = "res://source/server/master/data/" + FILE_NAME
	# NEVER key this off OS.has_feature("editor") - the VPS runs the editor
	# binary, so that feature is true in production. Use ServerEnvironment, the
	# same way WorldDatabase does.
	if ServerEnvironment.use_user_data_paths():
		database_path = "user://db/" + FILE_NAME
		ServerEnvironment.migrate_sqlite_if_needed(database_path, legacy_res_path)
	else:
		database_path = legacy_res_path


func open_database() -> void:
	if ServerEnvironment.use_user_data_paths():
		DirAccess.make_dir_recursive_absolute("user://db")
	else:
		DirAccess.make_dir_recursive_absolute("res://source/server/master/data")

	db = SQLite.new()
	db.path = database_path
	db.open_db()
	# Same durability settings as the world DB. WAL lets `sqlite3 .backup` run
	# alongside writes without tearing, and survives a crash mid-write; NORMAL is
	# the standard safe+fast sync level under WAL. Connection settings, not
	# schema - no migration, no wipe.
	db.query("PRAGMA journal_mode=WAL;")
	db.query("PRAGMA synchronous=NORMAL;")
	# Off by default in SQLite and worth paying for here: the ledger references
	# nothing, but a future migration that adds a reference gets the check for
	# free rather than discovering it was never on.
	db.query("PRAGMA foreign_keys=ON;")


## Current balance for an account. Safe before _ready has run (returns 0), so a
## caller racing master start-up gets a wrong-but-harmless answer rather than a
## null dereference.
func balance_of(account_name: String) -> int:
	if store == null:
		return 0
	return store.balance_of(account_name)
