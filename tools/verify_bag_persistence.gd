extends Node
## Round-trips a multi-bag player through WorldStoreSqlite on a throwaway DB.
##
## The bug this exists to catch: the players INSERT gained an inventory_bags
## column without a matching `?`, so save_player() failed for EVERY player —
## silently, because nothing checks the return value on the hot path.
##
## Despite the name it is the general PERSISTENCE-DRIFT guard, which is why the
## VaultGrants round-trip lives here too: that one is a payment record. A donor's
## entitlement that does not survive a relog means the strip takes their title
## back on the next zone change, and the whole point of the entitlement was to
## stop exactly that. Nothing about it is bag-shaped; everything about it is
## save_player-shaped.

const DB_PATH: String = "user://verify_bag_persistence.db"

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	var abs_path: String = ProjectSettings.globalize_path(DB_PATH)
	if FileAccess.file_exists(DB_PATH):
		DirAccess.remove_absolute(abs_path)

	var db: SQLite = SQLite.new()
	db.path = abs_path
	if not db.open_db():
		print("FAIL could not open scratch db")
		get_tree().quit(1)
		return
	WorldSchema.ensure_schema(db)
	var store: WorldStoreSqlite = WorldStoreSqlite.new(db)

	var player_id: int = store.create_player_character("verify_bags_acct", {
		"display_name": "BagTester",
	})
	_ck(player_id > 0, "created character (id %d)" % player_id)

	var saved: PlayerResource = store.get_player(player_id)
	_ck(saved != null, "loaded fresh character")
	if saved == null:
		_finish(db, abs_path)
		return
	_ck(saved.inventory_bags == 1, "fresh character starts with 1 bag (got %d)" % saved.inventory_bags)

	# Unlock all three bags and put an item in each.
	# Unregistered id: resolves to null, which Inventory treats as
	# non-stackable, so each add opens its own slot (same trick verify_bags uses).
	const PROBE_ID: int = 99901
	saved.inventory_bags = 3
	saved.inventory.clear()
	for bag: int in 3:
		Inventory.add_item(saved.inventory, PROBE_ID, 1, false, bag, 3)
	_ck(store.save_player(saved), "save_player() returned true for a 3-bag player")

	var reloaded: PlayerResource = store.get_player(player_id)
	_ck(reloaded != null, "reloaded character after save")
	if reloaded != null:
		_ck(reloaded.inventory_bags == 3, "bag count survives save/load (got %d)" % reloaded.inventory_bags)
		var per: Array[int] = [0, 0, 0]
		for slot_uid: Variant in reloaded.inventory:
			var bag: int = int((reloaded.inventory[slot_uid] as Dictionary).get("bag", 0))
			if bag >= 0 and bag < 3:
				per[bag] += 1
		_ck(per[0] == 1 and per[1] == 1 and per[2] == 1,
			"per-slot bag index survives save/load (got %d/%d/%d)" % per)

	# VaultGrants entitlements, which ride inside titles_json rather than in a
	# column of their own. A key added to an existing blob cannot cause the
	# placeholder drift above, but it CAN be written and never read back, which
	# looks identical from in-session: the grant works until the donor relogs.
	var packed: int = VaultSkins.pack(PlayerSkins.starter_skin_id(), VaultSkins.STYLE_GOLD)
	VaultGrants.grant_title(saved, "Diamond Donator")
	VaultGrants.grant_skin(saved, packed)
	saved.display_title = "Diamond Donator"
	_ck(store.save_player(saved), "save_player() returned true with grants set")
	var regranted: PlayerResource = store.get_player(player_id)
	_ck(regranted != null and VaultGrants.has_title(regranted, "Diamond Donator"),
		"a granted title survives save/load")
	_ck(regranted != null and VaultGrants.has_skin(regranted, packed),
		"a granted vault skin survives save/load")

	_finish(db, abs_path)


func _finish(db: SQLite, abs_path: String) -> void:
	db.close_db()
	DirAccess.remove_absolute(abs_path)
	print("\nPASS %d  FAIL %d" % [_pass, _fail])
	print("VERIFY_PASS" if _fail == 0 else "VERIFY_FAIL")
	get_tree().quit(0 if _fail == 0 else 1)


func _ck(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  ok    ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
