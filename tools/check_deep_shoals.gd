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


## Waterline height at a column, from the collider polygon.
func _shore_y_at(line: PackedVector2Array, x: float) -> float:
	var best_dx: float = INF
	var y: float = 0.0
	for pt: Vector2 in line:
		var dx: float = absf(pt.x - x)
		if dx < best_dx:
			best_dx = dx
			y = pt.y
	return y


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

	# The map itself, and the holes actually placed in it. Instantiated ONCE and
	# freed at the end — a second instantiate for the station check deadlocked.
	var root: Node = null
	var packed: PackedScene = load(MAP) as PackedScene
	if packed == null:
		_fail("Deep Shoals map failed to load")
	else:
		root = packed.instantiate()
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
				# Distance alone is not enough: the sand within reach must also
				# be FREE. Market stalls and crates parked on the waterline had
				# every hole in range and none of them fishable.
				var stand: bool = false
				var footprints: Array = shore_node.get("solid_footprints")
				for angle: int in range(0, 360, 15):
					for reach: int in [20, 30, 40, 46]:
						var spot: Vector2 = hole.position + Vector2(
							cos(deg_to_rad(angle)), sin(deg_to_rad(angle))
						) * float(reach)
						# Must be on sand (above the waterline at that column).
						var shore_y: float = _shore_y_at(line, spot.x)
						if spot.y > shore_y - 4.0:
							continue
						var free: bool = true
						for rect: Rect2 in footprints:
							if rect.has_point(spot):
								free = false
								break
						if free:
							stand = true
							break
					if stand:
						break
				print("  %-18s %.0f px from shore, standing spot = %s" % [
					hole.name, best, stand
				])
				if best > GATHER_RANGE:
					_fail("%s is %.0f px out — beyond the %d px gather range" % [
						hole.name, best, GATHER_RANGE
					])
				if not stand:
					_fail("%s has no free sand to fish from — something is parked on it" % hole.name)
		if root.get_node_or_null("RespawnPoint") == null:
			_fail("map has no RespawnPoint warper — arrivals would land at the origin")

	# Reachability of the cooking station: it must not sit inside a solid
	# footprint, and there must be clear sand next to it to stand on. The Shoals
	# cooker was buried inside the shipwreck's collider, visible but unusable.
	var world: Node = root
	if world != null:
		var cooker: Node2D = world.get_node_or_null("CookingStation") as Node2D
		var shore_node: Node = world.get_node_or_null("Shore")
		if cooker == null:
			_fail("map has no CookingStation")
		elif shore_node != null:
			var blocked: bool = false
			var approach: bool = false
			# The station has a footprint of its own; standing in it is expected.
			var own := Rect2(cooker.position - Vector2(32, 20), Vector2(64, 34))
			for rect: Rect2 in shore_node.get("solid_footprints"):
				if rect != own and rect.has_point(cooker.position):
					blocked = true
			# Somewhere within arm's reach that no footprint covers.
			for angle: int in range(0, 360, 30):
				var probe: Vector2 = cooker.position + Vector2(
					cos(deg_to_rad(angle)), sin(deg_to_rad(angle))
				) * 40.0
				var free: bool = true
				for rect: Rect2 in shore_node.get("solid_footprints"):
					if rect != own and rect.has_point(probe):
						free = false
						break
				if free:
					approach = true
					break
			print("cooking station at %s: buried = %s, has approach = %s" % [
				cooker.position, blocked, approach
			])
			if blocked:
				_fail("the cooking station is inside a solid footprint")
			if not approach:
				_fail("the cooking station has no clear side to walk up to")

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
	if root != null:
		root.free()

	print("RESULT ", "FAIL" if _failed else "PASS")
	get_tree().quit(1 if _failed else 0)
