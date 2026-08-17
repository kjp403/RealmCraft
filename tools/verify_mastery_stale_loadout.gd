@tool
extends Node
## Regression gate for the trimmed-top-rank fallout (commit 733270e4 dropped the
## tier-4 nodes from bow/book/wand). Players who had already learned and slotted
## one still carry the dead id in ability_loadout, which made archery specials
## silently channel nothing AND made every later equip bounce off the
## mastery.loadout handler with "unknown_node".
##
## Asserts the data facts the fix rests on, and that a stale pick resolves to an
## empty slot (0) instead of taking a real one down with it.
##
## Run: godot --headless --path . tools/verify_mastery_stale_loadout.tscn

const BOW_ITEM: String = "res://source/common/gameplay/items/weapons/bow/wooden_bow.item.tres"
## Top ranks the trim removed — the ids still sitting in live save data.
const STALE: Array[String] = ["bow_rain_of_arrows", "bow_pinning_arrow"]
## The highest ranks that DID survive, and must still channel.
const LIVE: Array[String] = ["bow_rain_of_arrows_3", "bow_pinning_arrow_3"]

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var tree: MasteryTreeResource = MasteryService.tree_for(&"bow")
	_check(tree != null, "bow tree loads")
	if tree == null:
		_finish()
		return

	for id: String in STALE:
		_check(
			tree.get_node_by_id(StringName(id)) == null,
			"%s is gone from the tree (trimmed top rank)" % id
		)
	for id: String in LIVE:
		var node: MasteryNode = tree.get_node_by_id(StringName(id))
		_check(node != null and node.ability != null, "%s still exists and has an ability" % id)

	# No chain may point at a node the trim removed, or its top rank is unlearnable.
	for node: MasteryNode in tree.nodes:
		if node.upgrades.is_empty():
			continue
		_check(
			tree.get_node_by_id(node.upgrades) != null,
			"%s upgrades from a node that still exists" % node.id
		)

	_check_resolution(tree)
	_finish()


## A loadout of [stale, live] must resolve to [0, <real id>]: the dead pick
## empties its own slot and leaves the good one alone.
func _check_resolution(tree: MasteryTreeResource) -> void:
	var weapon: WeaponItem = load(BOW_ITEM) as WeaponItem
	_check(weapon != null and weapon.category == &"bow", "wooden bow item is a bow-category weapon")
	if weapon == null:
		return

	var resource: PlayerResource = PlayerResource.new()
	var spent: Dictionary = {}
	for id: String in STALE:
		spent[id] = true # they DID buy it back when it existed
	for id: String in LIVE:
		spent[id] = true
	resource.masteries[&"bow"] = {"level": 99, "spent": spent}
	resource.ability_loadout["bow"] = [STALE[0], LIVE[1]]

	var ids: Array[int] = MasteryService.effective_special_ids(resource, weapon)
	_check(ids.size() == 2, "both slots resolve (got %d)" % ids.size())
	if ids.size() != 2:
		return
	_check(ids[0] == 0, "the removed pick resolves to an empty slot (got %d)" % ids[0])
	var expected: int = int(tree.get_node_by_id(StringName(LIVE[1])).ability.get_meta(&"id", 0))
	_check(
		expected > 0 and ids[1] == expected,
		"the surviving pick still channels (want %d, got %d)" % [expected, ids[1]]
	)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_PASS")
	else:
		for f: String in _failures:
			printerr("FAIL: %s" % f)
		printerr("VERIFY_FAIL (%d)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
