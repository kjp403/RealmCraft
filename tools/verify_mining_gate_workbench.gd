extends SceneTree
## Headless checks for Mining 50+ gate + hub workbench placement.
## Run: godot --headless --path . -s tools/verify_mining_gate_workbench.gd
## Expect: VERIFY_PASS

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	# Qualification math: level >= required (same rule the gate uses).
	if not (50 >= 50):
		failures.append("50 >= 50 should pass")
	if 49 >= 50:
		failures.append("49 >= 50 should fail")
	if not (99 >= 50):
		failures.append("99 >= 50 should pass")

	# PlayerResource path the gate reads on the server.
	var res := PlayerResource.new()
	res.skills[&"mining"] = {"level": 50, "xp": 0, "perks": {}}
	if int(res.get_skill(&"mining").get("level", 1)) < 50:
		failures.append("get_skill mining 50 failed")
	res.skills[&"mining"] = {"level": 49, "xp": 0, "perks": {}}
	if int(res.get_skill(&"mining").get("level", 1)) >= 50:
		failures.append("get_skill mining 49 should be under gate")

	# Workbench moved next to the tailor.
	var hub_text: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/hub.tscn"
	)
	if hub_text.find("WorkBenchStation") < 0:
		failures.append("hub missing WorkBenchStation")
	elif not _workbench_at(hub_text, Vector2(-539, -119)):
		failures.append("WorkBenchStation not at (-539, -119)")

	var cave_text: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"
	)
	if cave_text.find("DeepVeinGate") < 0:
		failures.append("mining_cave missing DeepVeinGate")
	if cave_text.find("required_level = 50") < 0:
		failures.append("DeepVeinGate required_level != 50")
	if cave_text.find("label_text = \"Mining 50+\"") < 0:
		failures.append("DeepVeinGate label missing Mining 50+")

	var gate_src: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/components/skill_level_gate.gd"
	)
	if gate_src.find("ClientState.skill_level") < 0:
		failures.append("gate missing ClientState.skill_level client path")
	if gate_src.find(">= required_level") < 0:
		failures.append("gate missing >= required_level check")

	if failures.is_empty():
		print("VERIFY_PASS mining_gate workbench=(-539,-119)")
		quit(0)
	else:
		print("VERIFY_FAIL")
		for line: String in failures:
			print("  - ", line)
		quit(1)


func _workbench_at(hub_text: String, want: Vector2) -> bool:
	var idx: int = hub_text.find("[node name=\"WorkBenchStation\"")
	if idx < 0:
		return false
	var chunk: String = hub_text.substr(idx, 280)
	return chunk.find("position = Vector2(%d, %d)" % [int(want.x), int(want.y)]) >= 0
