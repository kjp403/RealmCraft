extends SceneTree
## Load every Dragon/Obsidian/Celestial/Astralite ore, bar, vein and tool.

func _initialize() -> void:
	var paths: PackedStringArray = []
	for tier: String in ["dragon", "obsidian", "celestial", "astralite"]:
		paths.append("res://source/common/gameplay/items/materials/metals/%s_ore.tres" % tier)
		paths.append("res://source/common/gameplay/items/materials/metals/%s_bar.tres" % tier)
		paths.append("res://source/common/gameplay/maps/components/mineable_nodes/%s_vein.tres" % tier)
		for kind: String in ["pickaxe", "axe", "sickle"]:
			paths.append("res://source/common/gameplay/items/weapons/tools/%s_%s.tres" % [kind, tier])
	paths.append("res://source/common/gameplay/items/weapons/tools/fishing_rod_dragon.tres")
	paths.append("res://source/common/gameplay/crafting/resources/furnace.tres")
	paths.append("res://source/common/gameplay/crafting/resources/anvil.tres")
	paths.append("res://source/common/gameplay/jobs/mining.tres")
	var bad: int = 0
	for path: String in paths:
		var res: Resource = load(path)
		if res == null:
			push_error("FAILED " + path)
			bad += 1
		else:
			print("ok ", path)
	print("HIGH_ORE_TIER_VERIFY bad=", bad)
	quit(0)
