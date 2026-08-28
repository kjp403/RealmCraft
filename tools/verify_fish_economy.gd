extends Node
## Gate for the fish-economy pass (tools/build_fish_economy.py).
##
##   godot --path . --mode=client res://tools/verify_fish_economy.tscn
##
## Scene mode, not `-s`: a headless script run has no autoloads, so
## consumable_item.gd (which reads ClientState) fails to compile and every
## cooked-fish .tres then loads with a null script and a null item — the checks
## below would all "fail" against content that is perfectly fine.
##
## Prints VERIFY_PASS only when every claim the pass makes holds against the
## resources as Godot actually loads them:
##   * no tier-3 chest table still carries a raw or cooked fish,
##   * every tier-3 chest pays 5-15 Vial of Water,
##   * every named zone's InstanceResource rolls its fish on zone_kill_loot at
##     the authored amount and chance,
##   * every drop resolves to a registered item id (a LootDrop whose item has no
##     metadata/id is skipped silently at runtime, so it has to be caught here).

const CHESTS := "res://source/common/gameplay/combat/chests/"
const INSTANCES := "res://source/common/gameplay/maps/instance/instance_collection/"

const FISH_MARKERS := ["/items/materials/fish/", "/items/consumables/food/cooked_"]
const VIAL_SLUG := &"vial_of_water"

## instance file -> [item slug, min, max, chance]
const ZONES := {
	"biomes/woodland.tres": [&"cooked_lionfish", 1, 2, 0.1],
	"biomes/woodland_east.tres": [&"cooked_lionfish", 1, 2, 0.1],
	"biomes/fungus_cave.tres": [&"cooked_turtle", 1, 2, 0.1],
	"biomes/bandit_hideout.tres": [&"cooked_parrot_fish", 1, 2, 0.1],
	"biomes/forest.tres": [&"cooked_anglerfish", 1, 2, 0.1],
	"biomes/sewers.tres": [&"cooked_anglerfish", 2, 4, 0.1],
	"biomes/gutterworks.tres": [&"cooked_anglerfish", 2, 4, 0.1],
	"biomes/ossuary.tres": [&"cooked_anglerfish", 2, 4, 0.1],
	"biomes/drowned_cistern.tres": [&"cooked_anglerfish", 2, 4, 0.1],
	"biomes/desert.tres": [&"cooked_halibut", 1, 2, 0.1],
	"biomes/sunken_tombs.tres": [&"cooked_halibut", 1, 2, 0.1],
	"biomes/sunspire_terraces.tres": [&"cooked_halibut", 1, 2, 0.1],
	"biomes/fire_forge.tres": [&"cooked_stingray", 1, 2, 0.1],
	"biomes/bellows_gallery.tres": [&"cooked_stingray", 1, 2, 0.1],
	"biomes/cinder_deeps.tres": [&"cooked_stingray", 1, 2, 0.1],
}

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_check_chests()
	_check_zones()
	if _failures.is_empty():
		print("VERIFY_PASS")
		get_tree().quit(0)
		return
	for line: String in _failures:
		printerr("FAIL: %s" % line)
	print("VERIFY_FAIL (%d)" % _failures.size())
	get_tree().quit(1)


func _fail(line: String) -> void:
	_failures.append(line)


## Every drop on a table must resolve to a registered item — RewardService and
## ChestResource both drop an entry whose id is 0 without a word.
func _check_ids(where: String, table: Array) -> void:
	for drop: LootDrop in table:
		if drop == null or drop.item == null:
			_fail("%s: a LootDrop has no item" % where)
			continue
		if int(drop.item.get_meta(&"id", 0)) <= 0:
			_fail("%s: '%s' has no metadata/id — it would be skipped at runtime"
				% [where, drop.item.item_name])


func _check_chests() -> void:
	var dir: DirAccess = DirAccess.open(CHESTS)
	if dir == null:
		_fail("cannot open %s" % CHESTS)
		return
	var seen: int = 0
	for name: String in dir.get_files():
		if not name.ends_with(".tres"):
			continue
		var chest: ChestResource = load(CHESTS + name) as ChestResource
		if chest == null:
			_fail("%s will not load as a ChestResource" % name)
			continue
		if chest.tier != 3:
			continue # tier 1/2 wood chests keep their raw fish
		seen += 1
		_check_ids(name, chest.loot)
		_check_ids(name, chest.exclusive_loot)
		var vial: LootDrop = null
		for drop: LootDrop in chest.loot:
			if drop == null or drop.item == null:
				continue
			var path: String = str(drop.item.resource_path)
			for marker: String in FISH_MARKERS:
				if path.contains(marker):
					_fail("%s still pays fish: %s" % [name, drop.item.item_name])
			if drop.item.get_meta(&"slug", &"") == VIAL_SLUG:
				vial = drop
		if vial == null:
			_fail("%s has no Vial of Water entry" % name)
		elif vial.min_amount != 5 or vial.max_amount != 15:
			_fail("%s vials are %d-%d, expected 5-15" % [name, vial.min_amount, vial.max_amount])
	if seen != 12:
		_fail("expected 12 tier-3 chests, found %d" % seen)
	print("chests: %d tier-3 tables checked" % seen)


func _check_zones() -> void:
	for rel: String in ZONES:
		var want: Array = ZONES[rel]
		var res: InstanceResource = load(INSTANCES + rel) as InstanceResource
		if res == null:
			_fail("%s will not load as an InstanceResource" % rel)
			continue
		_check_ids(rel, res.zone_kill_loot)
		var found: LootDrop = null
		for drop: LootDrop in res.zone_kill_loot:
			if drop != null and drop.item != null \
					and drop.item.get_meta(&"slug", &"") == want[0]:
				found = drop
		if found == null:
			_fail("%s (%s) does not drop %s" % [rel, res.zone_title, want[0]])
			continue
		if found.min_amount != int(want[1]) or found.max_amount != int(want[2]):
			_fail("%s: %s is %d-%d, expected %d-%d"
				% [rel, want[0], found.min_amount, found.max_amount, want[1], want[2]])
		if not is_equal_approx(found.chance, float(want[3])):
			_fail("%s: %s chance is %f, expected %f" % [rel, want[0], found.chance, want[3]])
		print("%-34s %s %d-%d @ %.2f" % [res.zone_title, want[0], found.min_amount,
			found.max_amount, found.chance])
