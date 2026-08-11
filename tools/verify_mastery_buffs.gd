extends SceneTree
## Load every mastery tree and print node/ability sanity checks.


func _init() -> void:
	var fails: PackedStringArray = PackedStringArray()
	var dir := "res://source/common/gameplay/mastery/trees/"
	for file_name: String in ResourceLoader.list_directory(dir):
		if not file_name.ends_with(".tres"):
			continue
		var tree: MasteryTreeResource = load(dir + file_name) as MasteryTreeResource
		if tree == null:
			fails.append("FAIL load %s" % file_name)
			continue
		print("TREE ", tree.category, " nodes=", tree.nodes.size(), " cost=", tree.total_cost())
		var ids: Dictionary = {}
		for node: MasteryNode in tree.nodes:
			if ids.has(String(node.id)):
				fails.append("DUP id %s in %s" % [node.id, file_name])
			ids[String(node.id)] = true
			if node.tier < 1 or node.tier > 5:
				fails.append("BAD tier %s %s" % [node.id, node.tier])
			if not node.upgrades.is_empty() and not ids.has(String(node.upgrades)) \
					and tree.get_node_by_id(node.upgrades) == null:
				fails.append("MISSING upgrades target %s -> %s" % [node.id, node.upgrades])
			# Ability nodes must resolve a registry id.
			if node.ability != null:
				var aid: int = int(node.ability.get_meta(&"id", 0))
				if aid <= 0:
					fails.append("NO ability id on %s (%s)" % [node.id, node.ability.resource_path])
				# Spot-check a few key ratios via duck typing.
				if node.id == &"sword_whirlwind_5" and "damage_ratio" in node.ability:
					if absf(float(node.ability.damage_ratio) - 1.25) > 0.001:
						fails.append("WW5 ratio %s" % node.ability.damage_ratio)
				if node.id == &"wand_meteor" and "ap_ratio" in node.ability:
					if absf(float(node.ability.ap_ratio) - 5.0) > 0.001:
						fails.append("Meteor4 ratio %s" % node.ability.ap_ratio)
				if node.id == &"wand_frost_nova_4" and "ap_ratio" in node.ability:
					if absf(float(node.ability.ap_ratio) - 2.5) > 0.001:
						fails.append("Frost4 ratio %s" % node.ability.ap_ratio)
				if node.id == &"hammer_aura_4" and "heal_per_tick" in node.ability:
					if absf(float(node.ability.heal_per_tick) - 16.0) > 0.001:
						fails.append("Aura4 heal %s" % node.ability.heal_per_tick)
	# Second pass for upgrades now that all ids known per tree
	for file_name: String in ResourceLoader.list_directory(dir):
		if not file_name.ends_with(".tres"):
			continue
		var tree: MasteryTreeResource = load(dir + file_name) as MasteryTreeResource
		if tree == null:
			continue
		for node: MasteryNode in tree.nodes:
			if not node.upgrades.is_empty() and tree.get_node_by_id(node.upgrades) == null:
				fails.append("BAD upgrades %s -> %s" % [node.id, node.upgrades])

	if fails.is_empty():
		print("VERIFY_PASS")
	else:
		for f: String in fails:
			print(f)
		print("VERIFY_FAIL count=", fails.size())
	quit()
