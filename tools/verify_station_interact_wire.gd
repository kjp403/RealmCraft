extends SceneTree
## Ensures crafting stations load WITH CraftingStation scripts (regression for the
## Godot 4.7 "INTERACT_RANGE already exists in parent" parse break).


func _initialize() -> void:
	var failed := false

	var station_script: Script = load("res://source/common/gameplay/crafting/crafting_station.gd") as Script
	if station_script == null:
		push_error("crafting_station.gd failed to load (parse/compile error)")
		print("VERIFY_FAIL")
		quit(1)
		return
	print("ok crafting_station.gd loads")

	var scene: PackedScene = load(
		"res://source/common/gameplay/maps/maps/smith_house/inside_map.tscn"
	) as PackedScene
	if scene == null:
		push_error("smith_house scene failed to load")
		print("VERIFY_FAIL")
		quit(1)
		return

	var root: Node = scene.instantiate()
	var required: PackedStringArray = PackedStringArray([
		"FurnaceStation",
		"AnvilStation",
		"WorkBenchStation",
		"AscendedWorkBenchStation",
		"FletchingBenchStation",
		"AlchemyTable",
	])
	for name: String in required:
		var node: Node = root.get_node_or_null(NodePath(name))
		if node == null:
			push_error("smith_house missing %s" % name)
			failed = true
			continue
		if node.get_script() != station_script:
			push_error("%s has no CraftingStation script (got %s)" % [name, str(node.get_script())])
			failed = true
			continue
		if node.get("station") == null:
			push_error("%s has null station resource" % name)
			failed = true
			continue
		var shape: CollisionShape2D = node.get_node_or_null(NodePath("CollisionShape2D")) as CollisionShape2D
		if shape == null or shape.shape == null:
			push_error("%s missing CollisionShape2D" % name)
			failed = true
			continue
		print("ok %s script+station+shape" % name)

	root.free()
	if failed:
		print("VERIFY_FAIL")
		quit(1)
	else:
		print("VERIFY_PASS")
		quit(0)
