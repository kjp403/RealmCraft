extends SceneTree
## Headless smoke checks for smithing anvil + slayer house wiring.


func _init() -> void:
	var failures: PackedStringArray = PackedStringArray()

	var anvil: Resource = load("res://source/common/gameplay/crafting/resources/anvil.tres")
	if anvil == null:
		failures.append("anvil.tres failed to load")
	elif str(anvil.get("station_name")) != "Smithing Table":
		failures.append("anvil station_name missing")
	elif int(anvil.get("recipes").size()) < 70:
		failures.append("anvil recipes too few: %d" % int(anvil.get("recipes").size()))

	var house: Resource = load("res://source/common/gameplay/maps/instance/instance_collection/building/slayer_house.tres")
	if house == null or not (house is InstanceResource):
		failures.append("slayer_house.tres missing")
	else:
		var ir: InstanceResource = house
		if ir.zone_title != "Slayer House":
			failures.append("zone_title not Slayer House")
		if not ir.show_discovery:
			failures.append("show_discovery false")
		var map_scene: PackedScene = load(ir.map_path) as PackedScene
		if map_scene == null:
			failures.append("slayer house map failed to load")
		else:
			var map_node: Node = map_scene.instantiate()
			if map_node.get_node_or_null("Turael") == null:
				failures.append("Turael missing in slayer house")
			if map_node.get_node_or_null("Entrance") == null:
				failures.append("Entrance warper missing")
			map_node.free()

	var woodland: PackedScene = load("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn") as PackedScene
	if woodland == null:
		failures.append("woodland_tiles failed to load")
	else:
		var w: Node = woodland.instantiate()
		if w.get_node_or_null("SlayerHouseDoor") == null:
			failures.append("SlayerHouseDoor missing in woodland")
		w.free()

	var forest: PackedScene = load("res://source/common/gameplay/maps/maps/forest/forest.tscn") as PackedScene
	if forest == null:
		failures.append("forest failed to load")
	else:
		var f: Node = forest.instantiate()
		if f.get_node_or_null("Durael") == null:
			failures.append("Durael missing in Dimwood")
		f.free()

	var menu: PackedScene = load("res://source/client/ui/menus/slayer/slayer_menu.tscn") as PackedScene
	if menu == null:
		failures.append("slayer_menu.tscn missing")

	for path: String in [
		"res://source/server/world/components/data_request_handlers/slayer.status.gd",
		"res://source/server/world/components/data_request_handlers/slayer.assign.gd",
		"res://source/server/world/components/data_request_handlers/slayer.skip.gd",
	]:
		if load(path) == null:
			failures.append("handler missing: %s" % path)

	# Bosses still grant ornate (T3 pink = 249).
	for boss_path: String in [
		"res://source/common/gameplay/characters/npc/types/bosses/cinderborn.tres",
		"res://source/common/gameplay/characters/npc/types/bosses/sand_king.tres",
		"res://source/common/gameplay/characters/npc/types/bosses/cistern_sovereign.tres",
		"res://source/common/gameplay/characters/npc/types/trpg/trpg_necromancer.tres",
	]:
		var boss: Resource = load(boss_path)
		if boss == null or int(boss.get("ornate_chest_top_max")) <= 0:
			failures.append("ornate off: %s" % boss_path)

	if RewardService.ORNATE_CHEST_IDS != [249]:
		failures.append("ORNATE_CHEST_IDS should be T3-only [249]")

	if failures.is_empty():
		print("VERIFY_PASS slayer_house_smithing_ornate")
		quit(0)
	else:
		for f: String in failures:
			print("VERIFY_FAIL ", f)
		quit(1)
