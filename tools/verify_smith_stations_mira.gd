extends SceneTree
## Verifies crafting stations compile/interact wiring + Mira/Alchemy placement
## in the smith house.


func _initialize() -> void:
	var failed := false

	# Controllers must resolve as global classes (missing .uid previously broke LocalPlayer).
	if ClassDB.class_exists(&"InteractController") or true:
		# class_name scripts aren't ClassDB engine classes — load them directly.
		var ic: Script = load("res://source/client/local_player/interact_controller.gd") as Script
		var cc: Script = load("res://source/client/local_player/craft_controller.gd") as Script
		var lp: Script = load("res://source/client/local_player/local_player.gd") as Script
		if ic == null or cc == null or lp == null:
			push_error("failed to load interact/craft/local_player scripts")
			failed = true
		else:
			print("ok controller scripts load")

	var smith: PackedScene = load(
		"res://source/common/gameplay/maps/maps/smith_house/inside_map.tscn"
	) as PackedScene
	if smith == null:
		push_error("smith_house scene failed to load")
		print("VERIFY_FAIL")
		quit(1)
		return

	var root: Node = smith.instantiate()
	var required: PackedStringArray = PackedStringArray([
		"FurnaceStation",
		"AnvilStation",
		"WorkBenchStation",
		"AscendedWorkBenchStation",
		"FletchingBenchStation",
		"AlchemyTable",
		"Mira",
	])
	for name: String in required:
		var node: Node = root.get_node_or_null(NodePath(name))
		if node == null:
			push_error("smith_house missing %s" % name)
			failed = true
			continue
		print("ok %s at %s" % [name, str((node as Node2D).position)])

	var mira: Node2D = root.get_node_or_null(NodePath("Mira")) as Node2D
	if mira != null and mira.position != Vector2(-101, 335):
		push_error("Mira at %s expected (-101, 335)" % str(mira.position))
		failed = true

	var alchemy: Node2D = root.get_node_or_null(NodePath("AlchemyTable")) as Node2D
	if alchemy != null and alchemy.position != Vector2(-290, 293):
		push_error("AlchemyTable at %s expected (-290, 293)" % str(alchemy.position))
		failed = true
	if alchemy is CraftingStation:
		var station: CraftingStation = alchemy as CraftingStation
		if station.station == null:
			push_error("AlchemyTable has no station resource")
			failed = true

	# Woodland must no longer host Mira / AlchemyTable.
	var wood: PackedScene = load(
		"res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
	) as PackedScene
	if wood != null:
		var wood_root: Node = wood.instantiate()
		if wood_root.get_node_or_null(NodePath("NPCs/Mira")) != null \
				or wood_root.get_node_or_null(NodePath("Mira")) != null:
			push_error("woodland still has Mira")
			failed = true
		if wood_root.get_node_or_null(NodePath("AlchemyTable")) != null:
			push_error("woodland still has AlchemyTable")
			failed = true
		else:
			print("ok woodland no longer has Mira/AlchemyTable")
		wood_root.free()

	root.free()

	if failed:
		print("VERIFY_FAIL")
		quit(1)
	else:
		print("VERIFY_PASS")
		quit(0)
