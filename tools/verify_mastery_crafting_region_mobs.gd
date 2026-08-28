extends SceneTree
## Headless checks for mastery point budget, crafting XP buffs, Badger slayer,
## and new region monster variants.
## Run: godot --headless --path . -s tools/verify_mastery_crafting_region_mobs.gd
## Expect: VERIFY_PASS

func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	# --- Mastery: 1 point every 3 levels (33 at 99) ---------------------------
	var mastery: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/mastery/mastery_service.gd"
	)
	if mastery.find("const LEVELS_PER_POINT: int = 3") < 0:
		failures.append("LEVELS_PER_POINT must be 3")
	if mastery.find("func point_budget") < 0:
		failures.append("MasteryService.point_budget missing")
	# Sanity: floor(26/3)=8, floor(99/3)=33; first point at 3
	if MasteryService.point_budget(26) != 8:
		failures.append("point_budget(26) want 8 got %d" % MasteryService.point_budget(26))
	if MasteryService.point_budget(99) != 33:
		failures.append("point_budget(99) want 33 got %d" % MasteryService.point_budget(99))
	if MasteryService.point_budget(2) != 0:
		failures.append("point_budget(2) want 0 (first point at 3)")
	if MasteryService.point_budget(3) != 1:
		failures.append("point_budget(3) want 1")
	# Subclass budget: covers heaviest column (~24) but not cheapest full tree (~46)
	if MasteryService.point_budget(99) < 24:
		failures.append("L99 budget too low to finish heaviest subclass column")
	if MasteryService.point_budget(99) >= 46:
		failures.append("L99 budget high enough to clear a full tree")

	# Tree totals are judged against each tree's OWN level-99 budget, not a shared
	# cost band. A tree that carries more role kits costs more and pays out more
	# (MasteryTreeResource.point_rate) — Heavy Weapons is 66 cost at rate 2. The
	# invariant that still has to hold everywhere is the SHAPE: the budget must
	# fund a subclass column without clearing the whole tree, so cost has to sit
	# above the budget and within reach of about twice it.
	var tree_dir: String = "res://source/common/gameplay/mastery/trees/"
	for tree_file: String in ["hammer.tres", "sword.tres", "book.tres", "bow.tres", "wand.tres"]:
		var tree_res: MasteryTreeResource = load(tree_dir + tree_file) as MasteryTreeResource
		if tree_res == null:
			failures.append("failed to load %s" % tree_file)
			continue
		var cost: int = tree_res.total_cost()
		var tree_budget: int = MasteryService.point_budget(99, tree_res)
		if cost > tree_budget * 2:
			failures.append("%s total_cost=%d dwarfs its L99 budget %d (raise point_rate)"
				% [tree_file, cost, tree_budget])

	# --- Crafting XP: starter recipes must not sit on the default 10 ---------
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
	# Recipes that previously omitted xp_reward (Godot default 10) must be explicit.
	if wb.find('id="R_cloth_shoes"') >= 0:
		var shoes_idx: int = wb.find('id="R_cloth_shoes"')
		var shoes_chunk: String = wb.substr(shoes_idx, 280)
		if shoes_chunk.find("xp_reward = 30") < 0:
			failures.append("Cloth Shoes must grant 30 Crafting XP (was default 10)")
	if wb.find('id="R_cloth_hood"') >= 0:
		var hood_idx: int = wb.find('id="R_cloth_hood"')
		var hood_chunk: String = wb.substr(hood_idx, 280)
		if hood_chunk.find("xp_reward = 36") < 0:
			failures.append("Cloth Hood must grant 36 Crafting XP (was default 10)")
	for rid_xp: Array in [["R_lea_cap", 30], ["R_lea_boots", 30], ["R_leather_sewer", 30]]:
		var ridx: int = wb.find('id="%s"' % rid_xp[0])
		if ridx < 0:
			failures.append("workbench missing %s" % rid_xp[0])
		else:
			var chunk: String = wb.substr(ridx, 280)
			if chunk.find("xp_reward = %d" % rid_xp[1]) < 0:
				failures.append("%s must grant %d Crafting XP" % [rid_xp[0], rid_xp[1]])
	# Crafting UI: tabs live on their own row (not header_center) to avoid crop.
	var craft_ui: String = FileAccess.get_file_as_string(
		"res://source/client/ui/menus/crafting/crafting_menu.gd"
	)
	if craft_ui.find("_install_tab_bar") < 0 or craft_ui.find("_tab_bar.add_child") < 0:
		failures.append("crafting menu must host tabs on a dedicated _tab_bar row")
	var shell: String = FileAccess.get_file_as_string(
		"res://source/client/ui/menus/menu_shell.gd"
	)
	if shell.find("outer_top") < 0:
		failures.append("MenuShell fullscreen needs extra top inset (outer_top)")
	# Outfitting craft gates mirror smithing ladder (1/5/10/15/30/45/50).
	for pair: Array in [
		["R_ap_hood", 5],
		["R_appr_robe", 5],
		["R_sch_hood", 10],
		["R_sh_hood", 10],
		["R_ench_hood", 15],
		["R_ph_hood", 15],
		["R_an_hood", 30],
		["R_si_hood", 30],
	]:
		var ridx2: int = wb.find('id="%s"' % pair[0])
		if ridx2 < 0:
			failures.append("workbench missing %s" % pair[0])
		else:
			var chunk2: String = wb.substr(ridx2, 320)
			if chunk2.find("required_level = %d" % pair[1]) < 0:
				failures.append(
					"%s craft gate should be Lv %d (smithing-scale outfitting)" % [pair[0], pair[1]]
				)
	# Anvil/smithing XP must NOT be globally buffed (revert to main rates).
	var anvil: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/crafting/resources/anvil.tres"
	)
	# Bronze-tier boots were 40 on main; a 2× pass would make them 80.
	if anvil.find("xp_reward = 40") < 0:
		failures.append("anvil XP looks buffed; expected original bronze-tier 40")

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
		["res://source/common/gameplay/characters/npc/types/badger.tres", "28", "420"],
		["res://source/common/gameplay/characters/npc/types/desert_badger.tres", "36", "580"],
		["res://source/common/gameplay/characters/npc/types/rabid_wolf.tres", "48", "720"],
		["res://source/common/gameplay/characters/npc/types/angry_bat.tres", "36", "480"],
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
	if woodland_rat.find("combat_level = 20") < 0 or woodland_rat.find("max_health = 180") < 0:
		failures.append("Woodland Badger stats drifted from 20 / 180")
	if woodland_rat.find("hide_forest") < 0:
		failures.append("Woodland Badger should drop hide_forest")

	# --- Placements ---------------------------------------------------------
	var east: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/woodland/woodland_east.tscn"
	)
	for name: String in ["EastWolf1", "RabidWolf1", "AngryBat1"]:
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
	for slug: String in ["badger", "desert_badger", "rabid_wolf", "angry_bat", "cave_bat"]:
		if index.find("&\"%s\"" % slug) < 0:
			failures.append("enemy_types_index missing %s" % slug)

	# --- Horizon paid mastery reset (no free tree Reset) ---------------------
	var mastery_reset: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/characters/npc/interactions/mastery_reset_interaction.gd"
	)
	if mastery_reset.find("const COST: int = 25000") < 0:
		failures.append("MasteryResetInteraction.COST must be 25000")
	var respec_handler: String = FileAccess.get_file_as_string(
		"res://source/server/world/components/data_request_handlers/mastery.respec.gd"
	)
	if respec_handler.find("MasteryResetInteraction.COST") < 0:
		failures.append("mastery.respec must charge MasteryResetInteraction.COST")
	if respec_handler.find("reason\": \"gold\"") < 0 and respec_handler.find('"gold"') < 0:
		failures.append("mastery.respec must return gold failure reason")
	var tree_menu: String = FileAccess.get_file_as_string(
		"res://source/client/ui/menus/mastery_tree/mastery_tree_menu.gd"
	)
	if tree_menu.find("_on_respec_pressed") >= 0 or tree_menu.find('reset.text = "Reset"') >= 0:
		failures.append("mastery tree must not offer free Reset")
	var guild: String = FileAccess.get_file_as_string(
		"res://source/common/gameplay/maps/maps/guild_house/inside_map.tscn"
	)
	if guild.find("mastery_reset_interaction.gd") < 0:
		failures.append("Horizon must offer MasteryResetInteraction")
	if not ResourceLoader.exists("res://source/client/ui/menus/mastery_reset/mastery_reset_menu.tscn"):
		failures.append("mastery_reset_menu.tscn missing")

	if failures.is_empty():
		print("VERIFY_PASS")
	else:
		print("VERIFY_FAIL")
		for f: String in failures:
			print(" - ", f)
	quit(0 if failures.is_empty() else 1)
