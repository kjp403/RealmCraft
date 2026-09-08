extends Node
## Writes the proposed spots to a JSON file for the scene patcher to apply.
##
## Split from the patching itself on purpose: only Godot can instantiate a map
## and run the geometry, and only a text edit can add nodes to a .tscn without
## a headless ResourceSaver stripping every uid in the file on the way out.
##
## Emits { "<scene .tscn path>": [[x, y], ...] } — the scene path comes off the
## loaded PackedScene, because several biomes reference their map by uid:// and
## a uid is not something a text patcher can open.
##
## Run: godot --path . --mode=client res://tools/emit_peddler_spots.tscn

const BIOMES_DIR: String = "res://source/common/gameplay/maps/instance/instance_collection/biomes/"
const OUT_PATH: String = "res://previews/peddler/spots.json"
const PeddlerProposal = preload("res://tools/peddler_proposal.gd")


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var out: Dictionary = {}
	for file_name: String in ResourceLoader.list_directory(BIOMES_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var biome: InstanceResource = ResourceLoader.load(BIOMES_DIR + file_name) as InstanceResource
		if biome == null or PeddlerSites.is_excluded(biome.instance_name):
			continue
		var packed: PackedScene = load(biome.map_path) as PackedScene
		if packed == null:
			continue
		var node: Node = packed.instantiate()
		add_child(node)
		await get_tree().physics_frame
		await get_tree().physics_frame
		if node is Map:
			var map: Map = node as Map
			# A map root with a transform of its own would make these global
			# coordinates wrong as node positions, which are LOCAL to the parent.
			if not map.transform.is_equal_approx(Transform2D.IDENTITY):
				push_error("%s: map root is transformed; spots would land wrong." % biome.instance_name)
			var rows: Array = []
			for point: Vector2 in PeddlerProposal.propose(map):
				rows.append([point.x, point.y])
			out[packed.resource_path] = rows
			print("%-22s %d spot(s)  ->  %s" % [biome.instance_name, rows.size(), packed.resource_path])
		node.queue_free()
		await get_tree().process_frame

	var file: FileAccess = FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "  "))
	file.close()
	print("WROTE %s" % OUT_PATH)
	get_tree().quit(0)
