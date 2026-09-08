extends RefCounted
## Shared rules for PROPOSING authored peddler spots. Preloaded, not a
## class_name: no tool in this repo adds a global class, and the global class
## cache is stale until an import pass, which is a bad trade for a tool helper.
##
## One definition of "a good spot", used by every tool that has an opinion about
## placement — the proposer that prints coordinates, the renderer that draws
## them, and the gate that checks what shipped. Three copies of these rules would
## drift, and a picture that disagrees with the proposal is worse than no
## picture.
##
## A square qualifies when it is ALL of:
##   * reachable on foot from the home spawn (PeddlerSites.walkable_cells)
##   * valid for a cart (PeddlerSites.is_valid_spot — clear body, painted floor
##     where the map has paint to check)
##   * open on all eight sides, so a player can walk around the cart
##   * outside every AGGRESSIVE mob's detection radius plus HOSTILE_MARGIN

## Clear of the arrival pad, so the cart is somewhere you walk TO rather than
## something you land on top of.
const MIN_RADIUS: float = 120.0
## A spot has to be near somewhere players already go — a warper, an NPC, a
## crafting station. Distance from the home SPAWN is a bad proxy for that: it put
## all three woodland spots in one corner of a 5000px map and left the whole east
## half, where the paths and the goblin camp are, unused. These two bound the gap
## to the nearest point of interest instead: far enough not to crowd it, near
## enough that someone passing finds the cart.
const MIN_POI_GAP: float = 72.0
const MAX_POI_GAP: float = 420.0
## Breathing room beyond an aggressive mob's OWN detection radius. Buying from
## the cart opens a menu, and a mob wandering into you while it is open is the
## interruption this margin exists to prevent.
const HOSTILE_MARGIN: float = 96.0
## Spots to propose per biome.
const WANT: int = 3
## Ideal minimum distance between proposals, so three spots are three PLACES.
## Relaxed toward MIN_SPREAD on a map too small or too hostile to field three.
const SPREAD: float = 420.0
const MIN_SPREAD: float = 100.0
const SPREAD_STEP: float = 40.0
## Node types that count as somewhere players go.
const POI_TYPES: PackedStringArray = ["Warper", "NPC", "CraftingStation"]


## Every square that qualifies, unsorted.
static func candidates(map: Map) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if map == null:
		return out
	var home: Vector2 = map.get_spawn_position(0)
	var mobs: Array = aggressive_mobs(map)
	var pois: PackedVector2Array = points_of_interest(map)
	var walkable: Dictionary = PeddlerSites.walkable_cells(map, home)
	for cell: Vector2i in walkable:
		var point: Vector2 = Vector2(cell) * PeddlerSites.FILL_STEP \
			+ Vector2.ONE * (PeddlerSites.FILL_STEP * 0.5)
		if home.distance_to(point) < MIN_RADIUS:
			continue
		var poi: float = nearest_poi(pois, point)
		if poi < MIN_POI_GAP or poi > MAX_POI_GAP:
			continue
		if not PeddlerSites.is_valid_spot(map, point):
			continue
		if not _has_elbow_room(walkable, cell):
			continue
		if nearest_mob(mobs, point) < 0.0:
			continue
		out.append(point)
	return out


## [constant WANT] spots spread across the map, or fewer when the geometry
## cannot field them. Deterministic.
static func propose(map: Map) -> Array[Vector2]:
	var pool: Array[Vector2] = candidates(map)
	if pool.is_empty():
		return []
	var home: Vector2 = map.get_spawn_position(0)
	var spread: float = SPREAD
	var chosen: Array[Vector2] = _spread_out(pool, home, spread)
	while chosen.size() < WANT and spread > MIN_SPREAD:
		spread = maxf(MIN_SPREAD, spread - SPREAD_STEP)
		chosen = _spread_out(pool, home, spread)
	return chosen


## Every AGGRESSIVE mob as {"at": Vector2, "keep_out": float}.
##
## Aggressive means chase_on_area — a mob that starts a fight because you walked
## near it. A passive mob only fights back when hit, so standing beside one with
## a shop menu open is safe, and excluding them would empty several maps:
## mining_cave is 54 mobs and none of them aggressive, woodland 1 of 65.
##
## keep_out is read off each mob's own enemy_data rather than assumed —
## detection_radius is per-archetype and a caster's reaches further than a slime's.
static func aggressive_mobs(map: Map) -> Array:
	var out: Array = []
	if map == null:
		return out
	for node: Node in map.find_children("*", "HostileNpc", true, false):
		var mob: HostileNpc = node as HostileNpc
		if mob == null or mob.enemy_data == null or not mob.enemy_data.chase_on_area:
			continue
		out.append({
			"at": mob.global_position,
			"keep_out": float(mob.enemy_data.detection_radius) + HOSTILE_MARGIN,
		})
	return out


## Distance to the nearest aggressive mob, -1 when [param point] is inside one's
## keep-out ring, or a large number when the map has no aggressive mobs at all.
static func nearest_mob(mobs: Array, point: Vector2) -> float:
	var nearest: float = 99999.0
	for mob: Dictionary in mobs:
		var away: float = (mob["at"] as Vector2).distance_to(point)
		if away < float(mob["keep_out"]):
			return -1.0
		nearest = minf(nearest, away)
	return nearest


## Every place players go: warpers, NPCs and crafting stations. Not mobs — a camp
## is somewhere players go THROUGH, and the mob rule already keeps the cart off it.
static func points_of_interest(map: Map) -> PackedVector2Array:
	var out := PackedVector2Array()
	if map == null:
		return out
	for type_name: String in POI_TYPES:
		for node: Node in map.find_children("*", type_name, true, false):
			var node_2d: Node2D = node as Node2D
			if node_2d != null:
				out.append(node_2d.global_position)
	return out


## Distance to the nearest point of interest. A map with none leaves the band
## unenforced rather than rejecting every square on it.
static func nearest_poi(pois: PackedVector2Array, point: Vector2) -> float:
	if pois.is_empty():
		return (MIN_POI_GAP + MAX_POI_GAP) * 0.5
	var nearest: float = 99999.0
	for poi: Vector2 in pois:
		nearest = minf(nearest, poi.distance_to(point))
	return nearest


static func _has_elbow_room(walkable: Dictionary, cell: Vector2i) -> bool:
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			if not walkable.has(cell + Vector2i(dx, dy)):
				return false
	return true


## Greedy farthest-point pick: seed with the candidate nearest the home spawn
## (somewhere players already pass), then repeatedly take the one furthest from
## everything chosen so far. Deterministic, and it spreads the spots around the
## map instead of clustering them in one corner.
static func _spread_out(pool: Array[Vector2], home: Vector2, spread: float) -> Array[Vector2]:
	var sorted: Array[Vector2] = pool.duplicate()
	sorted.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return home.distance_to(a) < home.distance_to(b))
	var chosen: Array[Vector2] = [sorted[0]]
	while chosen.size() < WANT:
		var best: Vector2 = Vector2.INF
		var best_gap: float = 0.0
		for point: Vector2 in sorted:
			var gap: float = 99999.0
			for taken: Vector2 in chosen:
				gap = minf(gap, taken.distance_to(point))
			if gap > best_gap:
				best_gap = gap
				best = point
		if best == Vector2.INF or best_gap < spread:
			break
		chosen.append(best)
	return chosen
