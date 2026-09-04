extends Node
## Proves the gather-pool ledger actually survives the players table, against a
## real throwaway SQLite file:
##
##   godot --headless --path . --mode=client res://tools/verify_gather_db_roundtrip.tscn
##
## Scene mode, not `-s`: save_player calls DailyQuestManager and PeddlerLedger,
## and those need autoloads that a headless script run does not have.
##
## The specific thing this catches is INSERT drift. Adding gather_nodes_json
## meant adding a column name, a `?` and a binding in three separate places in
## world_store_sqlite.save_player; get the count wrong and every save_player for
## every player fails silently, with no error and no bad row to find later. A
## count assertion in a script would not catch a MISORDERED binding, so this
## writes a row and reads the values back instead.
##
## Expect: VERIFY_PASS

const DB_PATH: String = "user://verify_gather_roundtrip.db"
const VEIN: String = "res://source/common/gameplay/maps/components/mineable_nodes/astralite_vein.tres"

var _fails: PackedStringArray = PackedStringArray()


func _check(ok: bool, label: String) -> void:
	if ok:
		print("  ok   %s" % label)
	else:
		_fails.append(label)
		print("  FAIL %s" % label)


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var abs_path: String = ProjectSettings.globalize_path(DB_PATH)
	if FileAccess.file_exists(DB_PATH):
		DirAccess.remove_absolute(abs_path)

	var db := SQLite.new()
	db.path = abs_path
	if not db.open_db():
		print("VERIFY_FAIL could not open %s" % abs_path)
		get_tree().quit(1)
		return
	WorldSchema.ensure_schema(db)
	var store := WorldStoreSqlite.new(db)

	print("[schema]")
	db.query("PRAGMA table_info(players);")
	var cols: PackedStringArray = PackedStringArray()
	for row: Dictionary in db.query_result:
		cols.append(str(row.get("name", "")))
	_check(cols.has("gather_nodes_json"), "players has a gather_nodes_json column")

	var vein: MineableNodeResource = load(VEIN) as MineableNodeResource
	var key: String = GatherNodeLedger.node_key("starfall_mining_cave", ^"Nodes/AstraliteVein1")

	# A character who mined a vein dry and logged off.
	var player := PlayerResource.new()
	player.player_id = 900_001
	player.account_name = "verify_gather"
	player.display_name = "VerifyGather"
	var pool: int = GatherNodeLedger.pool(player, key, vein)
	for i: int in range(pool):
		GatherNodeLedger.consume(player, key, vein)
	# Second node left partly drained, to prove counts and not just presence.
	var key2: String = GatherNodeLedger.node_key("woodland", ^"Nodes/Yew4")
	var pool2: int = GatherNodeLedger.pool(player, key2, vein)
	GatherNodeLedger.consume(player, key2, vein)

	print("[write]")
	var saved: bool = store.save_player(player)
	_check(saved, "save_player returned true (a placeholder mismatch returns false here)")

	db.query_with_bindings(
		"SELECT gather_nodes_json, display_name FROM players WHERE player_id=?;",
		[player.player_id]
	)
	_check(not db.query_result.is_empty(), "the row exists")
	if not db.query_result.is_empty():
		var row: Dictionary = db.query_result[0]
		# If a binding landed in the wrong slot the row still writes — it just
		# writes the WRONG column, which a count check would never notice.
		_check(
			str(row.get("display_name", "")) == "VerifyGather",
			"display_name still holds a name, so the bindings did not shift"
		)
		var blob: Variant = JSON.parse_string(str(row.get("gather_nodes_json", "{}")))
		_check(blob is Dictionary, "gather_nodes_json parses as a dictionary")
		if blob is Dictionary:
			_check((blob as Dictionary).has(key), "the drained vein is in the row")
			_check((blob as Dictionary).has(key2), "the partly drained tree is in the row")

	print("[read back — this is the relog]")
	var loaded: PlayerResource = store.get_player(player.player_id)
	_check(loaded != null, "get_player returned the character")
	if loaded != null:
		_check(
			GatherNodeLedger.charges(loaded, key, vein) == 0,
			"the mined-out vein is STILL EMPTY after a full DB round trip"
		)
		_check(
			GatherNodeLedger.pool(loaded, key, vein) == pool,
			"its rolled pool size (%d) came back intact" % pool
		)
		_check(
			GatherNodeLedger.charges(loaded, key2, vein) == pool2 - 1,
			"the partly drained node kept its exact count (%d)" % (pool2 - 1)
		)

	db.close_db()
	DirAccess.remove_absolute(abs_path)

	if _fails.is_empty():
		print("VERIFY_PASS gather_db_roundtrip")
		get_tree().quit(0)
	else:
		print("VERIFY_FAIL (%d)" % _fails.size())
		for line: String in _fails:
			print("  - ", line)
		get_tree().quit(1)
