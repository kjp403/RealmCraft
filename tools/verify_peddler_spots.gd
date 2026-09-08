extends Node
## Gate: every biome in the peddler rotation carries valid authored spots.
##
## This is the check that replaced a runtime probe. Placement used to be
## re-decided every 30-minute cycle in nineteen maps, and the only way to find a
## bad square was a player standing in front of a cart in a wall. Now the spots
## are authored once and this fails the build if any of them is wrong.
##
## Per biome, and every one of these has been a real bug:
##   * at least MIN_SPOTS markers exist — a map with none silently falls back to
##     the spawn pad forever, which looks like "the peddler is boring", not like
##     a failure;
##   * each marker passes PeddlerSites.is_valid_spot — painted floor (where the
##     map has paint), with the cart's real body clear;
##   * each marker is reachable ON FOOT from the home spawn, not merely clear —
##     a sealed pocket behind a wall run is both;
##   * each marker is clear of every AGGRESSIVE mob, so opening the shop menu is
##     not an invitation to be hit;
##   * markers are distinct, because three names pointing at one square is three
##     ways to get the same cart.
##
## Run: godot --path . --mode=client res://tools/verify_peddler_spots.tscn

const BIOMES_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const PeddlerProposal = preload("res://tools/peddler_proposal.gd")
## Fewer than this and the rotation stops being varied enough to be worth
## authoring at all.
const MIN_SPOTS: int = 3
## Two markers closer than this are the same place twice.
const MIN_SEPARATION: float = 64.0
## The fill has to reach the markers, which sit further out than the old runtime
## band allowed for.
const FILL_BUDGET: float = 2000.0

var _fail: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	for file_name: String in ResourceLoader.list_directory(BIOMES_DIR):
		if file_name.ends_with(".tres"):
			await _check(BIOMES_DIR + file_name)
	print("VERIFY_PASS" if _fail == 0 else "VERIFY_FAIL")
	get_tree().quit(0 if _fail == 0 else 1)


func _check(res_path: String) -> void:
	var biome: InstanceResource = ResourceLoader.load(res_path) as InstanceResource
	if biome == null:
		return
	var name: String = String(biome.instance_name)
	if PeddlerSites.is_excluded(biome.instance_name):
		print("  skip  %-22s excluded from the rotation" % name)
		return
	var packed: PackedScene = load(biome.map_path) as PackedScene
	if packed == null:
		_bad(name, "map_path did not load")
		return
	var node: Node = packed.instantiate()
	add_child(node)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if node is not Map:
		node.queue_free()
		_bad(name, "map root is not a Map")
		return
	var map: Map = node as Map

	var spots: PackedVector2Array = PeddlerSites.authored_spots(map)
	if spots.size() < MIN_SPOTS:
		_bad(name, "has %d PeddlerSpot marker(s), needs %d" % [spots.size(), MIN_SPOTS])
	else:
		var home: Vector2 = map.get_spawn_position(0)
		var walkable: Dictionary = PeddlerSites.walkable_cells(map, home, FILL_BUDGET)
		var mobs: Array = PeddlerProposal.aggressive_mobs(map)
		var ok: bool = true
		for i: int in spots.size():
			var spot: Vector2 = spots[i]
			if not PeddlerSites.is_valid_spot(map, spot):
				ok = false
				_bad(name, "spot %d at %s is not a valid square" % [i + 1, spot])
			elif not _reachable(walkable, spot):
				ok = false
				_bad(name, "spot %d at %s cannot be walked to from the spawn" % [i + 1, spot])
			var gap: float = PeddlerProposal.nearest_mob(mobs, spot)
			if gap < 0.0:
				ok = false
				_bad(name, "spot %d at %s is inside an aggressive mob's range" % [i + 1, spot])
			for j: int in range(i + 1, spots.size()):
				if spot.distance_to(spots[j]) < MIN_SEPARATION:
					ok = false
					_bad(name, "spots %d and %d are the same place" % [i + 1, j + 1])
		if ok:
			print("  ok    %-22s %d spots, all reachable and clear of mobs" % [name, spots.size()])

	map.queue_free()
	await get_tree().process_frame


## The fill is a 16px lattice, so a marker sits inside a cell rather than on one.
## Accept the cell it falls in or any of its neighbours — a marker one pixel over
## a cell boundary is not an unreachable marker.
func _reachable(walkable: Dictionary, spot: Vector2) -> bool:
	var step: float = PeddlerSites.FILL_STEP
	var cell := Vector2i(floori(spot.x / step), floori(spot.y / step))
	for dx: int in [-1, 0, 1]:
		for dy: int in [-1, 0, 1]:
			if walkable.has(cell + Vector2i(dx, dy)):
				return true
	return false


func _bad(biome: String, why: String) -> void:
	_fail += 1
	printerr("  FAIL  %-22s %s" % [biome, why])
