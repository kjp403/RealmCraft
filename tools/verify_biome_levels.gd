extends SceneTree
## Gate for the biome sub-levels and the stairs that reach them.
##
## Three things this checks that a collision audit cannot:
##   1. Every hostile is present in BOTH `id_to_node` and `node_to_id` on the
##      container. A hostile missing from those dictionaries loads fine and
##      never replicates to clients — the Hollow golem failure in AGENTS.md.
##   2. Warper round trips actually close. Every stair on a surface map must
##      find its arrival id on the destination, and the destination's exit must
##      find its landing id back on the surface map.
##   3. The three surface maps still carry no hostiles of their own, so the
##      original `verify_stub_biomes.gd` contract is not quietly broken by the
##      stairs we appended.
##
##   godot --headless --path . -s tools/verify_biome_levels.gd

const MAPS := "res://source/common/gameplay/maps/maps/"

const LEVELS: Array[Dictionary] = [
	{
		"path": MAPS + "desert/sunspire_terraces.tscn", "root": "sunspire_terraces",
		"entrance": 40, "exit": 140, "exit_target": 50,
		"parent": MAPS + "desert/desert.tscn", "stair": 150,
		"bosses": [], "min_mobs": 8, "min_npcs": 2,
	},
	{
		"path": MAPS + "desert/sunken_tombs.tscn", "root": "sunken_tombs",
		"entrance": 41, "exit": 141, "exit_target": 51,
		"parent": MAPS + "desert/desert.tscn", "stair": 151,
		"bosses": ["SandKing"], "min_mobs": 15, "min_npcs": 1,
	},
	{
		"path": MAPS + "sewers/gutterworks.tscn", "root": "gutterworks",
		"entrance": 42, "exit": 142, "exit_target": 52,
		"parent": MAPS + "sewers/sewers.tscn", "stair": 152,
		"bosses": [], "min_mobs": 10, "min_npcs": 2,
	},
	{
		"path": MAPS + "sewers/drowned_cistern.tscn", "root": "drowned_cistern",
		"entrance": 43, "exit": 143, "exit_target": 53,
		"parent": MAPS + "sewers/sewers.tscn", "stair": 153,
		"bosses": ["CisternSovereign"], "min_mobs": 14, "min_npcs": 1,
	},
	{
		"path": MAPS + "fire_forge/bellows_gallery.tscn", "root": "bellows_gallery",
		"entrance": 44, "exit": 144, "exit_target": 54,
		"parent": MAPS + "fire_forge/fire_forge.tscn", "stair": 154,
		"bosses": [], "min_mobs": 10, "min_npcs": 2,
	},
	{
		"path": MAPS + "fire_forge/cinder_deeps.tscn", "root": "cinder_deeps",
		"entrance": 45, "exit": 145, "exit_target": 55,
		"parent": MAPS + "fire_forge/fire_forge.tscn", "stair": 155,
		"bosses": ["Cinderborn"], "min_mobs": 14, "min_npcs": 1,
	},
]

const SURFACES: Array[String] = [
	MAPS + "desert/desert.tscn",
	MAPS + "sewers/sewers.tscn",
	MAPS + "fire_forge/fire_forge.tscn",
]

var _failures: int = 0


func _initialize() -> void:
	for path in SURFACES:
		_check_surface_untouched(path)
	for level in LEVELS:
		_check_level(level)
	if _failures == 0:
		print("BIOME_LEVELS_VERIFY_PASS")
		quit(0)
		return
	print("BIOME_LEVELS_VERIFY_FAIL ", _failures)
	quit(1)


func _fail(msg: String) -> void:
	_failures += 1
	print("FAIL ", msg)


## Collect every warper-like node keyed by its `warper_id`.
func _warper_ids(map: Node) -> Dictionary:
	var out: Dictionary = {}
	for child in map.get_children():
		var id_value: Variant = child.get("warper_id")
		if id_value == null:
			continue
		out[int(id_value)] = child
	return out


func _check_surface_untouched(path: String) -> void:
	var map: Node = (load(path) as PackedScene).instantiate()
	var name := path.get_file()
	var container := map.get_node_or_null("ReplicatedPropsContainer")
	if container == null:
		_fail("%s has no ReplicatedPropsContainer" % name)
	elif container.get_child_count() != 0:
		_fail("%s gained hostiles (%d)" % [name, container.get_child_count()])
	else:
		print("OK   ", name, " still clean (no hostiles)")
	map.free()


