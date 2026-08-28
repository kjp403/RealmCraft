@tool
extends Node
## Gate for the level-99 mastery payoff: a maxed tree grants EVERY ability at
## the top tier of its chain, free of the point budget, and every loadout slot
## (Q / E / R / C) resolves.
##
## The three things that can silently break it: ownership still reading the
## stored spend (a maxed player couldn't equip what they never bought), the
## resolver firing a stale lower rank instead of the chain top, and the third
## slot being dropped because something still assumes two.
##
## Run: godot --headless --path . tools/verify_mastery_full_unlock.tscn

const BOW_ITEM: String = "res://source/common/gameplay/items/weapons/bow/wooden_bow.item.tres"
## A chain whose lower rank must auto-bump to its top at the cap.
const CHAIN_LOW: String = "bow_multishot"
const CHAIN_TOP: String = "bow_multishot_3"

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	var tree: MasteryTreeResource = MasteryService.tree_for(&"bow")
	_check(tree != null, "bow tree loads")
	if tree == null:
		_finish()
		return

	_check_unlock_flag()
	_check_top_of_chain(tree)
	_check_resolution(tree)
	_finish()


func _check_unlock_flag() -> void:
	_check(
		not MasteryService.has_full_unlock({"level": PlayerResource.MASTERY_LEVEL_CAP - 1}),
		"one level short of the cap is NOT a full unlock"
	)
	_check(
		MasteryService.has_full_unlock({"level": PlayerResource.MASTERY_LEVEL_CAP}),
		"the cap IS a full unlock"
	)


func _check_top_of_chain(tree: MasteryTreeResource) -> void:
	var low: MasteryNode = tree.get_node_by_id(StringName(CHAIN_LOW))
	var top: MasteryNode = tree.get_node_by_id(StringName(CHAIN_TOP))
	_check(low != null and top != null, "the multishot chain still exists end to end")
	if low == null or top == null:
		return
	_check(
		MasteryService.top_of_chain(tree, low).id == top.id,
		"a chain's lowest rank resolves up to its top (got %s)" % MasteryService.top_of_chain(tree, low).id
	)
	# Ownership at the cap ignores the spend ledger ENTIRELY — abilities and
	# passives alike. A partial unlock is the bug this asserts against: the tree
	# said MASTERED while greyed-out passive tiles stared back at the player.
	var maxed: Dictionary = {"level": PlayerResource.MASTERY_LEVEL_CAP, "spent": {}}
	_check(MasteryService.owns_node(maxed, top), "a maxed tree owns an ability it never bought")
	var passives: int = 0
	for node: MasteryNode in tree.nodes:
		if node.ability != null:
			continue
		passives += 1
		_check(
			MasteryService.owns_node(maxed, node),
			"a maxed tree owns passive %s it never bought" % node.id
		)
	_check(passives > 0, "the bow tree has passives for the cap to grant")
	# Below the cap, nothing is free.
	var below: Dictionary = {"level": PlayerResource.MASTERY_LEVEL_CAP - 1, "spent": {}}
	_check(
		not MasteryService.owns_node(below, top),
		"one level short of the cap owns nothing it did not buy"
	)


## Three picks, one of them a stale lower rank: all three slots come back, and
## the lower rank channels its chain's TOP tier.
func _check_resolution(tree: MasteryTreeResource) -> void:
	var weapon: WeaponItem = load(BOW_ITEM) as WeaponItem
	_check(weapon != null and weapon.category == &"bow", "wooden bow item is a bow-category weapon")
	if weapon == null:
		return

	var abilities: Array[MasteryNode] = []
	var seen_chains: Dictionary = {}
	for node: MasteryNode in tree.nodes:
		if node.ability == null:
			continue
		var root: String = String(MasteryService.chain_root_of(tree, node))
		if seen_chains.has(root) or root == CHAIN_LOW:
			continue
		seen_chains[root] = true
		abilities.append(MasteryService.top_of_chain(tree, node))
	_check(abilities.size() >= 2, "the bow tree has enough distinct ability chains to fill 3 slots")
	if abilities.size() < 2:
		return

	# NOTHING bought — the cap alone must carry the whole loadout.
	var resource: PlayerResource = PlayerResource.new()
	resource.masteries[&"bow"] = {"level": PlayerResource.MASTERY_LEVEL_CAP, "spent": {}}
	resource.ability_loadout["bow"] = [
		CHAIN_LOW, String(abilities[0].id), String(abilities[1].id),
	]

	var ids: Array[int] = MasteryService.effective_special_ids(resource, weapon)
	_check(ids.size() == 3, "all three slots resolve (got %d)" % ids.size())
	if ids.size() != 3:
		return
	var want_top: int = int(tree.get_node_by_id(StringName(CHAIN_TOP)).ability.get_meta(&"id", 0))
	_check(
		want_top > 0 and ids[0] == want_top,
		"a stale lower rank channels the chain TOP at the cap (want %d, got %d)" % [want_top, ids[0]]
	)
	for i: int in 2:
		var want: int = int(abilities[i].ability.get_meta(&"id", 0))
		_check(
			want > 0 and ids[i + 1] == want,
			"slot %d channels its unbought pick (want %d, got %d)" % [i + 2, want, ids[i + 1]]
		)

	# Below the cap the same unbought loadout must channel NOTHING — the unlock
	# is the reward for 99, not a hole in the ownership check.
	resource.masteries[&"bow"] = {"level": PlayerResource.MASTERY_LEVEL_CAP - 1, "spent": {}}
	var below: Array[int] = MasteryService.effective_special_ids(resource, weapon)
	var any_mounted: bool = false
	for id: int in below:
		if id > 0:
			any_mounted = true
	_check(not any_mounted, "one level short of the cap, an unbought loadout channels nothing")


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL: %d" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
