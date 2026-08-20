extends Node
## Gate for the Deep Shoals fishing content: the map instantiates, every new
## fish resolves through the item registry, each hole points at its fish with
## the right level gate, the cooking recipes exist, and the Beach Angler's warp
## is gated on Fishing 60.
##   godot --path . --mode=client res://tools/check_deep_shoals.tscn

const MAP: String = "res://source/common/gameplay/maps/maps/woodland/deep_shoals.tscn"
const INSTANCE: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/deep_shoals.tres"
const ANGLER: String = "res://source/common/gameplay/characters/npc/npcs/woodland/beach_angler.tres"
const COOKING: String = "res://source/common/gameplay/crafting/resources/cooking_station.tres"
const TIERS: Dictionary = {"halibut": 60, "stingray": 70, "wolffish": 80, "blue_lobster": 90}
## Mirrors HarvestController.GATHER_RANGE.
const GATHER_RANGE: float = 48.0

var _failed: bool = false


func _ready() -> void:
	call_deferred(&"_go")


func _fail(msg: String) -> void:
	push_error(msg)
	_failed = true


func _go() -> void:
	# Items resolve by slug through the registry, raw and cooked.
	for slug: String in TIERS:
		for key: String in [slug, "cooked_" + slug]:
			var id: int = ContentRegistryHub.id_from_slug(&"items", StringName(key))
			if id <= 0:
				_fail("item %s is not in the items index" % key)
				continue
			var item: Item = ContentRegistryHub.load_by_id(&"items", id) as Item
			if item == null or item.item_icon == null:
				_fail("item %s loaded without an icon" % key)
			else:
				print("item %-22s id %d  %s" % [key, id, item.item_name])

	# Holes: right fish, right level, right tool.
	for slug: String in TIERS:
		var path: String = "res://source/common/gameplay/maps/components/mineable_nodes/fishing_hole_%s.tres" % slug
		var hole: Resource = load(path)
		if hole == null:
			_fail("missing hole %s" % path)
			continue
		if int(hole.required_level) != int(TIERS[slug]):
			_fail("%s hole requires level %d, expected %d" % [slug, hole.required_level, TIERS[slug]])
		if hole.ore == null or String(hole.ore.get_meta(&"slug", &"")) != slug:
			_fail("%s hole does not yield %s" % [slug, slug])
		if hole.required_tool != &"fishing_rod":
			_fail("%s hole is not rod-gated" % slug)
		print("hole  %-14s level %2d  xp %d" % [slug, hole.required_level, hole.job_xp.get(&"fishing", 0)])

	# Cooking: one recipe per new fish, gated at the same level.
	var station: Resource = load(COOKING)
	var cooked: Dictionary = {}
	for recipe: Resource in station.recipes:
		if recipe == null or recipe.output_item == null:
			continue
		cooked[String(recipe.output_item.get_meta(&"slug", &""))] = recipe
	for slug: String in TIERS:
		var recipe: Resource = cooked.get("cooked_" + slug)
		if recipe == null:
			_fail("no cooking recipe for cooked_%s" % slug)
			continue
		print("cook  %-14s level %2d  xp %d" % [slug, recipe.required_level, recipe.xp_reward])

	# The map itself, and the holes actually placed in it.
	var packed: PackedScene = load(MAP) as PackedScene
	if packed == null:
		_fail("Deep Shoals map failed to load")
	else:
		var root: Node = packed.instantiate()
		var nodes: Node = root.get_node_or_null("MineableNodes")
		var placed: int = nodes.get_child_count() if nodes != null else 0
		print("map placed holes: ", placed)
		# Several holes per tier, so a player works along the coves instead of
		# camping one spot. Every tier must still be represented.
		if placed < TIERS.size():
			_fail("expected at least %d holes in the map, found %d" % [TIERS.size(), placed])
		var tiers_present: Dictionary = {}
		for hole: Node in nodes.get_children():
			var data: Resource = hole.get("data")
			if data != null and data.ore != null:
				tiers_present[String(data.ore.get_meta(&"slug", &""))] = true
		for slug: String in TIERS:
			if not tiers_present.has(slug):
				_fail("no %s hole placed in the map" % slug)
		print("tiers present: ", tiers_present.keys())
		# Reachability: a hole further from the walkable sand than
		# HarvestController.GATHER_RANGE cannot be fished at all — the player
		# cannot swim out to it. Measured against the shoreline the collider
		# builds, which is where the sand actually ends.
		var shore_node: Node = root.get_node_or_null("Shore")
		var line: PackedVector2Array = shore_node.get("shoreline") if shore_node != null else PackedVector2Array()
		if line.is_empty():
			_fail("map has no shoreline data to measure reach against")
		else:
			for hole: Node2D in nodes.get_children():
				var best: float = INF
				for pt: Vector2 in line:
					best = minf(best, hole.position.distance_to(pt))
				print("  %-18s %.0f px from shore" % [hole.name, best])
				if best > GATHER_RANGE:
					_fail("%s is %.0f px out — beyond the %d px gather range" % [
						hole.name, best, GATHER_RANGE
					])
		if root.get_node_or_null("RespawnPoint") == null:
			_fail("map has no RespawnPoint warper — arrivals would land at the origin")
		root.free()

	if load(INSTANCE) == null:
		_fail("deep_shoals instance resource failed to load")

	# The gate itself.
	var angler: Resource = load(ANGLER)
	var gated: bool = false
	for interaction: Resource in angler.interactions:
		if interaction is WarpInteraction:
			var warp: WarpInteraction = interaction as WarpInteraction
			print("angler warp -> %s, needs %s %d" % [
				warp.destination_label, warp.required_skill, warp.required_skill_level
			])
			if warp.required_skill == &"fishing" and warp.required_skill_level == 60:
				gated = true
	if not gated:
		_fail("Beach Angler has no Fishing 60 warp to the Deep Shoals")

	print("RESULT ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