func _check_level(cfg: Dictionary) -> void:
	var path: String = cfg["path"]
	var name := path.get_file()
	var packed: PackedScene = load(path)
	if packed == null:
		_fail("%s will not load" % name)
		return
	var map: Node = packed.instantiate()

	if map.name != StringName(cfg["root"]):
		_fail("%s root is %s, expected %s" % [name, map.name, cfg["root"]])

	# --- Layers ---
	for layer_name in ["Ground", "Walls", "Props"]:
		var layer := map.get_node_or_null("Tiles/" + layer_name) as TileMapLayer
		if layer == null or layer.get_used_cells().is_empty():
			_fail("%s missing or empty layer %s" % [name, layer_name])

	# --- Replication bookkeeping ---
	var container := map.get_node_or_null("ReplicatedPropsContainer")
	if container == null:
		_fail("%s has no ReplicatedPropsContainer" % name)
		map.free()
		return
	if map.get("replicated_props_container") == null:
		_fail("%s did not resolve replicated_props_container (missing node_paths)" % name)

	var mobs := container.get_child_count()
	if mobs < int(cfg["min_mobs"]):
		_fail("%s has %d hostiles, expected >= %d" % [name, mobs, int(cfg["min_mobs"])])
	if int(container.get("id_to_node").size()) != mobs:
		_fail("%s baked id_to_node has %d entries for %d hostiles" % [
			name, int(container.get("id_to_node").size()), mobs
		])

	# The container re-bakes from live children on `_enter_tree`, and its maps
	# are Node-keyed at runtime rather than NodePath-keyed. Drive that same path
	# here: a hostile that is not a direct child, or that collides on a sync id,
	# is the case that silently never replicates.
	container._bake_static_map()
	var seen_ids: Dictionary = {}
	for child in container.get_children():
		var sync_id: int = container.child_id_of_node(child)
		if sync_id < 0:
			_fail("%s hostile %s resolves to no sync id (would never replicate)" % [name, child.name])
			continue
		if seen_ids.has(sync_id):
			_fail("%s hostiles %s and %s share sync id %d" % [
				name, seen_ids[sync_id], child.name, sync_id
			])
		seen_ids[sync_id] = child.name
		if container._resolve_child(sync_id) != child:
			_fail("%s hostile %s does not resolve back from id %d" % [name, child.name, sync_id])
		if child.get("enemy_data") == null:
			_fail("%s hostile %s has no enemy_data" % [name, child.name])

	# --- Bosses ---
	for boss_name: String in cfg["bosses"]:
		var boss := container.get_node_or_null(boss_name)
		if boss == null:
			_fail("%s missing boss %s" % [name, boss_name])
			continue
		var data: Resource = boss.get("enemy_data")
		if data == null or not bool(data.get("is_boss")):
			_fail("%s boss %s is not flagged is_boss" % [name, boss_name])

	# --- Friendly NPCs ---
	var npc_root := map.get_node_or_null("NPCs")
	var npc_count: int = 0 if npc_root == null else npc_root.get_child_count()
	if npc_count < int(cfg["min_npcs"]):
		_fail("%s has %d NPCs, expected >= %d" % [name, npc_count, int(cfg["min_npcs"])])
	if npc_root != null:
		for npc in npc_root.get_children():
			if npc.get("npc_resource") == null:
				_fail("%s NPC %s has no npc_resource" % [name, npc.name])

	# --- Warper round trip ---
	var ids := _warper_ids(map)
	if not ids.has(int(cfg["entrance"])):
		_fail("%s has no arrival warper %d" % [name, int(cfg["entrance"])])
	if not ids.has(int(cfg["exit"])):
		_fail("%s has no exit portal %d" % [name, int(cfg["exit"])])
	else:
		var exit_node: Node = ids[int(cfg["exit"])]
		if int(exit_node.get("target_id")) != int(cfg["exit_target"]):
			_fail("%s exit targets %d, expected %d" % [
				name, int(exit_node.get("target_id")), int(cfg["exit_target"])
			])

	var parent_map: Node = (load(cfg["parent"]) as PackedScene).instantiate()
	var parent_ids := _warper_ids(parent_map)
	var parent_name: String = String(cfg["parent"]).get_file()
	if not parent_ids.has(int(cfg["stair"])):
		_fail("%s has no stair portal %d to %s" % [parent_name, int(cfg["stair"]), name])
	else:
		var stair: Node = parent_ids[int(cfg["stair"])]
		if int(stair.get("target_id")) != int(cfg["entrance"]):
			_fail("%s stair %d targets %d, but %s arrives on %d" % [
				parent_name, int(cfg["stair"]), int(stair.get("target_id")),
				name, int(cfg["entrance"])
			])
	# The return leg has to land somewhere real on the surface map.
	if not parent_ids.has(int(cfg["exit_target"])):
		_fail("%s has no landing warper %d for the return from %s" % [
			parent_name, int(cfg["exit_target"]), name
		])
	parent_map.free()

	print(
		"OK   ", name,
		" mobs=", mobs, " npcs=", npc_count,
		" in=", int(cfg["entrance"]), " out=", int(cfg["exit"]),
		" <-> ", parent_name, " stair=", int(cfg["stair"])
	)
	map.free()
