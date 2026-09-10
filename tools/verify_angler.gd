extends Node
## Smoke test for the three Angler modules — the Fillet Knife, the Bottomless Bait
## Bucket, and the Node Combo that spends bait for Fishing XP.
##
## Runs in SCENE mode, not `-s`: the touched files name client autoloads, and under
## `-s` every one of them would fail to COMPILE rather than to run.
##
## Expect: VERIFY_PASS
##   godot --headless --path . res://tools/verify_angler.tscn
##
## Registered in tools/run_verify.sh. That runner asserts on the literal
## VERIFY_PASS string, never on the exit code — a scene-mode gate invoked as `-s`
## dies on the missing autoloads before its first check and still exits 0.

const BEACH_SHOP: String = "res://source/common/gameplay/shops/resources/beach_angler_shop.tres"

## Every fishing hole in the game rolls its pool in this range (min_charges 10,
## max_charges 50). The combo's whole shape depends on it, so the gate asserts it
## rather than trusting the comment: retune a node's pool and the XP maths below
## silently stops describing the game.
const POOL_MIN: int = 10
const POOL_MAX: int = 50

var _pass: int = 0
var _failures: PackedStringArray = []


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	print("=== Angler module verification ===")
	_registry()
	_fillet_table()
	_fillet_convert()
	_beach_shop()
	_node_pools()
	_combo_math()
	_combo_streak()
	_bucket()
	_scripts_compile()
	print("")
	if _failures.is_empty():
		print("VERIFY_PASS angler (%d checks)" % _pass)
		get_tree().quit(0)
		return
	print("VERIFY_FAIL %d of %d checks" % [_failures.size(), _pass + _failures.size()])
	for line: String in _failures:
		print("  - %s" % line)
	get_tree().quit(1)


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_pass += 1
		print("  ok   %s%s" % [label, "" if detail.is_empty() else "  (%s)" % detail])
	else:
		_failures.append("%s%s" % [label, "" if detail.is_empty() else "  (%s)" % detail])
		printerr("  FAIL %s%s" % [label, "" if detail.is_empty() else "  (%s)" % detail])


# --- Registry ---------------------------------------------------------------

func _registry() -> void:
	print("\n[registry] new items resolve by slug")
	var bait: int = BaitBucket.bait_id()
	var bucket: int = BaitBucket.bucket_id()
	var knife: int = ContentRegistryHub.id_from_slug(&"items", FilletService.KNIFE_SLUG)
	_check("fish_bait indexed", bait > 0, "id %d" % bait)
	_check("bottomless_bait_bucket indexed", bucket > 0, "id %d" % bucket)
	_check("fillet_knife indexed", knife > 0, "id %d" % knife)
	# The Task Master design was dropped; its currency must not linger in the index
	# pointing at a deleted .tres, where load_by_id returns null rather than failing.
	_check("angler_points is fully gone",
		ContentRegistryHub.id_from_slug(&"items", &"angler_points") <= 0)


# --- Module 2 ---------------------------------------------------------------

func _fillet_table() -> void:
	print("\n[fillet] table + raw_fish tagging")
	var table: FilletTable = FilletTable.shared()
	_check("table loads", table != null)
	if table == null:
		return

	# Flat, deliberately. A tier-scaled yield makes the combo cost ~96% of the
	# catch at Fishing 1 and ~8% at Fishing 90 — backwards from "reachable from
	# the get-go". See the note on FilletTable.default_yield.
	var yields: Dictionary[int, bool] = {}
	var untagged: Array[String] = []
	for slug: String in [
		"shrimp", "herring", "cod", "trout", "salmon", "crab", "tuna", "lionfish",
		"parrot_fish", "lobster", "anglerfish", "turtle", "halibut", "stingray",
		"wolffish", "blue_lobster",
	]:
		var fish: Item = ContentRegistryHub.load_by_slug(&"items", StringName(slug)) as Item
		if fish == null or not FilletTable.is_raw_fish(fish):
			untagged.append(slug)
			continue
		yields[table.yield_for(fish)] = true
	_check("all 16 raw fish tagged", untagged.is_empty(), ", ".join(untagged))
	_check("yield is flat across the ladder", yields.size() == 1,
		"distinct yields: %s" % str(yields.keys()))
	_check("every fish yields 2 bait", yields.size() == 1 and yields.has(2))

	# A cooked fish must NOT be filletable — the tag is on the raw item only.
	var cooked: Item = ContentRegistryHub.load_by_slug(&"items", &"cooked_tuna") as Item
	_check("cooked tuna is not filletable",
		cooked != null and not FilletTable.is_raw_fish(cooked))


