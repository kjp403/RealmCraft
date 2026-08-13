extends SceneTree
## Headless checks for Mining Cave (no skill gate), hub workbench placement,
## and mithril/adamant/runite mining + smithing level gates.
## Run: godot --headless --path . -s tools/verify_mining_gate_workbench.gd
## Expect: VERIFY_PASS

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

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
	if cave_text.find("DeepVeinGate") >= 0:
		failures.append("mining_cave still has DeepVeinGate — the alcove must be open")
	if cave_text.find("skill_level_gate.gd") >= 0:
		failures.append("mining_cave still references skill_level_gate.gd")
	if cave_text.find("AdamantVein") < 0:
		failures.append("mining_cave missing adamant veins")
	if cave_text.find("RuniteVein") < 0:
		failures.append("mining_cave missing runite veins")

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

	var expect_mine: Dictionary = {"mithril": 35, "adamant": 50, "runite": 60}
	for metal: String in expect_mine.keys():
		var vein: String = FileAccess.get_file_as_string(
			"res://source/common/gameplay/maps/components/mineable_nodes/%s_vein.tres" % metal
		)
		if vein.find("required_level = %d" % int(expect_mine[metal])) < 0:
			failures.append("%s vein required_level != %d" % [metal, int(expect_mine[metal])])

	var mining_guide: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/jobs/mining.tres"
	)
	if mining_guide.find("source_levels = Array[int]([0, 0, 5, 15, 20, 35, 40, 50, 60])") < 0:
		failures.append("mining.tres skill-guide source_levels are stale")

	var furnace: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/crafting/resources/furnace.tres"
	)
	if furnace.find("required_level = 35") < 0:
		failures.append("furnace missing mithril smithing 35")
	if furnace.find("required_level = 50") < 0:
		failures.append("furnace missing adamant smithing 50")
	if furnace.find("required_level = 65") < 0:
		failures.append("furnace missing runite smithing 65")

	var anvil: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/crafting/resources/anvil.tres"
	)
	_expect_recipe_level(failures, anvil, "R_mi_arr", 35, "anvil mithril arrowheads")
	_expect_recipe_level(failures, anvil, "R_ad_arr", 50, "anvil adamant arrowheads")
	_expect_recipe_level(failures, anvil, "R_ru_arr", 65, "anvil runite arrowheads")
	_expect_recipe_level(failures, anvil, "R_wpn_mithril_sword", 35, "anvil mithril sword")
	_expect_recipe_level(failures, anvil, "R_wpn_adamant_sword", 50, "anvil adamant sword")
	_expect_recipe_level(failures, anvil, "R_wpn_runite_sword", 65, "anvil runite sword")

	var smithing_guide: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/jobs/smithing.tres"
	)
	if smithing_guide.find("recipe_levels = Array[int]([1, 1, 1, 1, 1, 5, 5, 5, 5, 5, 10, 10, 10, 10, 15, 15, 15, 15, 15, 15, 15, 15, 35, 35, 50, 50, 65, 65, 35, 35, 35, 50, 50, 50, 65, 65, 65])") < 0:
		failures.append("smithing.tres skill-guide recipe_levels are stale")
	if smithing_guide.find("recipe_deferred_levels = Array[int]([1, 1, 1, 1, 1, 5, 5, 5, 5, 5, 15, 15, 15, 15, 15, 35, 35, 35, 35, 35, 50, 50, 50, 50, 50, 65, 65, 65, 65, 65])") < 0:
		failures.append("smithing.tres skill-guide recipe_deferred_levels are stale")

	var smith_res: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/instance/instance_collection/building/smith_house.tres"
	)
	if smith_res.find("maps/smith_house/inside_map.tscn") < 0:
		failures.append("smith_house map_path must be a res:// scene path (uid:// drops clients)")
	var client_im: String = FileAccess.get_file_as_string(
		"res://source/client/network/instance_manager.gd"
	)
	if client_im.find("pending_spawn") < 0 or client_im.find("_resolve_map_path") < 0:
		failures.append("client instance manager must stash spawn and resolve uid map paths")
	var inv: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/items/inventory.gd"
	)
	if inv.find("const BANK_RESOURCE_STACK: int = 50") < 0:
		failures.append("bank resource stacks must cap at 50")
	var outfitting_guide: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/jobs/outfitting.tres"
	)
	if outfitting_guide.count("gears/cloth/") < 20:
		failures.append("outfitting.tres skill-guide is missing most cloth recipes")
	if outfitting_guide.find("cloth_vest.tres") < 0 or outfitting_guide.find("apprentice_robe.tres") < 0:
		failures.append("outfitting.tres skill-guide missing starter cloth set")

	var cloth_hood: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/items/gears/cloth/cloth_hood.tres"
	)
	var hood_res: int = cloth_hood.find("[resource]")
	if hood_res < 0 or cloth_hood.find("vendor_value = 4", hood_res) < 0:
		failures.append("cloth_hood vendor_value must sit on the GearItem (not the stat modifier)")

	if failures.is_empty():
		print("VERIFY_PASS mining_gate smith_house_stations")
		quit(0)
	else:
		print("VERIFY_FAIL")
		for line: String in failures:
			print("  - ", line)
		quit(1)


func _expect_recipe_level(
	failures: PackedStringArray, body: String, recipe_id: String, level: int, label: String
) -> void:
	var needle: String = "id=\"%s\"" % recipe_id
	var idx: int = body.find(needle)
	if idx < 0:
		failures.append("%s missing (%s)" % [label, recipe_id])
		return
	var lvl_idx: int = body.find("required_level = %d" % level, idx)
	if lvl_idx < 0 or lvl_idx > idx + 400:
		failures.append("%s required_level != %d" % [label, level])
