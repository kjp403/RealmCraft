extends Node
## Load-and-shape check for Farming herb ladder + Herblore alchemy station.
##
## Runs as a SCENE, not `-s`: under `-s` there are no autoloads, so
## ConsumableItem (which reaches ClientState) fails to compile and every potion
## in the station and the job list loads as null — the check then reports
## cascading false failures. See verify_bank.gd for the same note.
##
##   godot --headless --path . --mode=client res://tools/verify_herblore.tscn

func _ready() -> void:
	var fails: Array[String] = []

	var farm: JobPerks = JobRegistry.perks_for(&"harvesting")
	if farm == null:
		fails.append("JobRegistry missing harvesting")
	elif farm.source_items.size() < 8:
		fails.append("Farming sources expected >= 8, got %d" % farm.source_items.size())
	else:
		print("farming sources=", farm.source_items.size(), " levels=", farm.source_levels)

	var herb: JobPerks = JobRegistry.perks_for(&"herblore")
	if herb == null:
		fails.append("JobRegistry missing herblore")
	else:
		print("herblore=", herb.display_name, " recipes=", herb.recipe_items.size())
		# 7 potion ladder + 4 weapon coatings + the 2 Hollow Seep quest brews.
		if herb.recipe_items.size() != 13:
			fails.append("Herblore recipe_items expected 13, got %d" % herb.recipe_items.size())

	if not JobRegistry.JOBS.has(&"herblore"):
		fails.append("JOBS dict missing herblore")

	var station: CraftingStationResource = load(
		"res://source/common/gameplay/crafting/resources/alchemy_station.tres"
	)
	if station == null:
		fails.append("alchemy_station.tres failed to load")
	else:
		print("station=", station.station_name, " profession=", station.profession,
			" recipes=", station.recipes.size())
		if station.profession != &"herblore":
			fails.append("alchemy station profession should be herblore")
		if station.recipes.size() != 13:
			fails.append("expected 13 brew recipes, got %d" % station.recipes.size())
		for r: CraftingRecipe in station.recipes:
			if r == null or r.output_item == null:
				fails.append("null brew recipe")
				continue
			print("  brew ", r.output_item.item_name, " lv", r.required_level, " xp", r.xp_reward)
			var has_vial := false
			for ing: CraftIngredient in r.ingredients:
				if ing == null or ing.item == null:
					fails.append("null ingredient on %s" % r.output_item.item_name)
					continue
				if String(ing.item.get_meta(&"slug", &"")) == "vial_of_water":
					has_vial = true
					if ing.amount != 1:
						fails.append("%s vial amount %d != 1" % [r.output_item.item_name, ing.amount])
			if not has_vial:
				fails.append("%s missing 1x vial of water" % r.output_item.item_name)

	var herb_slugs: Array[String] = [
		"healing_herb", "frostpetal", "sunwort", "moonbloom",
		"bloodcap", "starblossom", "grimshade",
	]
	var expected_levels: Dictionary = {
		"healing_herb": 1, "frostpetal": 5, "sunwort": 10, "moonbloom": 20,
		"bloodcap": 30, "starblossom": 40, "grimshade": 50,
	}
	for slug: String in herb_slugs:
		var node_res: MineableNodeResource = load(
			"res://source/common/gameplay/maps/components/mineable_nodes/%s.tres" % slug
		)
		if node_res == null:
			fails.append("node %s missing" % slug)
			continue
		if node_res.required_tool != &"sickle":
			fails.append("%s tool should be sickle" % slug)
		# Farming herbs harvest on right-click so woodcutting left-clicks pass through.
		if int(node_res.required_level) != int(expected_levels[slug]):
			fails.append("%s level %d != %d" % [slug, node_res.required_level, expected_levels[slug]])
		if not node_res.job_xp.has(&"harvesting"):
			fails.append("%s missing harvesting xp" % slug)
		print("  node ", slug, " lv", node_res.required_level, " xp", node_res.job_xp.get(&"harvesting", 0))

	for sickle_slug: String in ["sickle", "sickle_iron", "sickle_steel", "sickle_mithril"]:
		var tool: ToolItem = load(
			"res://source/common/gameplay/items/weapons/tools/%s.tres" % sickle_slug
		)
		if tool == null:
			fails.append("tool %s missing" % sickle_slug)
			continue
		if tool.tool_type != &"sickle":
			fails.append("%s tool_type wrong" % sickle_slug)
		if tool.required_skill != &"harvesting":
			fails.append("%s should require harvesting" % sickle_slug)
		print("  tool ", sickle_slug, " farm_lv", tool.required_skill_level)

	if not LeaderboardService.TOTAL_LEVEL_SKILLS.has(&"herblore"):
		fails.append("TOTAL_LEVEL_SKILLS missing herblore")

	var mira_shop: ShopResource = load(
		"res://source/common/gameplay/shops/resources/miras_apothecary.tres"
	)
	if mira_shop == null:
		fails.append("miras_apothecary.tres failed to load")
	else:
		var vial_price := 0
		for entry: ShopEntry in mira_shop.entries:
			if entry == null or entry.item == null:
				continue
			if String(entry.item.get_meta(&"slug", &"")) == "vial_of_water":
				vial_price = entry.price
		if vial_price != 1000:
			fails.append("Mira should sell vial of water for 1000, got %d" % vial_price)

	var potion_buybacks: Dictionary = {
		"res://source/common/gameplay/items/consumables/minor_health_potion.tres": 375,
		"res://source/common/gameplay/items/consumables/minor_mana_potion.tres": 563,
		"res://source/common/gameplay/items/consumables/health_potion.tres": 750,
		"res://source/common/gameplay/items/consumables/mana_potion.tres": 1125,
		"res://source/common/gameplay/items/consumables/greater_health_potion.tres": 1125,
		"res://source/common/gameplay/items/consumables/greater_mana_potion.tres": 1500,
	}
	for path: String in potion_buybacks.keys():
		var potion: Item = load(path)
		var want: int = int(potion_buybacks[path])
		if potion == null:
			fails.append("%s failed to load" % path.get_file())
		elif potion.vendor_value != want:
			fails.append("%s vendor_value %d, want %d (75%% buyback)" % [
				path.get_file(), potion.vendor_value, want
			])

	if fails.is_empty():
		print("VERIFY_PASS herblore")
		get_tree().quit(0)
	else:
		for f: String in fails:
			print("VERIFY_FAIL ", f)
		get_tree().quit(1)