func _fillet_convert() -> void:
	print("\n[fillet] conversion")
	var pr: PlayerResource = PlayerResource.new()
	pr.player_id = 99010
	pr.inventory = {}
	pr.inventory_bags = 1

	var tuna: int = ContentRegistryHub.id_from_slug(&"items", &"tuna")
	var bait: int = BaitBucket.bait_id()
	var knife: int = ContentRegistryHub.id_from_slug(&"items", FilletService.KNIFE_SLUG)

	Inventory.add_item(pr.inventory, tuna, 10)
	_check("refused without a knife",
		str(FilletService.fillet(pr, tuna, 0).get("reason", "")) == "no_knife")
	_check("no fish consumed on refusal", Inventory.count(pr.inventory, tuna) == 10)

	Inventory.add_item(pr.inventory, knife, 1)
	var rows: Array[Dictionary] = FilletService.filletable(pr)
	_check("panel lists the tuna", rows.size() == 1 and int(rows[0]["id"]) == tuna,
		"%d row(s)" % rows.size())
	_check("panel previews 20 bait", not rows.is_empty() and int(rows[0]["bait"]) == 20)

	var part: Dictionary = FilletService.fillet(pr, tuna, 3)
	_check("partial fillet converts 3", int(part.get("converted", 0)) == 3)
	_check("partial fillet yields 6 bait", int(part.get("bait", 0)) == 6)
	_check("7 tuna left", Inventory.count(pr.inventory, tuna) == 7)
	_check("6 bait in the bag", Inventory.count(pr.inventory, bait) == 6)
	# The knife is a tool, never spent.
	_check("knife survives use", Inventory.count(pr.inventory, knife) == 1)

	var all: Dictionary = FilletService.fillet_all(pr)
	_check("fillet all takes the rest", int(all.get("converted", 0)) == 7)
	_check("no tuna left", Inventory.count(pr.inventory, tuna) == 0)
	_check("20 bait total", Inventory.count(pr.inventory, bait) == 20)
	_check("fillet all on an empty bag refuses",
		str(FilletService.fillet_all(pr).get("reason", "")) == "no_fish")


# --- Where the tools are sold -----------------------------------------------

func _beach_shop() -> void:
	print("\n[shop] Beach Tackle sells the tools for gold")
	var shop: ShopResource = load(BEACH_SHOP) as ShopResource
	_check("beach shop loads", shop != null)
	if shop == null:
		return

	var knife: int = ContentRegistryHub.id_from_slug(&"items", FilletService.KNIFE_SLUG)
	var bucket: int = BaitBucket.bucket_id()
	var knife_entry: Dictionary = shop.entry_for(knife)
	var bucket_entry: Dictionary = shop.entry_for(bucket)

	_check("knife is stocked", not knife_entry.is_empty(),
		"%d gold" % int(knife_entry.get("price", 0)))
	_check("bucket is stocked", not bucket_entry.is_empty(),
		"%d gold" % int(bucket_entry.get("price", 0)))
	# Gold, not a point currency: the combo has to be reachable at Fishing 1, and
	# there is no longer any points economy to gate it behind.
	_check("knife is priced in gold",
		int(knife_entry.get("currency_id", 0)) == Economy.gold_id())
	_check("bucket is priced in gold",
		int(bucket_entry.get("currency_id", 0)) == Economy.gold_id())
	# Cheap enough to be a starting tool. The level-30 rod is 200 gold; the pair
	# must not cost more than the rod ladder they support.
	var pair: int = int(knife_entry.get("price", 0)) + int(bucket_entry.get("price", 0))
	_check("the pair costs under 200 gold", pair <= 200, "%d total" % pair)
	# Bait is deliberately NOT sold — it only comes from filleting your own catch,
	# which is what makes the combo a trade rather than a gold sink.
	_check("bait is not sold", shop.entry_for(BaitBucket.bait_id()).is_empty())
	# The rods must still be there. This shop was edited in place.
	_check("the rod ladder survived the edit", shop.entries.size() == 6,
		"%d entries" % shop.entries.size())


