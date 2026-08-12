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

	# Crafting stations live inside the smith/tailor house (not outdoors on hub).
	var hub_text: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/hub.tscn"
	)
	if hub_text.find("WorkBenchStation") >= 0:
		failures.append("hub still has outdoor WorkBenchStation (should be in smith_house)")
	var smith_text: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/smith_house/inside_map.tscn"
	)
	for station_name: String in [
		"FurnaceStation", "AnvilStation", "WorkBenchStation", "AscendedWorkBenchStation"
	]:
		if smith_text.find("[node name=\"%s\"" % station_name) < 0:
			failures.append("smith_house missing %s" % station_name)
	if smith_text.find("ascended_workbench.tres") < 0:
		failures.append("smith_house Ascended Workbench not wired to ascended_workbench.tres")

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
	if gate_src.find("eject_direction") < 0:
		failures.append("gate missing eject_direction (null-spot fix)")
	if cave_text.find("eject_direction = Vector2(-1, 0)") < 0:
		failures.append("DeepVeinGate missing leftward eject_direction")
	# Skiller-safe wildlife: Mining Cave must not share aggressive trpg_bat.
	if cave_text.find("trpg/trpg_bat.tres") >= 0:
		failures.append("mining_cave CaveBats still use aggressive trpg_bat")
	if cave_text.find("types/cave_bat.tres") < 0:
		failures.append("mining_cave must use cave_bat.tres (chase_on_area=false)")
	var cave_bat_text: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/characters/npc/types/cave_bat.tres"
	)
	if cave_bat_text.find("chase_on_area = false") < 0:
		failures.append("cave_bat must be passive (chase_on_area=false)")

	if failures.is_empty():
		print("VERIFY_PASS mining_gate smith_house_stations")
		quit(0)
	else:
		print("VERIFY_FAIL")
		for line: String in failures:
			print("  - ", line)
		quit(1)
