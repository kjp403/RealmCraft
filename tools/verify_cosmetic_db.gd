extends SceneTree
## Prove the schema v15 migration and the player save/load round-trip still work,
## against a THROWAWAY database — never the live one.
##   godot --headless --path . -s tools/verify_cosmetic_db.gd
##
## This is the highest-risk change in the cosmetics work: the players INSERT gained a
## column, and a mismatch between columns / placeholders / bindings would fail EVERY
## player save. It also simulates the live upgrade path (a v14 database that already
## has rows) rather than only the fresh-create path.

var _fail: int = 0


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), label)
	if not ok:
		_fail += 1


func _initialize() -> void:
	var path: String = "user://_cosmetic_migration_test_%d.db" % Time.get_ticks_msec()
	var db: SQLite = SQLite.new()
	db.path = ProjectSettings.globalize_path(path)
	db.open_db()

	print("-- fresh create --")
	WorldSchema.ensure_schema(db)
	_check(_has_column(db, "cosmetic_id"), "players.cosmetic_id exists after ensure_schema")

	print("-- simulate a live v14 upgrade --")
	# Seed a COMPLETE row through the real save path first. A hand-written partial
	# INSERT trips the table's NOT NULL columns and silently stores nothing, which
	# would make this rehearsal pass vacuously.
	var legacy_pr: PlayerResource = PlayerResource.new()
	legacy_pr.init(4242, "legacy_acct", "LegacyHero", 1)
	legacy_pr.level = 7
	var seed_store: WorldStoreSqlite = WorldStoreSqlite.new(db)
	_check(seed_store.save_player(legacy_pr), "seeded a complete legacy row")
	db.query("SELECT COUNT(*) AS n FROM players WHERE player_id=4242;")
	_check(int(db.query_result[0].get("n", 0)) == 1, "legacy row is actually present pre-migration")

	# Now rewind that row to what a real v14 database looks like: no cosmetic_id
	# column, schema_version back to 14.
	db.query("ALTER TABLE players DROP COLUMN cosmetic_id;")
	db.query("UPDATE meta SET value='14' WHERE key='schema_version';")
	_check(not _has_column(db, "cosmetic_id"), "column removed for the upgrade rehearsal")

	WorldSchema.ensure_schema(db)
	_check(_has_column(db, "cosmetic_id"), "migration re-adds cosmetic_id on a v14 DB")
	db.query("SELECT player_id, display_name, level, cosmetic_id FROM players WHERE player_id=4242;")
	var legacy: Dictionary = db.query_result[0] if not db.query_result.is_empty() else {}
	_check(not legacy.is_empty(), "pre-existing row survived the migration")
	_check(int(legacy.get("level", -1)) == 7, "pre-existing row kept its data")
	_check(int(legacy.get("cosmetic_id", -1)) == 0, "pre-existing row defaults to no cosmetic")

	print("-- save / load round-trip --")
	var store: WorldStoreSqlite = WorldStoreSqlite.new(db)
	var pr: PlayerResource = PlayerResource.new()
	pr.init(9001, "test_acct", "TestHero", 1)
	pr.level = 12
	pr.cosmetic_id = 5 # aura_rainbow
	pr.owned_skins = PackedInt64Array([1])
	var saved: bool = store.save_player(pr)
	_check(saved, "save_player returned true")

	var loaded: PlayerResource = store.get_player(9001)
	_check(loaded != null, "player loads back")
	if loaded != null:
		_check(loaded.display_name == "TestHero", "display_name round-trips")
		_check(loaded.level == 12, "level round-trips")
		_check(loaded.cosmetic_id == 5, "cosmetic_id round-trips (got %d)" % loaded.cosmetic_id)

	# A player saved with no cosmetic must come back as 0, not null/garbage.
	var plain: PlayerResource = PlayerResource.new()
	plain.init(9002, "test_acct2", "PlainHero", 1)
	store.save_player(plain)
	var plain_loaded: PlayerResource = store.get_player(9002)
	_check(plain_loaded != null and plain_loaded.cosmetic_id == 0, "unset cosmetic loads as 0")

	db.close_db()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("COSMETIC_DB_%s failures=%d" % ["FAIL" if _fail else "PASS", _fail])
	quit(1 if _fail else 0)


func _has_column(db: SQLite, column: String) -> bool:
	db.query("PRAGMA table_info(players);")
	for row: Dictionary in db.query_result:
		if str(row.get("name", "")) == column:
			return true
	return false
