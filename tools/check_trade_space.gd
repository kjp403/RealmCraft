extends Node
## Regression gate for the trade item-loss bug: the swap called Inventory.add_item,
## which has no capacity check, so a 15-slot offer into a bag with 10 free squares
## completed and the overflow went nowhere. [InventorySpace] is what the trade paths
## now ask BEFORE moving anything.
##
## Also covers the delivery ladder (bank -> bag -> ground) used by "send to bank",
## as far as it can go without a live map: bank full must fall through to the bag
## rather than stop.
##
## And BULK (case 7): a bag square's stack limit must never cap a trade offer, but
## the receiver's free SQUARES still must — those are different limits, and only
## the second one may refuse a swap.
##   godot --path . --mode=client res://tools/check_trade_space.tscn

const FILLER: StringName = &"iron_ore"
## Distinct non-stackables, so each one costs its own square.
const GEAR: Array[StringName] = [
	&"iron_helmet", &"iron_chest", &"iron_boots",
	&"steel_helmet", &"steel_chest", &"steel_boots",
]

var _failed: bool = false


func _ready() -> void:
	call_deferred(&"_go")


func _id(slug: StringName) -> int:
	return ContentRegistryHub.id_from_slug(&"items", slug)


## A one-bag inventory holding [param used] distinct-ish squares of filler.
func _bag_with(used: int) -> Dictionary:
	var bag: Dictionary = {}
	var filler_id: int = _id(FILLER)
	for _i: int in used:
		bag[Inventory.next_uid(bag)] = {"id": filler_id, "a": 999, "bag": 0}
	return bag


func _expect(label: String, got: bool, want: bool) -> void:
	if got != want:
		_failed = true
	print("%s: got %s, want %s — %s" % [label, got, want, "OK" if got == want else "FAIL"])


func _expect_int(label: String, got: int, want: int) -> void:
	if got != want:
		_failed = true
	print("%s: got %d, want %d — %s" % [label, got, want, "OK" if got == want else "FAIL"])