# --- Module 4 ---------------------------------------------------------------

func _node_pools() -> void:
	print("\n[nodes] fishing pools are 10-50")
	var dir: String = "res://source/common/gameplay/maps/components/mineable_nodes/"
	var wrong: Array[String] = []
	var seen: int = 0
	for file: String in ResourceLoader.list_directory(dir):
		if not file.begins_with("fishing_hole_") or not file.ends_with(".tres"):
			continue
		var data: MineableNodeResource = load(dir + file) as MineableNodeResource
		if data == null:
			continue
		seen += 1
		if data.min_charges != POOL_MIN or data.max_charges != POOL_MAX:
			wrong.append("%s %d-%d" % [file, data.min_charges, data.max_charges])
	_check("every fishing hole found", seen >= 12, "%d holes" % seen)
	_check("pools are all %d-%d" % [POOL_MIN, POOL_MAX], wrong.is_empty(), ", ".join(wrong))


func _combo_math() -> void:
	print("\n[combo] multiplier curve")
	_check("no streak = no bonus", is_equal_approx(FishingComboManager.multiplier_for(0), 1.0))
	_check("1 catch = +2%", is_equal_approx(FishingComboManager.multiplier_for(1), 1.02))
	_check("10 catches = +20%", is_equal_approx(FishingComboManager.multiplier_for(10), 1.20))
	_check("20 catches hits the cap", is_equal_approx(FishingComboManager.multiplier_for(20), 1.40))
	_check("cap holds past 20", is_equal_approx(FishingComboManager.multiplier_for(500), 1.40))
	_check("negative streak is safe", is_equal_approx(FishingComboManager.multiplier_for(-3), 1.0))

	# The payoff curve the design rests on: a floor-roll node is worth noticeably
	# less than a max-roll one, which is what makes finding a 50 exciting. If a
	# retune ever flattens that spread, this is where it shows up.
	var small: float = _node_average(POOL_MIN)
	var big: float = _node_average(POOL_MAX)
	_check("a %d-pool node averages ~+9%%" % POOL_MIN, absf(small - 1.09) < 0.01, "x%.3f" % small)
	_check("a %d-pool node averages ~+32%%" % POOL_MAX, absf(big - 1.316) < 0.01, "x%.3f" % big)
	_check("big nodes are worth much more", big - small > 0.20,
		"+%.1f%% spread" % ((big - small) * 100.0))
	# Only pools past the cap point get there at all, so hitting +40% stays an
	# event rather than the default.
	var cap_at: int = int(round(
		(FishingComboManager.MAX_MULTIPLIER - 1.0) / FishingComboManager.STEP
	)) + 1
	_check("the cap needs %d catches" % cap_at, cap_at > POOL_MIN and cap_at < POOL_MAX,
		"%d, between %d and %d" % [cap_at, POOL_MIN, POOL_MAX])


## Average XP multiplier across one node of [param pool] catches, worked start to
## finish without breaking the streak.
func _node_average(pool: int) -> float:
	var total: float = 0.0
	for n: int in pool:
		total += FishingComboManager.multiplier_for(n)
	return total / float(pool)


