extends Node
## Static checks for the bank rework. Runs as a SCENE, for the same reason
## render_bank_previews does: under `-s` there are no autoloads, so every script
## that reaches Client / ClientState fails to compile and the check reports
## cascading false failures instead of the truth.
##
##   godot --path . --mode=client res://tools/verify_bank.tscn
##
## Scope: compilation of the touched scripts, and the Inventory maths the new
## multi-pile deposit leans on. It does NOT drive bank.deposit end to end — that
## needs a live ServerInstance and a real Player, so the deposit path still wants
## a smoke test on a running world server.

const SCRIPTS: Array[String] = [
	"res://source/client/ui/bank_order.gd",
	"res://source/client/ui/menus/bank/bank_menu.gd",
	"res://source/server/world/components/data_request_handlers/bank.deposit.gd",
	"res://source/server/world/components/data_request_handlers/bank.withdraw.gd",
	"res://source/server/world/components/data_request_handlers/bank.deposit_all.gd",
	"res://source/server/world/components/data_request_handlers/bank.get.gd",
	"res://source/server/world/components/data_request_handlers/bank.upgrade.gd",
]

var _pass: int = 0
var _fail: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	print("-- compile --")
	for path: String in SCRIPTS:
		var script: Script = load(path) as Script
		_check(script != null and script.can_instantiate(), "compiles: %s" % path.get_file())

	print("-- sort modes --")
	for mode: int in BankOrder.Sort.values():
		_check(BankOrder.SORT_LABELS.has(mode), "sort %d has a label" % mode)
		_check(BankOrder.SORT_HINTS.has(mode), "sort %d has a hint" % mode)
	_check(
		BankOrder.load_sort() is int and BankOrder.SORT_LABELS.has(int(BankOrder.load_sort())),
		"load_sort clamps to a known mode"
	)

	print("-- tab coverage --")
	# Every Item.InventoryTab must have a rail entry, or items silently vanish
	# from every tab except All.
	var menu_script: GDScript = load("res://source/client/ui/menus/bank/bank_menu.gd") as GDScript
	var tabs: Array = menu_script.get_script_constant_map().get("TABS", [])
	var covered: Dictionary = {}
	for entry: Array in tabs:
		covered[int(entry[0])] = true
	for tab: int in Item.InventoryTab.values():
		_check(covered.has(tab), "InventoryTab %d has a rail tab" % tab)

	print("-- multi-pile deposit maths --")
	var iron: int = ContentRegistryHub.id_from_slug(&"items", &"iron_ore")
	_check(iron > 0, "iron_ore resolves")
	if iron > 0:
		# A split bag stack is the case the old handler got wrong: it capped the
		# deposit at the ONE clicked pile, so "All" on 3+7 banked 7, not 10.
		var bag: Dictionary = {1: {"id": iron, "a": 3}, 2: {"id": iron, "a": 7}}
		_check(Inventory.count(bag, iron) == 10, "count spans every bag pile (3+7 = 10)")

		# Vault space is what actually caps a deposit, and bank stacks are bulk.
		var vault: Dictionary = {}
		var fit: int = Inventory.max_fit(vault, iron, 200, true)
		_check(fit >= 200 * Inventory.BANK_RESOURCE_STACK, "empty vault fits a full bulk load")

		# A vault at capacity still accepts a top-up into an existing pile.
		var full_vault: Dictionary = {}
		for i: int in 50:
			full_vault[i + 1] = {"id": iron, "a": Inventory.BANK_RESOURCE_STACK - 1}
		_check(
			Inventory.max_fit(full_vault, iron, 50, true) == 50,
			"a full vault still tops up existing piles"
		)

		# ...but not a NEW stack of something it has no room for.
		var other: int = ContentRegistryHub.id_from_slug(&"items", &"coal_ore")
		_check(
			other > 0 and Inventory.max_fit(full_vault, other, 50, true) == 0,
			"a full vault refuses to open a new stack"
		)

	print("-- partial stack merge --")
	if iron > 0:
		var split: Dictionary = {1: {"id": iron, "a": 9}, 2: {"id": iron, "a": 1}}
		_check(Inventory.merge_slots(split, 2, 1, false) == 1, "9+1 iron merges the 1")
		_check(int(split[1].get("a", 0)) == 10, "destination becomes a full stack of 10")
		_check(not split.has(2), "empty source pile is erased")

		var overflow: Dictionary = {1: {"id": iron, "a": 10}, 2: {"id": iron, "a": 5}}
		_check(Inventory.merge_slots(overflow, 2, 1, false) == 0, "full dest refuses a merge")
		_check(int(overflow[1].get("a", 0)) == 10, "full dest stays 10")
		_check(int(overflow[2].get("a", 0)) == 5, "source stays 5 when dest is full")

		var partial: Dictionary = {1: {"id": iron, "a": 8}, 2: {"id": iron, "a": 5}}
		_check(Inventory.merge_slots(partial, 2, 1, false) == 2, "8+5 moves 2 into the dest")
		_check(int(partial[1].get("a", 0)) == 10, "dest fills to 10")
		_check(int(partial[2].get("a", 0)) == 3, "source keeps the leftover 3")

	print("-- withdraw cap --")
	if iron > 0:
		# Withdraw All is capped by BAG fit, not by the vault total — the reason
		# "All" on 594 coal shows 170 rather than 594.
		var bag2: Dictionary = {}
		for i: int in 11:
			bag2[i + 1] = {"id": iron, "a": 10}
		var free: int = Inventory.MAX_SLOTS - 11
		_check(
			Inventory.max_fit(bag2, iron, Inventory.MAX_SLOTS) == free * 10,
			"withdraw fit = free bag slots x bag stack limit"
		)

	print("")
	print("PASS %d  FAIL %d" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		_pass += 1
		print("  ok    ", label)
	else:
		_fail += 1
		print("  FAIL  ", label)