func _go() -> void:
	var gear_ids: Array[int] = []
	for slug: StringName in GEAR:
		var id: int = _id(slug)
		if id > 0:
			gear_ids.append(id)
	if gear_ids.size() < 3:
		print("RESULT FAIL — could not resolve the gear items this gate needs")
		get_tree().quit(1)
		return

	# 1. The reported case: more incoming squares than free ones, nothing offered
	# back, must be refused.
	var tight: Dictionary = _bag_with(Inventory.MAX_SLOTS - 2)
	var incoming: Dictionary = {}
	for i: int in 3:
		incoming[gear_ids[i]] = 1
	_expect("3 items into 2 free squares", InventorySpace.can_receive_all(tight, incoming), false)
	_expect_int(
		"...and it says how many squares short",
		InventorySpace.missing_slots_for(tight, incoming),
		1
	)

	# 2. Exactly filling the bag is fine — the guard must not be off by one.
	var incoming_two: Dictionary = {gear_ids[0]: 1, gear_ids[1]: 1}
	_expect("2 items into 2 free squares", InventorySpace.can_receive_all(tight, incoming_two), true)

	# 3. A swap frees what it gives: a full bag trading 3 squares away for 3 fits.
	var full: Dictionary = _bag_with(Inventory.MAX_SLOTS)
	var outgoing: Dictionary = {_id(FILLER): 3 * 999}
	_expect(
		"full bag, 3 squares out for 3 in",
		InventorySpace.can_receive_all(full, incoming, outgoing),
		true
	)
	_expect(
		"full bag, nothing out",
		InventorySpace.can_receive_all(full, incoming),
		false
	)

	# 4. Several unlocked bags are counted, not just the active one.
	var three_bags: Dictionary = _bag_with(Inventory.MAX_SLOTS)
	_expect(
		"full first bag, 3 bags unlocked",
		InventorySpace.can_receive_all(three_bags, incoming, {}, 0, 3),
		true
	)

	# 5. Currency never needs a square.
	var gold_id: int = Economy.gold_id()
	if gold_id > 0:
		_expect(
			"10k gold into a full bag",
			InventorySpace.can_receive_all(_bag_with(Inventory.MAX_SLOTS), {gold_id: 10000}),
			true
		)

	# 6. Delivery ladder: a full vault must hand off to the bag, not stop dead.
	# (The ground rung needs a live map, so it is exercised in-game, not here.)
	var bank: Dictionary = {}
	var filler_id: int = _id(FILLER)
	for _i: int in BankInteraction.STARTING_SLOTS:
		bank[Inventory.next_uid(bank)] = {"id": filler_id, "a": 1, "bag": 0}
	var gem_id: int = gear_ids[0]
	_expect_int(
		"full vault takes none of the incoming item",
		Inventory.max_fit(bank, gem_id, BankInteraction.STARTING_SLOTS, true),
		0
	)
	var bag: Dictionary = {}
	_expect_int(
		"...so the bag rung takes it",
		mini(1, Inventory.max_fit(bag, gem_id, Inventory.MAX_SLOTS, false, 0, 1)),
		1
	)

	# 7. Bulk. A bag stack limit caps a SQUARE, never a trade offer: 900 cooked
	# shrimp living in ninety ten-count squares is one offer of 900. This is the
	# item-loss case this gate exists for, because the transfer stopped adding
	# received goods one unit at a time — it now hands add_item the whole 900.
	_check_bulk_offer()

	print("RESULT ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)


## A 900-unit offer, end to end through the real transfer.
##
## The receiver's PlayerResource is what decides the active bag and how many bags
## are unlocked — pass it, or _transfer_offer falls back to ONE bag (30 squares =
## 300 shrimp) and silently drops the rest.
func _check_bulk_offer() -> void:
	var shrimp: int = _id(&"cooked_shrimp")
	if shrimp <= 0:
		_failed = true
		print("bulk offer: could not resolve cooked_shrimp — FAIL")
		return
	var item: Item = ContentRegistryHub.load_by_id(&"items", shrimp) as Item
	_expect_int("a bag square holds only 10 shrimp", Inventory.stack_limit_for(item, false), 10)

	# Giver: a full three-bag inventory of shrimp, ninety squares of ten.
	var giver: Dictionary = {}
	for i: int in Inventory.MAX_SLOTS * Inventory.MAX_BAGS:
		giver[Inventory.next_uid(giver)] = {"id": shrimp, "a": 10, "bag": i % Inventory.MAX_BAGS}
	_expect_int("...but the giver holds 900 of them", Inventory.count(giver, shrimp), 900)

	# What TradeService.set_offer validates: the TOTAL held, not one square.
	var offer: Dictionary = {"items": {shrimp: 900}, "gold": 0}
	_expect("an offer of 900 passes set_offer's own check", Inventory.count(giver, shrimp) >= 900, true)

	var receiver: Dictionary = {}
	_expect(
		"an empty three-bag receiver can take all 900",
		InventorySpace.can_receive_all(receiver, offer["items"], {}, 0, Inventory.MAX_BAGS),
		true
	)
	# Room is a real limit and must stay one — it is not the same as a stack cap.
	_expect(
		"a one-bag receiver is refused (300 max) — room, not stack size",
		InventorySpace.can_receive_all(receiver, offer["items"], {}, 0, 1),
		false
	)

	var to_pr: PlayerResource = PlayerResource.new()
	to_pr.inventory_bags = Inventory.MAX_BAGS
	to_pr.active_inventory_bag = 0
	TradeService._transfer_offer(giver, receiver, to_pr, offer)
	_expect_int("the giver's 900 left the bag", Inventory.count(giver, shrimp), 0)
	_expect_int("the receiver got all 900 — nothing dropped", Inventory.count(receiver, shrimp), 900)
	_expect_int("and it repacked into 90 squares", receiver.size(), 90)
	var over_cap: bool = false
	for uid: Variant in receiver:
		if int(receiver[uid].get("a", 0)) > 10:
			over_cap = true
	_expect("no received square exceeds the bag stack limit", over_cap, false)

	# An item that authors no stack_limit rides in a single square either way.
	var heads: int = _id(&"bronze_arrowheads")
	if heads > 0:
		var a_giver: Dictionary = {}
		a_giver[Inventory.next_uid(a_giver)] = {"id": heads, "a": 5000, "bag": 0}
		var a_receiver: Dictionary = {}
		TradeService._transfer_offer(
			a_giver, a_receiver, to_pr, {"items": {heads: 5000}, "gold": 0}
		)
		_expect_int("5000 arrowheads move whole", Inventory.count(a_receiver, heads), 5000)
		_expect_int("...in one square", a_receiver.size(), 1)
