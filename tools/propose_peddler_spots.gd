extends Node
## Prints proposed authored peddler spots for every biome, for a human to review.
##
## This tool does NOT decide where the cart goes — it shortlists squares that
## pass every rule so an author can confirm three per map instead of reading tile
## data by eye. What it prints is a proposal; what ships is the PeddlerSpot
## markers someone put in the scene after LOOKING at
## tools/render_peddler_spots.tscn's pictures.
##
## The rules live in tools/peddler_proposal.gd, shared with the renderer and the
## gate so the three cannot drift apart.
##
## Run: godot --path . --mode=client res://tools/propose_peddler_spots.tscn

const BIOMES_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const PeddlerProposal = preload("res://tools/peddler_proposal.gd")


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	print("biome                  home            cand  got  mobs")
	for file_name: String in ResourceLoader.list_directory(BIOMES_DIR):
		if file_name.ends_with(".tres"):
			await _propose(BIOMES_DIR + file_name)
	get_tree().quit(0)


func _propose(res_path: String) -> void:
	var biome: InstanceResource = ResourceLoader.load(res_path) as InstanceResource
	if biome == null:
		return
	if PeddlerSites.is_excluded(biome.instance_name):
		print("%-22s SKIPPED — excluded from the rotation" % biome.instance_name)
		return
	var packed: PackedScene = load(biome.map_path) as PackedScene
	if packed == null:
		print("%-22s SKIPPED — map_path did not load" % biome.instance_name)
		return
	var node: Node = packed.instantiate()
	add_child(node)
	await get_tree().physics_frame
	await get_tree().physics_frame
	if node is not Map:
		node.queue_free()
		return
	var map: Map = node as Map

	var home: Vector2 = map.get_spawn_position(0)
	var mobs: Array = PeddlerProposal.aggressive_mobs(map)
	var all_mobs: int = map.find_children("*", "HostileNpc", true, false).size()
	var pool: Array[Vector2] = PeddlerProposal.candidates(map)
	var chosen: Array[Vector2] = PeddlerProposal.propose(map)

	print("%-22s (%5d,%5d) %5d   %d   %d of %d aggressive" % [
		biome.instance_name, home.x, home.y, pool.size(), chosen.size(),
		mobs.size(), all_mobs,
	])
	for point: Vector2 in chosen:
		print("    Vector2(%.0f, %.0f)   %4.0fpx from home   nearest aggressive mob %.0fpx" % [
			point.x, point.y, home.distance_to(point),
			PeddlerProposal.nearest_mob(mobs, point),
		])
	if chosen.size() < PeddlerProposal.WANT:
		print("    ONLY %d — needs a hand-placed marker here" % chosen.size())

	map.queue_free()
	await get_tree().process_frame
