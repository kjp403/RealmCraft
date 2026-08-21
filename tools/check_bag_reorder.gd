extends Node
## Exercise the bag drag-to-reorder path the way compact_menu_host does it:
## load the saved order, swap two uids, then re-sync against the live entries
## exactly as the next refresh will. A drop that reports success but comes back
## unchanged after the refresh is the bug players see as "dragging does
## nothing".
##   godot --path . --mode=client res://tools/check_bag_reorder.tscn

const SLOTS: int = 30

var _fails: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	# A full 30-slot bag, uids 100..129, in order.
	var live: Array[Dictionary] = []
	var order: Array = []
	for i: int in SLOTS:
		live.append({"uid": 100 + i})
		order.append(100 + i)
	BagOrder.save_order(order)

	# Drag the item in grid slot 26 onto grid slot 6 (occupied).
	var from_uid: int = 126
	var to_index: int = 6
	var work: Array = BagOrder.load_order()
	var dest_uid: int = int(work[to_index])
	BagOrder.swap(work, from_uid, dest_uid)
	_expect(int(BagOrder.load_order()[to_index]) == from_uid, "swap lands in the target slot")

	var after: Array = BagOrder.sync_with_entries(live)
	_expect(int(after[to_index]) == from_uid,
		"swap SURVIVES the refresh (got %d at slot %d)" % [int(after[to_index]), to_index])
	_expect(int(after[26]) == dest_uid, "the displaced item takes the source slot")

	# Same drag onto an EMPTY square past the end of the packed order.
	BagOrder.save_order(order.duplicate())
	work = BagOrder.load_order()
	BagOrder.move_to_index(work, 129, 3)
	var packed: Array = BagOrder.sync_with_entries(live)
	_expect(int(packed[3]) == 129, "move to an earlier square survives the refresh")

	# A uid the saved order has never seen — freshly looted, or pruned while
	# another bag was open. This used to no-op, which is the drag that "does
	# nothing".
	BagOrder.save_order(order.duplicate())
	work = BagOrder.load_order()
	work.erase(126)
	BagOrder.save_order(work)
	work = BagOrder.load_order()
	BagOrder.swap(work, 126, int(work[6]))
	_expect(BagOrder.load_order().find(126) == 6,
		"an unknown source uid still lands where it was dropped")

	print("bag reorder: %d failed" % _fails)
	print("BAG_REORDER_PASS" if _fails == 0 else "BAG_REORDER_FAIL")
	get_tree().quit(0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("  FAIL: ", what)
	else:
		print("  ok:   ", what)
