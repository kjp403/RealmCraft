extends SceneTree
## End-to-end load check for the rebuilt Goblin Woodland scene: the map must
## instantiate, every gathering node must resolve its resource, and the
## replicated-prop id maps must still point at real children.
##
##   godot --headless --path . -s tools/check_woodland_loads.gd

const MAP_PATH := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"


func _initialize() -> void:
	var packed := load(MAP_PATH) as PackedScene
	if packed == null:
		push_error("CHECK FAIL: map did not load")
		quit(1)
		return
	var map: Node2D = packed.instantiate()

	var failures: Array[String] = []

	var holder := map.get_node_or_null("MineableNodes")
	if holder == null:
		failures.append("MineableNodes container missing")
	else:
		var kinds: Dictionary = {}
		for child: Node in holder.get_children():
			var res: Resource = child.get("data")
			if res == null:
				failures.append("%s has no data resource" % child.name)
				continue
			var label: String = res.get("display_name")
			kinds[label] = int(kinds.get(label, 0)) + 1
		print("CHECK gathering nodes: ", holder.get_child_count())
		var names := kinds.keys()
		names.sort()
		for k: String in names:
			print("   %-16s %d" % [k, kinds[k]])

	var props := map.get_node_or_null("ReplicatedPropsContainer")
	if props == null:
		failures.append("ReplicatedPropsContainer missing")
	else:
		var id_map: Dictionary = props.get("id_to_node")
		var node_map: Dictionary = props.get("node_to_id")
		print("CHECK replicated props: children=", props.get_child_count(),
			" id_to_node=", id_map.size(), " node_to_id=", node_map.size())
		if id_map.size() != props.get_child_count():
			failures.append("id_to_node has %d entries for %d children"
				% [id_map.size(), props.get_child_count()])
		if node_map.size() != id_map.size():
			failures.append("node_to_id/id_to_node size mismatch")
		for id: int in id_map:
			var n: Node = id_map[id]
			if n == null or not is_instance_valid(n):
				failures.append("id %d resolves to nothing" % id)
			elif not node_map.has(n) or int(node_map[n]) != id:
				failures.append("round-trip broken for id %d" % id)

	map.free()
	if failures.is_empty():
		print("CHECK OK")
		quit(0)
	else:
		for f: String in failures:
			push_error("CHECK FAIL: " + f)
		printerr("CHECK FAILED with %d problem(s)" % failures.size())
		quit(1)
