extends Node
## Gate for the high-tier woodcutting content: the four exotic trees, their
## logs and unstrung bows, the fletching recipes, and Starfall Grove itself.
##
## Runs as a SCENE, not as `-s`: a `-s` tool has no autoloads, so
## mineable_node.gd fails to compile against ClientState and every gather node
## in the grove instantiates with a null script — which reads exactly like the
## map being broken. See tools/audit_woodland_east.tscn for the same pattern.
##
##   godot --headless --path . tools/check_exotic_trees.tscn

const STYLES: Array[StringName] = [&"drift_up", &"sparkle", &"spark_side", &"starburst"]
const NODE_DIR := "res://source/common/gameplay/maps/components/mineable_nodes/"
const WOOD := "res://source/common/gameplay/items/materials/wood/"
const GROVE := "res://source/common/gameplay/maps/maps/starfall_grove/starfall_grove.tscn"

const TIERS: Array[Array] = [
	# node slug, log slug, unstrung bow slug, expected level
	["wispwood_tree", "wispwood_log", "wispwood_bow_u", 60],
	["nebula_palm_tree", "nebula_palm_log", "nebula_palm_bow_u", 70],
	["glimmer_birch_tree", "glimmer_birch_log", "glimmer_birch_bow_u", 80],
	["supernova_rosewood_tree", "rosewood_log", "rosewood_bow_u", 85],
]

var _fails: int = 0


func _ready() -> void:
	_go()


func _fail(msg: String) -> void:
	printerr("FAIL ", msg)
	_fails += 1


func _go() -> void:
	_check_nodes()
	_check_job_ladder()
	_check_index()
	_check_recipes()
	_check_grove()
	print("failures: ", _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _check_nodes() -> void:
	for tier: Array in TIERS:
		var path: String = NODE_DIR + tier[0] + ".tres"
		var data: MineableNodeResource = ResourceLoader.load(path) as MineableNodeResource
		if data == null:
			_fail("load " + path)
			continue
		if data.ore == null or data.texture == null or data.depleted_texture == null:
			_fail("missing ore/texture on " + path)
		if data.required_level != int(tier[3]):
			_fail("%s level %d, expected %d" % [tier[0], data.required_level, tier[3]])
		if data.idle_frames.is_empty():
			_fail("no idle frames on " + path)
		for frame: Texture2D in data.idle_frames:
			if frame == null or frame.get_size() != data.texture.get_size():
				_fail("idle frame size mismatch on " + path)
		if data.chop_fx_style not in STYLES:
			_fail("unknown chop_fx_style '%s' on %s" % [data.chop_fx_style, path])
		# XP per second is the number that decides whether the ladder is a grind
		# or a ramp, so report it rather than the raw grant.
		var xp: int = int(data.job_xp.get(&"woodcutting", 0))
		var rate: float = float(xp) * 1.5 / maxf(0.1, data.player_cooldown_seconds)
		print("%-20s lv%-3d xp %-4d cd %.1fs  %6.1f xp/s  %d frames  fx %s" % [
			data.display_name, data.required_level, xp, data.player_cooldown_seconds,
			rate, data.idle_frames.size() + 1, data.chop_fx_style])


func _check_job_ladder() -> void:
	var job: JobPerks = ResourceLoader.load("res://source/common/gameplay/jobs/woodcutting.tres") as JobPerks
	if job == null or job.source_items.size() != job.source_levels.size():
		_fail("woodcutting source_items/source_levels out of step")
		return
	print("woodcutting ladder: ", job.source_levels)


func _check_index() -> void:
	var index: ContentIndex = ResourceLoader.load("res://source/common/registry/indexes/items_index.tres") as ContentIndex
	var slugs: Dictionary = {}
	for entry: Dictionary in index.entries:
		slugs[String(entry.get(&"slug", &""))] = true
	for tier: Array in TIERS:
		for slug: String in [tier[1], tier[2]]:
			if not slugs.has(slug):
				_fail(slug + " missing from items index")
			if ResourceLoader.load(WOOD + slug + ".tres") == null:
				_fail(slug + ".tres does not load")


func _check_recipes() -> void:
	var bench: CraftingStationResource = ResourceLoader.load(
		"res://source/common/gameplay/crafting/resources/fletching_bench.tres"
	) as CraftingStationResource
	if bench == null:
		_fail("fletching bench does not load")
		return
	var outputs: Dictionary = {}
	for recipe: CraftingRecipe in bench.recipes:
		if recipe == null or recipe.output_item == null:
			_fail("fletching bench has a null recipe/output")
			continue
		outputs[String(recipe.output_item.item_name)] = true
	for tier: Array in TIERS:
		var bow: Item = ResourceLoader.load(WOOD + tier[2] + ".tres") as Item
		if bow == null or not outputs.has(String(bow.item_name)):
			_fail("no fletching recipe outputs " + tier[2])
	print("fletching bench recipes: ", bench.recipes.size())


func _check_grove() -> void:
	var packed: PackedScene = ResourceLoader.load(GROVE) as PackedScene
	if packed == null:
		_fail("Starfall Grove scene does not load")
		return
	var map: Node = packed.instantiate()
	var gather: Node = map.get_node_or_null("GatherNodes")
	if gather == null:
		_fail("grove has no GatherNodes container")
		map.queue_free()
		return
	var per_tier: Dictionary = {}
	for child: Node in gather.get_children():
		var node := child as MineableNode
		if node == null or node.data == null:
			_fail("grove gather node '%s' has no data" % child.name)
			continue
		var slug: String = node.data.display_name
		per_tier[slug] = int(per_tier.get(slug, 0)) + 1
	print("grove stands: ", per_tier)
	if gather.get_child_count() < 20:
		_fail("grove has only %d gather nodes" % gather.get_child_count())
	if map.get_node_or_null("Entrance") == null or map.get_node_or_null("HubPortal") == null:
		_fail("grove is missing its Entrance warper or HubPortal")
	map.queue_free()

	# The zone is only reachable if the hub actually carries the return portal.
	var hub: PackedScene = ResourceLoader.load("res://source/common/gameplay/maps/maps/hub.tscn") as PackedScene
	if hub == null:
		_fail("hub.tscn does not load")
		return
	var hub_map: Node = hub.instantiate()
	if hub_map.get_node_or_null("Warpers/StarfallGrovePortal") == null:
		_fail("hub is missing StarfallGrovePortal")
	hub_map.queue_free()
