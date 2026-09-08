@tool
extends SceneTree
## Gate on where uncut gems come from: every mining vein must carry a gem
## table, every entry must resolve, and the cumulative tier rule must hold —
## a vein may only offer gems at or below its own tier.
##
##   godot --headless --path . -s tools/verify_gem_sources.gd

const NODES: String = "res://source/common/gameplay/maps/components/mineable_nodes"
const GEMS: String = "res://source/common/gameplay/items/materials/gems"

## Vein tier -> the highest gem tier it may roll. Index into GEM_ORDER.
const GEM_ORDER: Array[StringName] = [
	&"uncut_sapphire", &"uncut_emerald", &"uncut_ruby", &"uncut_diamond",
]
const VEIN_CAP: Dictionary = {
	&"copper_vein": 0, &"tin_vein": 0,
	&"iron_vein": 1, &"coal_vein": 1,
	&"silver_vein": 2, &"gold_vein": 2,
	&"mithril_vein": 3, &"adamant_vein": 3, &"runite_vein": 3,
	&"dragon_vein": 3, &"obsidian_vein": 3, &"celestial_vein": 3,
	&"astralite_vein": 3,
}


func _init() -> void:
	var bad: int = 0
	var wired: int = 0

	for slug: StringName in [&"uncut_sapphire", &"uncut_emerald", &"uncut_ruby",
			&"uncut_diamond", &"sapphire", &"emerald", &"ruby", &"diamond",
			&"rough_geode"]:
		var item: Item = ResourceLoader.load("%s/%s.tres" % [GEMS, slug]) as Item
		if item == null:
			printerr("ITEM MISSING  ", slug); bad += 1; continue
		if int(item.get_meta(&"id", 0)) <= 0:
			printerr("ITEM UNINDEXED ", slug, " — run update_items_index.gd"); bad += 1
		if item.item_icon == null:
			printerr("ITEM NO ICON  ", slug); bad += 1

	for vein: StringName in VEIN_CAP:
		var res: MineableNodeResource = ResourceLoader.load(
			"%s/%s.tres" % [NODES, vein]) as MineableNodeResource
		if res == null:
			printerr("VEIN MISSING  ", vein); bad += 1; continue
		if res.secondary_pool.is_empty():
			printerr("VEIN NO POOL  ", vein); bad += 1; continue
		if res.secondary_chance <= 0.0:
			printerr("VEIN 0 CHANCE ", vein); bad += 1
		wired += 1
		var cap: int = int(VEIN_CAP[vein])
		var total: float = 0.0
		for drop: LootDrop in res.secondary_pool:
			if drop == null or drop.item == null:
				printerr("VEIN BAD DROP ", vein); bad += 1; continue
			total += drop.chance
			var s: StringName = StringName(drop.item.get_meta(&"slug", &""))
			var at: int = GEM_ORDER.find(s)
			if at == -1:
				continue          # the geode is not on the gem ladder
			if at > cap:
				printerr("VEIN OVER TIER ", vein, " offers ", s,
					" (cap ", GEM_ORDER[cap], ")")
				bad += 1
		if total <= 0.0:
			printerr("VEIN 0 WEIGHT ", vein); bad += 1

	# The loop has to CLOSE: a gem source with no cutting recipe just piles up
	# a material nothing consumes, which is the failure mode of adding drops
	# before the content that spends them.
	var bench: CraftingStationResource = ResourceLoader.load(
		"res://source/common/gameplay/crafting/resources/workbench.tres"
	) as CraftingStationResource
	var cuts: int = 0
	if bench == null:
		printerr("WORKBENCH MISSING"); bad += 1
	else:
		for recipe: CraftingRecipe in bench.recipes:
			if recipe == null or recipe.output_item == null:
				continue
			var out_slug: StringName = StringName(
				recipe.output_item.get_meta(&"slug", &""))
			if out_slug in [&"sapphire", &"emerald", &"ruby", &"diamond"]:
				cuts += 1
				if recipe.profession_for(bench) != &"outfitting":
					printerr("CUT PAYS WRONG SKILL ", out_slug); bad += 1
				if recipe.xp_reward <= 0:
					printerr("CUT NO XP ", out_slug); bad += 1
	if cuts != 4:
		printerr("CUT RECIPES: expected 4, found ", cuts); bad += 1

	print("veins wired: %d   cut recipes: %d   problems: %d" % [wired, cuts, bad])
	quit(1 if bad else 0)
