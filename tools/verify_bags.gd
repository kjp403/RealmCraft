extends Node
## Regression gate for multi-bag inventory routing (backpack tabs).
##
## Unregistered item ids resolve to null, which Inventory treats as
## non-stackable AND as counting toward capacity — so slot routing can be probed
## without depending on the content registry.
##
## The bug this exists to catch: add_item passed capacity 1 to
## _next_bag_with_space, so "has space" meant "is entirely empty" and 28 items
## landed as bag0=26 / bag1=1 / bag2=1 instead of filling the active bag.

const ID: int = 99901
const ID_B: int = 99902

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	_check_single_bag_players_unaffected()
	_check_active_bag_fills_first()
	_check_overflow_order()
	_check_capacity_accounting()
	_check_total_free_slots()
	_check_degenerate_inputs()

	print("\nPASS %d  FAIL %d" % [_pass, _fail])
	print("VERIFY_PASS" if _fail == 0 else "VERIFY_FAIL")
	get_tree().quit(0 if _fail == 0 else 1)


## The overwhelming majority of players own exactly one bag. Nothing may change
## for them.
func _check_single_bag_players_unaffected() -> void:
	var inv: Dictionary = {}
	for i: int in Inventory.MAX_SLOTS:
		Inventory.add_item(inv, ID, 1, false, 0, 1)
	var per: Array[int] = _per_bag(inv)
	_ck(per[0] == Inventory.MAX_SLOTS, "1 bag: all %d items in bag 0 (got %d)" % [
		Inventory.MAX_SLOTS, per[0]
	])
	_ck(per[1] == 0 and per[2] == 0, "1 bag: nothing leaks into locked bags")


func _check_active_bag_fills_first() -> void:
	var inv: Dictionary = {}
	for i: int in 5:
		Inventory.add_item(inv, ID, 1, false, 0, 3)
	var per: Array[int] = _per_bag(inv)
	_ck(per[0] == 5, "3 bags, active 0: 5 items all in bag 0 (got %d/%d/%d)" % per)

	var inv2: Dictionary = {}
	for i: int in 5:
		Inventory.add_item(inv2, ID, 1, false, 1, 3)
	var per2: Array[int] = _per_bag(inv2)
	_ck(per2[1] == 5, "3 bags, active 1: 5 items all in bag 1 (got %d/%d/%d)" % per2)

	var inv3: Dictionary = {}
	for i: int in Inventory.MAX_SLOTS:
		Inventory.add_item(inv3, ID, 1, false, 0, 3)
	var per3: Array[int] = _per_bag(inv3)
	_ck(
		per3[0] == Inventory.MAX_SLOTS and per3[1] == 0 and per3[2] == 0,
		"3 bags: bag 0 fills to %d before spilling (got %d/%d/%d)" % [
			Inventory.MAX_SLOTS, per3[0], per3[1], per3[2]
		]
	)


## Past the active bag's capacity, new slots wrap to the next unlocked bag.
func _check_overflow_order() -> void:
	var inv: Dictionary = {}
	for i: int in Inventory.MAX_SLOTS + 3:
		Inventory.add_item(inv, ID, 1, false, 0, 3)
	var per: Array[int] = _per_bag(inv)
	_ck(per[0] == Inventory.MAX_SLOTS, "overflow: bag 0 stays full (got %d)" % per[0])
	_ck(per[1] == 3, "overflow: next 3 land in bag 1 (got %d)" % per[1])
	_ck(per[2] == 0, "overflow: bag 2 untouched (got %d)" % per[2])

	# Starting from the middle bag must wrap 1 -> 2 -> 0, never into a locked bag.
	var inv2: Dictionary = {}
	for i: int in Inventory.MAX_SLOTS * 2 + 1:
		Inventory.add_item(inv2, ID_B, 1, false, 1, 2)
	var per2: Array[int] = _per_bag(inv2)
	_ck(per2[2] == 0, "wrap with 2 bags unlocked never uses bag 2 (got %d)" % per2[2])
	_ck(
		per2[0] + per2[1] == Inventory.MAX_SLOTS * 2 + 1,
		"wrap keeps every item (got %d/%d/%d)" % per2
	)


func _check_capacity_accounting() -> void:
	var inv: Dictionary = {}
	for i: int in Inventory.MAX_SLOTS:
		inv[i + 1] = {"id": ID, "a": 1, "bag": 0}
	_ck(
		Inventory.can_add(inv, ID, 1, Inventory.MAX_SLOTS, false, 0, 3),
		"bag 0 full but 3 bags unlocked -> can_add true"
	)
	_ck(
		not Inventory.can_add(inv, ID, 1, Inventory.MAX_SLOTS, false, 0, 1),
		"bag 0 full and only 1 bag -> can_add false"
	)
	_ck(
		Inventory.max_fit(inv, ID, Inventory.MAX_SLOTS, false, 0, 1) == 0,
		"max_fit 0 for a full single bag"
	)
	_ck(
		Inventory.max_fit(inv, ID, Inventory.MAX_SLOTS, false, 0, 3) > 0,
		"max_fit positive when other bags are open"
	)


func _check_total_free_slots() -> void:
	var inv: Dictionary = {}
	for i: int in Inventory.MAX_SLOTS:
		inv[i + 1] = {"id": ID, "a": 1, "bag": 0}
	_ck(
		Inventory.total_free_slots(inv, 3) == Inventory.MAX_SLOTS * 2,
		"total_free_slots reports %d for 3 bags with bag 0 full (got %d)" % [
			Inventory.MAX_SLOTS * 2, Inventory.total_free_slots(inv, 3)
		]
	)
	_ck(
		Inventory.total_free_slots(inv, 1) == 0,
		"total_free_slots 0 for 1 bag with bag 0 full"
	)


## Legacy slots carry no "bag" key, and inventory_bags should never be 0 — but
## neither may crash or silently route items into a bag no tab can show.
func _check_degenerate_inputs() -> void:
	var legacy: Dictionary = Inventory.normalize({"1": {"id": ID, "a": 1}})
	var first_key: Variant = legacy.keys()[0]
	_ck(int(legacy[first_key].get("bag", -1)) == 0, "normalize() defaults legacy slots to bag 0")

	var inv: Dictionary = {}
	Inventory.add_item(inv, ID, 1, false, 0, 0)
	_ck(inv.size() == 1, "bag_count 0 does not crash")
	for uid in inv:
		_ck(int(inv[uid].get("bag", -1)) == 0, "bag_count 0 still lands in bag 0")

	var inv2: Dictionary = {}
	Inventory.add_item(inv2, ID, 5, false, 0, 3)
	for uid in inv2:
		var b: int = int(inv2[uid].get("bag", -1))
		_ck(b >= 0 and b < Inventory.MAX_BAGS, "every slot has an in-range bag (%d)" % b)
		break


func _per_bag(inv: Dictionary) -> Array[int]:
	var per: Array[int] = [0, 0, 0]
	for uid in inv:
		var b: int = int(inv[uid].get("bag", 0))
		if b >= 0 and b < 3:
			per[b] += 1
	return per


func _ck(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  ok    %s" % label)
	else:
		_fail += 1
		printerr("  FAIL  %s" % label)
