@tool
extends Node
## Regression gate for the teleport/respawn crash.
##
## The client REUSES one local player node across maps. It used to be left
## PARENTLESS for the whole map load, and a node outside the tree has a null
## get_tree() AND a null multiplayer — while network pushes and UI signals keep
## calling into it (death/respawn, channel start/end, equip cast, the chat typing
## gate). Every one of those dereferenced the null and killed the client.
##
## Asserts the orphaned state really is unsafe (so the reason for parking cannot
## be forgotten), and that InstanceManagerClient._park_local_player leaves the
## player in a state where those same calls resolve.
##
## Run: godot --headless --path . tools/verify_local_player_park.tscn

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_check_orphan_is_unsafe()
	_check_park_is_safe()
	_finish()


## The bug, reproduced: this is what remove_child with no new parent left behind.
func _check_orphan_is_unsafe() -> void:
	var orphan: Node2D = Node2D.new()
	add_child(orphan)
	_check(orphan.get_tree() != null, "control: an in-tree node has a tree")
	_check(orphan.multiplayer != null, "control: an in-tree node has a multiplayer")
	remove_child(orphan)
	# If either of these ever starts passing, the crash class is gone and this
	# whole gate can go with it.
	_check(orphan.get_tree() == null, "orphaned node has NO tree (get_tree() would crash)")
	_check(orphan.multiplayer == null, "orphaned node has NO multiplayer (is_server() would crash)")
	orphan.free()


## The fix: parked on the manager, the same calls resolve.
func _check_park_is_safe() -> void:
	var manager: InstanceManagerClient = InstanceManagerClient.new()
	add_child(manager)
	var map: Node2D = Node2D.new()
	manager.add_child(map)
	var player: Node2D = Node2D.new()
	map.add_child(player)

	manager._park_local_player(player)

	_check(player.get_parent() == manager, "parked player hangs off the manager")
	_check(player.is_inside_tree(), "parked player is still in the tree")
	_check(player.get_tree() != null, "parked player has a live tree")
	_check(player.multiplayer != null, "parked player has a live multiplayer")
	_check(
		player.process_mode == Node.PROCESS_MODE_DISABLED,
		"parked player stops processing (nothing ticks against the freed map)"
	)
	_check(not player.visible, "parked player is hidden over the empty world")

	# What spawn_player does on arrival: reparent into the new map and undo the park.
	var next_map: Node2D = Node2D.new()
	manager.add_child(next_map)
	player.get_parent().remove_child(player)
	next_map.add_child(player)
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.show()
	_check(player.get_parent() == next_map, "arriving player lands in the new map")
	_check(player.process_mode == Node.PROCESS_MODE_INHERIT, "arriving player processes again")
	_check(player.visible, "arriving player is visible again")

	manager.free()


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
