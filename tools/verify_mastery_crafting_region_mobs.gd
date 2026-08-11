extends SceneTree
## Headless checks for mastery point budget, crafting XP buffs, Badger slayer,
## and new region monster variants.
## Run: godot --headless --path . -s tools/verify_mastery_crafting_region_mobs.gd
## Expect: VERIFY_PASS

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	# --- Mastery: 1 point per level -----------------------------------------
	var mastery: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/mastery/mastery_service.gd"
	)
	if mastery.find("const POINTS_PER_LEVEL: int = 1") < 0:
		failures.append("POINTS_PER_LEVEL must be 1")

	# --- Crafting XP buffed + perk multiplier on server ---------------------
	var craft: String = FileAccess.get_file_as_string(
		"res://source/server/world/components/data_request_handlers/craft.item.gd"
	)
	if craft.find("xp_multiplier") < 0:
		failures.append("craft.item.gd must apply JobPerks xp_multiplier")
	var wb: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/crafting/resources/workbench.tres"
	)
	# leather jacket was 14 → 42 at 3×
	if wb.find("xp_reward = 42") < 0:
		failures.append("workbench leather jacket XP should be 42 after 3× buff")

	# --- Slayer: Badgers (file slug stays rats for save compat) -------------
	var rats: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/slayer/tasks/rats.tres"
	)
	if rats.find('display_name = "Badgers"') < 0:
		failures.append("rats.tres display_name must be Badgers")
	if rats.find("&\"badger\"") < 0 or rats.find("&\"desert_badger\"") < 0:
		failures.append("Badgers task missing badger / desert_badger")
	if rats.find("&\"rat_base\"") >= 0:
		failures.append("Badgers task should not include rat_base")

	var wolves: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/slayer/tasks/wolves.tres"
	)
	if wolves.find("&\"rabid_wolf\"") < 0:
		failures.append("Wolves task missing rabid_wolf")

	# --- Region monster defs ------------------------------------------------
	for path_slug in [
		["res://source/common/gameplay/characters/npc/types/badger.tres", "26", "150"],
		["res://source/common/gameplay/characters/npc/types/desert_badger.tres", "34", "250"],
		["res://source/common/gameplay/characters/npc/types/rabid_wolf.tres", "44", "325"],
		["res://source/common/gameplay/characters/npc/types/angry_bat.tres", "32", "190"],
	]:
		var body: String = FileAccess.get_file_as_string(path_slug[0])
		if body.find("combat_level = %s" % path_slug[1]) < 0:
			failures.append("%s missing combat_level %s" % [path_slug[0], path_slug[1]])
		if body.find("max_health = %s.0" % path_slug[2]) < 0 \
				and body.find("max_health = %s" % path_slug[2]) < 0:
			failures.append("%s missing max_health %s" % [path_slug[0], path_slug[2]])

	var woodland_rat: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/characters/npc/types/woodland_rat.tres"
	)
	if woodland_rat.find("combat_level = 18") < 0 or woodland_rat.find("max_health = 75") < 0:
		failures.append("Woodland Badger stats drifted from 18 / 75")
	if woodland_rat.find("hide_forest") < 0:
		failures.append("Woodland Badger should drop hide_forest")

	# --- Placements ---------------------------------------------------------
	var east: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/woodland/woodland_east.tscn"
	)
	for name: String in ["EastBadger1", "RabidWolf1", "AngryBat1"]:
		if east.find(name) < 0:
			failures.append("woodland_east missing %s" % name)

	var desert: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/desert/desert.tscn"
	)
	if desert.find("DesertBadger1") < 0:
		failures.append("desert missing DesertBadger1")

	var wood: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
	)
	if wood.find("CamelDesertBadger1") < 0:
		failures.append("woodland missing CamelDesertBadger near camel")
	# Sync map must include rats 15–56 (previously truncated after Rat14).
	if wood.find("88: NodePath(\"WoodlandRat56\")") < 0 \
			and wood.find('88: NodePath("WoodlandRat56")') < 0:
		failures.append("woodland id_to_node missing WoodlandRat56")
	if wood.find("46: NodePath(\"WoodlandRat14\")\n},") >= 0:
		failures.append("woodland id_to_node still prematurely closed after Rat14")

	var index: String = FileAccess.get_file_as_string(
		"res://source/common/registry/indexes/enemy_types_index.tres"
	)
	for slug: String in ["badger", "desert_badger", "rabid_wolf", "angry_bat"]:
		if index.find("&\"%s\"" % slug) < 0:
			failures.append("enemy_types_index missing %s" % slug)

	if failures.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL")
		for f: String in failures:
			print(" - ", f)
	quit(0 if failures.is_empty() else 1)
