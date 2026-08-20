extends Node
## Regression gate for the bank deposit item-loss bug: Inventory.add_item used
## the 28-slot BAG cap when opening new vault slots, so a bank already holding
## 28+ stacks silently swallowed whatever did not fit.
##   godot --path . --mode=client res://tools/check_bank_deposit.tscn

const HERB: StringName = &"blightspore"
const FILLER: StringName = &"iron_ore"


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var herb_id: int = ContentRegistryHub.id_from_slug(&"items", HERB)
	var filler_id: int = ContentRegistryHub.id_from_slug(&"items", FILLER)
	var failed: bool = false

	# A well-used vault: 40 distinct piles, more than the 28-slot bag cap.
	var bank: Dictionary = {}
	for i: int in 40:
		bank[Inventory.next_uid(bank)] = {"id": filler_id, "a": 5, "bag": 0}

	var before: int = Inventory.count(bank, herb_id)
	Inventory.add_item(bank, herb_id, 100, true)
	var after: int = Inventory.count(bank, herb_id)
	print("deposit into 40-stack bank: before=%d after=%d (want 100)" % [before, after])
	if after - before != 100:
		push_error("LOST %d items depositing into a full-ish bank" % (100 - (after - before)))
		failed = true

	# And the bag path still respects its own cap rather than overflowing.
	var bag: Dictionary = {}
	Inventory.add_item(bag, herb_id, 30, false, 0, 1)
	var bag_total: int = Inventory.count(bag, herb_id)
	print("bag add 30 with one bag: total=%d slots=%d" % [bag_total, bag.size()])
	if bag.size() > Inventory.MAX_SLOTS:
		push_error("bag exceeded MAX_SLOTS")
		failed = true

	print("RESULT ", "FAIL" if failed else "PASS")
	get_tree().quit(1 if failed else 0)
