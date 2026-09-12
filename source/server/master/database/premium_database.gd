class_name PremiumDatabase
extends Node
## Owns the master's premium-currency SQLite handle. Mirrors [WorldDatabase]:
## resolve a path, open, ensure schema, hand out a store.
##
## Separate file from the world's classic.db on purpose. Different lifecycle
## (the master outlives every world restart), different key (account, not
## character), and a wallet must not be inside a database that a world rollback
## would take with it.

## How often the wallet is snapshotted. The world backs up on its periodic save;
## the master has no such tick, so this brings its own. Hourly because the data
## is small and the cost of losing an hour of top-ups is somebody's money.
const BACKUP_INTERVAL_S: float = 3600.0

## Snapshots kept before the oldest is deleted. Ten hours of history at the
## interval above - enough to notice a problem and roll back past it.
const BACKUP_KEEP: int = 10

var database_path: String
var db: SQLite
var store: PremiumStore

var _backup_timer: Timer


func _ready() -> void:
	start_database()
	_start_backup_timer()


## The backup schedule. A wallet that is never snapshotted is one disk fault away
## from every purchase anyone has ever made.
func _start_backup_timer() -> void:
	_backup_timer = Timer.new()
	_backup_timer.wait_time = BACKUP_INTERVAL_S
	_backup_timer.autostart = true
	_backup_timer.timeout.connect(func() -> void: backup_database())
	add_child(_backup_timer)
	# One immediately on boot, so a restart always leaves a recent snapshot and a
	# server that keeps crash-looping still produces one.
	backup_database.call_deferred()


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


## Snapshot the wallet into user://db_backups, oldest pruned past [param keep_last].
##
## CHECKPOINT FIRST, ALWAYS. Under WAL the recent writes live in premium.db-wal,
## not in premium.db, so copying the .db alone silently omits everything since
## the last automatic checkpoint. The world database learned this the hard way -
## a 332 KB .db beside a 4 MB uncheckpointed -wal, i.e. hours missing from every
## "successful" backup. TRUNCATE folds the -wal back in and keeps it from
## ballooning. Runs on the server's own connection, so it always has the lock.
func backup_database(keep_last: int = BACKUP_KEEP) -> bool:
	if database_path.is_empty() or not FileAccess.file_exists(database_path):
		return false
	if db != null:
		db.query("PRAGMA wal_checkpoint(TRUNCATE);")

	var backup_dir: String = "user://db_backups"
	DirAccess.make_dir_recursive_absolute(backup_dir)

	var name_without_ext: String = database_path.get_file().get_basename()
	var backup_path: String = "%s/%s_%d.db" % [
		backup_dir, name_without_ext, int(Time.get_unix_time_from_system())
	]

	var src: FileAccess = FileAccess.open(database_path, FileAccess.READ)
	if src == null:
		ServerLog.warn("Premium backup: could not read %s." % database_path)
		return false
	var contents: PackedByteArray = src.get_buffer(src.get_length())
	src.close()

	var dst: FileAccess = FileAccess.open(backup_path, FileAccess.WRITE)
	if dst == null:
		ServerLog.warn("Premium backup: could not write %s." % backup_path)
		return false
	dst.store_buffer(contents)
	dst.close()

	_rotate_backups(backup_dir, name_without_ext, keep_last)
	return true


## Keeps the newest [param keep_last] snapshots for this database and deletes the
## rest. Filtered by prefix so it can share a directory with the world's backups
## without either rotating the other away.
func _rotate_backups(backup_dir: String, name_prefix: String, keep_last: int) -> void:
	var dir: DirAccess = DirAccess.open(backup_dir)
	if dir == null:
		return
	var backups: Array[String] = []
	dir.list_dir_begin()
	var file: String = dir.get_next()
	while not file.is_empty():
		if not dir.current_is_dir() and file.begins_with(name_prefix + "_") and file.ends_with(".db"):
			backups.append(file)
		file = dir.get_next()
	dir.list_dir_end()

	# Names carry a zero-padded-free unix stamp, so a plain sort is chronological
	# for every timestamp of the same digit count - which covers the next two
	# centuries. Newest last, so the head of the list is what gets dropped.
	backups.sort()
	var excess: int = backups.size() - maxi(1, keep_last)
	for i: int in maxi(0, excess):
		dir.remove(backups[i])