## The combo rules themselves, not just the curve: bait is spent per ADVANCE,
## the first catch is free, and each reset condition actually fires.
func _combo_streak() -> void:
	print("\n[combo] register_catch rules")
	var pr: PlayerResource = PlayerResource.new()
	pr.player_id = 99003
	pr.inventory = {}
	pr.inventory_bags = 1
	Inventory.add_item(pr.inventory, BaitBucket.bucket_id(), 1)
	pr.stored_bait = 100

	var spot := Vector2(500.0, 500.0)
	FishingComboManager.clear(pr.player_id)

	# First catch starts the streak: no bonus, and no bait spent.
	var first: float = FishingComboManager.register_catch(pr, pr.player_id, "pondA", spot)
	_check("first catch pays no bonus", is_equal_approx(first, 1.0))
	_check("first catch costs no bait", BaitBucket.stored(pr) == 100,
		"%d left" % BaitBucket.stored(pr))

	var second: float = FishingComboManager.register_catch(pr, pr.player_id, "pondA", spot)
	_check("second catch pays +2%", is_equal_approx(second, 1.02))
	_check("second catch spent one bait", BaitBucket.stored(pr) == 99)
	_check("streak is 1", FishingComboManager.streak_of(pr.player_id) == 1)

	for _i: int in 5:
		FishingComboManager.register_catch(pr, pr.player_id, "pondA", spot)
	_check("streak reached 6", FishingComboManager.streak_of(pr.player_id) == 6,
		"%d" % FishingComboManager.streak_of(pr.player_id))
	_check("bait spent once per advance", BaitBucket.stored(pr) == 94,
		"%d left" % BaitBucket.stored(pr))

	# Moving past the tolerance breaks it. Movement is detected by POSITION, not
	# velocity — a server-side velocity read is always zero here.
	var far: Vector2 = spot + Vector2(FishingComboManager.MOVE_TOLERANCE_PX + 8.0, 0.0)
	_check("walking away resets the streak",
		is_equal_approx(FishingComboManager.register_catch(pr, pr.player_id, "pondA", far), 1.0))
	_check("streak restarted at 0", FishingComboManager.streak_of(pr.player_id) == 0)

	# A small shuffle must NOT break it.
	FishingComboManager.clear(pr.player_id)
	FishingComboManager.register_catch(pr, pr.player_id, "pondA", spot)
	var nudge: Vector2 = spot + Vector2(FishingComboManager.MOVE_TOLERANCE_PX - 8.0, 0.0)
	_check("a small shuffle keeps the streak",
		is_equal_approx(FishingComboManager.register_catch(pr, pr.player_id, "pondA", nudge), 1.02))

	# Switching spots breaks it — the rule that makes a worked-out node end the run.
	_check("a different node resets the streak",
		is_equal_approx(FishingComboManager.register_catch(pr, pr.player_id, "pondB", spot), 1.0))

	# Running dry breaks it, and cannot go negative.
	FishingComboManager.clear(pr.player_id)
	pr.stored_bait = 1
	FishingComboManager.register_catch(pr, pr.player_id, "pondC", spot)
	_check("last bait still advances",
		is_equal_approx(FishingComboManager.register_catch(pr, pr.player_id, "pondC", spot), 1.02))
	_check("running dry resets the streak",
		is_equal_approx(FishingComboManager.register_catch(pr, pr.player_id, "pondC", spot), 1.0))
	_check("bait cannot go negative", BaitBucket.stored(pr) == 0)

	# No bucket at all: the combo simply never starts paying.
	var bare: PlayerResource = PlayerResource.new()
	bare.player_id = 99004
	bare.inventory = {}
	bare.inventory_bags = 1
	FishingComboManager.clear(bare.player_id)
	FishingComboManager.register_catch(bare, bare.player_id, "pondA", spot)
	_check("no bucket = no combo",
		is_equal_approx(FishingComboManager.register_catch(bare, bare.player_id, "pondA", spot), 1.0))

	FishingComboManager.clear(pr.player_id)
	FishingComboManager.clear(bare.player_id)
	_check("clear drops tracking", FishingComboManager.streak_of(pr.player_id) == 0)


# --- Module 3 ---------------------------------------------------------------

