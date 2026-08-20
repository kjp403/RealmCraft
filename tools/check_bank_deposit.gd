extends Node
## Regression gate for the bank deposit item-loss bug: Inventory.add_item opened
## new vault slots using the 28-slot BAG cap, so a bank already holding 28+
## stacks silently swallowed whatever did not fit — after the deposit had
## already removed it from the player's bag.
##
## Covers every shape that writes into the vault: single deposit, Deposit All
## across many item types, a stack split over several bag piles, non-stackables,
## and a vault at capacity (which must REFUSE, not eat).
##   godot --path . --mode=client res://tools/check_bank_deposit.tscn

const FILLER: StringName = &"iron_ore"
const HERBS: Array[StringName] = [
	&"blightspore", &"venom_sac", &"fairy_dust", &"ember_ash", &"sunwort",
	&"frostpetal", &"moonbloom", &"bloodcap", &"healing_herb", &"vial_of_water",
]
const GEAR: StringName = &"iron_helmet"
## Comfortably past MAX_SLOTS (28) — the cap that used to be applied to vaults.
const VAULT_STACKS: int = 40
const BANK_CAPACITY: int = 200

var _failed: bool = false


func _ready() -> void:
	call_deferred(&"_go")


func _id(slug: StringName) -> int:
	return ContentRegistryHub.id_from_slug(&"items", slug)


## A vault that already has more piles than a bag could hold.
func _used_vault() -> Dictionary:
	var bank: Dictionary = {}
	var filler_id: int = _id(FILLER)
	for _i: int in VAULT_STACKS:
		bank[Inventory.next_uid(bank)] = {"id": filler_id, "a": 5, "bag": 0}
	return bank


func _check(label: String, got: int, want: int) -> void:
	var ok: bool = got == want
	if not ok:
		_failed = true
	print("%s: got %d, want %d — %s" % [label, got, want, "OK" if ok else "LOST %d" % (want - got)])


func _go() -> void:
	# 1. Single deposit into a well-used vault.
	var bank: Dictionary = _used_vault()
	var herb_id: int = _id(HERBS[0])
	Inventory.add_item(bank, herb_id, 100, true)
	_check("single deposit of 100", Inventory.count(bank, herb_id), 100)

	# 2. Deposit All: many different materials in one go.
	bank = _used_vault()
	var total_want: int = 0
	for slug: StringName in HERBS:
		var id: int = _id(slug)
		if id <= 0:
			continue
		Inventory.add_item(bank, id, 47, true)
		total_want += 47
	var total_got: int = 0
	for slug: StringName in HERBS:
		var id: int = _id(slug)
		if id > 0:
			total_got += Inventory.count(bank, id)
	_check("deposit all (%d materials x47)" % HERBS.size(), total_got, total_want)

	# 3. One item split across three bag piles, deposited as a whole.
	bank = _used_vault()
	var bag: Dictionary = {}
	var split_id: int = _id(HERBS[1])
	for amount: int in [3, 7, 5]:
		bag[Inventory.next_uid(bag)] = {"id": split_id, "a": amount, "bag": 0}
	var held: int = Inventory.count(bag, split_id)
	var moved: int = 0
	for uid: Variant in bag.keys():
		moved += Inventory.remove_from_slot(bag, int(uid), 99)
	Inventory.add_item(bank, split_id, moved, true)
	_check("split stack (3+7+5)", Inventory.count(bank, split_id), held)

	# 4. Non-stackable gear — one vault slot each, none dropped.
	bank = _used_vault()
	var gear_id: int = _id(GEAR)
	if gear_id > 0:
		Inventory.add_item(bank, gear_id, 4, true)
		_check("4 non-stackable helmets", Inventory.count(bank, gear_id), 4)

	# 5. A vault at capacity must REFUSE (max_fit 0), never accept-and-drop.
	bank = {}
	var filler_id: int = _id(FILLER)
	for _i: int in BANK_CAPACITY:
		bank[Inventory.next_uid(bank)] = {"id": filler_id, "a": 1, "bag": 0}
	var fit: int = Inventory.max_fit(bank, _id(HERBS[2]), BANK_CAPACITY, true)
	print("full vault max_fit: %d (want 0 so the caller refuses)" % fit)
	if fit != 0:
		_failed = true

	# 6. The bag path is untouched: still capped at MAX_SLOTS.
	var only_bag: Dictionary = {}
	Inventory.add_item(only_bag, herb_id, 30, false, 0, 1)
	print("bag add 30: total=%d slots=%d" % [Inventory.count(only_bag, herb_id), only_bag.size()])
	if only_bag.size() > Inventory.MAX_SLOTS:
		_failed = true

	print("RESULT ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
