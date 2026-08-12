extends SceneTree
## Load-and-shape check for the Fletching skill content: the job resource, the
## bench recipes, the 7 new items, the ammo slot, and the tree byproducts.
## Run: godot --headless -s tools/verify_fletching.gd

func _init() -> void:
	var fails: Array[String] = []

	var job: JobPerks = JobRegistry.perks_for(&"fletching")
	if job == null:
		fails.append("JobRegistry has no &\"fletching\"")
	else:
		print("job=", job.display_name, " category=", job.category, " perks=", job.perks.size())
		var maxed: Dictionary = {&"straight_grain": 3}
		print("  shaft_yield_factor(r3)=", job.shaft_yield_factor(maxed))
		if not is_equal_approx(job.shaft_yield_factor(maxed), 1.0):
			fails.append("Straight Grain rank 3 should reach 1.0")
		if not is_zero_approx(job.shaft_yield_factor({})):
			fails.append("shaft yield must be 0 with no ranks")

	var bench: CraftingStationResource = load(
		"res://source/common/gameplay/crafting/resources/fletching_bench.tres"
	)
	if bench == null:
		fails.append("fletching_bench.tres failed to load")
	else:
		print("bench=", bench.station_name, " profession=", bench.profession,
			" recipes=", bench.recipes.size())
		if bench.recipes.size() != 11:
			fails.append("expected 11 bench recipes, got %d" % bench.recipes.size())
		for r: CraftingRecipe in bench.recipes:
			if r == null or r.output_item == null:
				fails.append("bench recipe with null output")
				continue
			var out_id: int = int(r.output_item.get_meta(&"id", 0))
			if out_id <= 0:
				fails.append("output %s has no registry id" % r.output_item.item_name)
			for ing: CraftIngredient in r.ingredients:
				if ing == null or ing.item == null:
					fails.append("null ingredient on %s" % r.output_item.item_name)
					continue
				if int(ing.item.get_meta(&"id", 0)) <= 0:
					fails.append("ingredient %s has no registry id" % ing.item.item_name)
			print("  ", r.output_item.item_name, " x", r.output_amount,
				" lv", r.required_level, " xp", r.xp_reward)

	for slug: String in [
		"headless_arrow", "bronze_arrow", "iron_arrow", "steel_arrow",
		"mithril_arrow", "adamant_arrow", "runite_arrow",
	]:
		var id: int = ContentRegistryHub.id_from_slug(&"items", StringName(slug))
		var item: Item = ContentRegistryHub.load_by_id(&"items", id)
		if item == null:
			fails.append("item %s (id %d) did not load" % [slug, id])
			continue
		var extra: String = ""
		if item is AmmoItem:
			var ammo: AmmoItem = item as AmmoItem
			extra = " slot=%s stack=%d mastery=%d" % [
				ammo.slot.key if ammo.slot else "NONE",
				ammo.stack_limit,
				ammo.required_mastery_level,
			]
			if ammo.slot == null or ammo.slot.key != &"ammo":
				fails.append("%s is not in the ammo slot" % slug)
			if ammo.stack_limit != 0:
				fails.append("%s must stack without limit" % slug)
			if ammo.base_modifiers.is_empty():
				fails.append("%s has no stat modifier" % slug)
		print("  item ", slug, " id=", id, extra)

	var trees: Dictionary = {
		"normal_tree": 10, "oak_tree": 20, "willow_tree": 30,
		"maple_tree": 40, "yew_tree": 50,
	}
	for tree_name: String in trees:
		var node_res: MineableNodeResource = load(
			"res://source/common/gameplay/maps/components/mineable_nodes/%s.tres" % tree_name
		)
		if node_res == null:
			fails.append("%s failed to load" % tree_name)
			continue
		if node_res.byproduct_item == null:
			fails.append("%s has no byproduct_item" % tree_name)
		if node_res.byproduct_amount != int(trees[tree_name]):
			fails.append("%s byproduct_amount is %d, expected %d" % [
				tree_name, node_res.byproduct_amount, int(trees[tree_name])
			])
		print("  ", tree_name, " byproduct=", node_res.byproduct_amount,
			" job=", node_res.byproduct_job)

	if fails.is_empty():
		print("VERIFY_PASS fletching")
		quit(0)
	else:
		for f: String in fails:
			print("VERIFY_FAIL ", f)
		quit(1)
