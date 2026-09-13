extends Node
## Round-trips [member PlayerResource.cosmetic_slots] through the REAL world
## database: save, reload, compare.
##
## WHY A WHOLE TOOL FOR ONE FIELD. Adding a column means touching three things
## that must agree - the column list, the placeholder count and the values array
## - and when they disagree SQLite fails the whole INSERT and save_player()
## returns as if it worked. Every player silently stops saving. The only way to
## know is to write a row and read it back, which is what this does.
##
## RUNS AS A SCENE, NOT A `-s` TOOL. `-s` starts a bare SceneTree with no
## autoloads, and PlayerResource pulls in scripts that reference Client and
## ClientState - under `-s` they fail to COMPILE, so get_player_resource() hands
## back null and the probe "fails" for a reason that has nothing to do with the
## database. Same trap, same fix, as tools/render_vault_previews.
##
## Run with the WORLD SERVER STOPPED (it holds the database open):
##   godot --headless --path . --mode=client res://tools/verify_cosmetic_slots.tscn

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _ok(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		print("  ok    %s" % label)
		return
	_failures += 1
	print("  FAIL  %s  %s" % [label, detail])


func _run() -> void:
	var db: WorldDatabase = WorldDatabase.new()
	add_child(db)
	# start_database, not open_database: the latter opens the file and stops, so
	# `store` stays null and every call through it dies on Nil. This is also what
	# picks the right path for the environment and runs the migrations, which is
	# the half of the schema this probe is actually here to exercise.
	db.start_database({"name": "Classic"})
	print("database: %s" % db.database_path)

	# A player id far above anything a real character will get, so a rerun on a
	# live database cannot land on somebody's character.
	const PROBE_ID: int = 999000001

	var res: PlayerResource = PlayerResource.new()
	res.player_id = PROBE_ID
	res.account_name = "verify_slots"
	res.display_name = "VerifySlots"
	res.cosmetic_slots = {
		&"aura": 1001,
		&"halo": 1002,
		&"trail": 1003,
		&"flourish": 1004,
		&"departure": 1005,
		&"weapon": 1006,
		&"pet": 1007,
	}
	res.cosmetic_id = 1001
	res.weapon_cosmetic_id = 1006

	print("save")
	db.save_player(res)
	# save_player returns nothing - the store swallows the result, which is the
	# whole reason a misaligned INSERT is silent. The reload below is the assert.
	_ok("save_player did not crash", true)

	print("")
	print("reload")
	var back: PlayerResource = db.get_player_resource(PROBE_ID)
	_ok("row came back", back != null)
	if back == null:
		_finish()
		return
	for slot: StringName in [&"aura", &"halo", &"trail", &"flourish", &"departure", &"weapon", &"pet"]:
		_ok(
			"%s survived" % slot,
			int(back.cosmetic_slots.get(slot, 0)) == int(res.cosmetic_slots[slot]),
			str(back.cosmetic_slots)
		)

	print("")
	print("unequipping clears the slot rather than storing a 0")
	back.cosmetic_slots.erase(&"halo")
	db.save_player(back)
	var cleared: PlayerResource = db.get_player_resource(PROBE_ID)
	_ok("halo is gone", not cleared.cosmetic_slots.has(&"halo"), str(cleared.cosmetic_slots))
	_ok("aura untouched", int(cleared.cosmetic_slots.get(&"aura", 0)) == 1001)

	_finish()


func _finish() -> void:
	print("")
	if _failures == 0:
		print("verify_cosmetic_slots: PASS")
	else:
		print("verify_cosmetic_slots: FAIL (%d)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