func _bucket() -> void:
	print("\n[bait] bucket fill / spend")
	var pr: PlayerResource = PlayerResource.new()
	pr.player_id = 99001
	pr.inventory = {}
	pr.inventory_bags = 1

	var bait_id: int = BaitBucket.bait_id()
	var bucket_id: int = BaitBucket.bucket_id()

	# No bucket in the bag: a fill must refuse, and bait must be unreachable.
	Inventory.add_item(pr.inventory, bait_id, 50)
	_check("fill refused without the bucket",
		str(BaitBucket.fill_from_inventory(pr).get("reason", "")) == "no_bucket")
	_check("has_bait false without the bucket", not BaitBucket.has_bait(pr))

	Inventory.add_item(pr.inventory, bucket_id, 1)
	var filled: Dictionary = BaitBucket.fill_from_inventory(pr)
	_check("fill moves the whole stack", int(filled.get("moved", 0)) == 50,
		"moved %d" % int(filled.get("moved", 0)))
	_check("bag no longer holds loose bait", Inventory.count(pr.inventory, bait_id) == 0)
	_check("bucket holds 50", BaitBucket.stored(pr) == 50)
	_check("has_bait true", BaitBucket.has_bait(pr))

	_check("consume spends one", BaitBucket.consume_bait(pr, 1) and BaitBucket.stored(pr) == 49)
	_check("over-spend is refused whole",
		not BaitBucket.consume_bait(pr, 999) and BaitBucket.stored(pr) == 49,
		"still %d" % BaitBucket.stored(pr))

	# The cap, and the honest report when it truncates.
	pr.stored_bait = BaitBucket.MAX_STORED - 10
	Inventory.add_item(pr.inventory, bait_id, 40)
	var capped: Dictionary = BaitBucket.fill_from_inventory(pr)
	_check("fill stops at the cap", BaitBucket.stored(pr) == BaitBucket.MAX_STORED)
	_check("overflow reported, not eaten",
		bool(capped.get("capped", false)) and Inventory.count(pr.inventory, bait_id) == 30,
		"%d left in bag" % Inventory.count(pr.inventory, bait_id))

	# The economy in one line: at a flat 2 bait per fish, filleting half a max-roll
	# node funds a whole next one. If default_yield ever drops to 1, this fails and
	# says so, because sustaining the combo would then cost the entire catch.
	var funded: int = (POOL_MAX / 2) * FilletTable.shared().default_yield
	_check("half a max node funds a full one", funded >= POOL_MAX - 1,
		"%d bait vs %d needed" % [funded, POOL_MAX - 1])


# --- Compile check ----------------------------------------------------------

## Every script and scene this work added or touched, loaded so a parse error in a
## client-only file is caught HERE rather than the first time a player right-clicks
## a knife. This is why the gate is scene-mode: under `-s` these scripts name
## autoloads that do not exist, and every one would "fail" for the wrong reason.
const TOUCHED_SCRIPTS: Array[String] = [
	"res://source/common/gameplay/fishing/fishing_combo_manager.gd",
	"res://source/common/gameplay/fishing/bait_bucket.gd",
	"res://source/common/gameplay/fishing/fillet_recipe.gd",
	"res://source/common/gameplay/fishing/fillet_table.gd",
	"res://source/common/gameplay/fishing/fillet_service.gd",
	"res://source/common/gameplay/items/angler_tool_item.gd",
	"res://source/common/gameplay/items/fillet_knife_item.gd",
	"res://source/common/gameplay/items/bait_bucket_item.gd",
	"res://source/common/gameplay/characters/player/player_resource.gd",
	"res://source/common/gameplay/maps/components/mineable_node.gd",
	"res://source/client/ui/menus/fillet/fillet_menu.gd",
	"res://source/client/ui/compact_menus/compact_menu_host.gd",
	"res://source/server/world/components/world_server.gd",
	"res://source/server/world/database/world_schema.gd",
	"res://source/server/world/database/world_store_sqlite.gd",
	"res://source/server/world/components/data_request_handlers/bait.fill.gd",
	"res://source/server/world/components/data_request_handlers/fillet.list.gd",
	"res://source/server/world/components/data_request_handlers/fillet.convert.gd",
]

const TOUCHED_SCENES: Array[String] = [
	"res://source/client/ui/menus/fillet/fillet_menu.tscn",
]


func _scripts_compile() -> void:
	print("\n[compile] every touched script + scene loads")
	var broken: Array[String] = []
	for path: String in TOUCHED_SCRIPTS:
		var script: GDScript = load(path) as GDScript
		# can_instantiate() is false for a script that failed to compile — a plain
		# non-null load() still returns the broken resource.
		if script == null or not script.can_instantiate():
			broken.append(path.get_file())
	_check("%d scripts compile" % TOUCHED_SCRIPTS.size(), broken.is_empty(), ", ".join(broken))

	var bad_scenes: Array[String] = []
	for path: String in TOUCHED_SCENES:
		var scene: PackedScene = load(path) as PackedScene
		if scene == null or not scene.can_instantiate():
			bad_scenes.append(path.get_file())
	_check("%d scenes instantiate" % TOUCHED_SCENES.size(), bad_scenes.is_empty(),
		", ".join(bad_scenes))
