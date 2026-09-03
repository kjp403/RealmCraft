extends Node
## Gate for the six high-tier Farming patches after tools/plant_high_tier_herbs.py.
##
##   godot --headless --path . --mode=client res://tools/verify_high_tier_patches.tscn
##
## Runs as a SCENE, not `-s`: the maps hold hostile NPCs whose script chain
## reaches the `Client` / `ClientState` autoloads, and under `-s` those fail to
## compile and the map instantiates with nothing readable on it.
##
## Checks the three things a text-inserted node can get wrong and the .tscn will
## not complain about:
##   1. the patch resolves to the right MineableNodeResource (a wrong
##      ExtResource id parses fine and silently plants the wrong herb),
##   2. its position is on ground the player can REACH from the Entrance — not
##      inside a wall and not on an island, which a hand-picked coordinate
##      cannot guarantee and which nothing else in the pipeline checks,
##   3. the ore veins already in the Starfall cave survived the insert, because
##      that map's MineableNodes container is shared with its generator's work.

const EXPECT: Array[Dictionary] = [
	{
		"path": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
		"patches": {"ForgeRustSpore": ["rust_spore_cap", 7], "ForgeMagmaRoot": ["magma_root", 7]},
		"keep": {},
	},
	{
		"path": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
		"patches": {
			"SewerNightshade": ["nightshade_bramble", 7],
			"SewerGloomSpore": ["gloom_spore_cap", 7],
		},
		"keep": {},
	},
	{
		"path": "res://source/common/gameplay/maps/maps/desert/desert.tscn",
		"patches": {"DesertSunLotus": ["sun_lit_lotus", 8]},
		"keep": {},
	},
	{
		"path": "res://source/common/gameplay/maps/maps/starfall_mining_cave/starfall_mining_cave.tscn",
		"patches": {"CaveIronSpike": ["iron_spike_thorn", 8]},
		# The veins the cave generator placed, which share the container the
		# patches were inserted into.
		"keep": {"DragonVein": 6, "ObsidianVein": 5, "CelestialVein": 5, "AstraliteVein": 4},
	},
]


func _ready() -> void:
	var fails: Array[String] = []
	for entry: Dictionary in EXPECT:
		fails.append_array(_check(entry))
	if fails.is_empty():
		print("VERIFY_PASS high_tier_patches")
		get_tree().quit(0)
	else:
		for f: String in fails:
			print("VERIFY_FAIL ", f)
		get_tree().quit(1)


func _check(entry: Dictionary) -> Array[String]:
	var fails: Array[String] = []
	var path: String = String(entry["path"])
	var name: String = path.get_file()
	var scene: PackedScene = load(path)
	if scene == null:
		fails.append("%s failed to load" % name)
		return fails
	var map: Node = scene.instantiate()

	var container: Node = map.get_node_or_null("MineableNodes")
	if container == null:
		fails.append("%s has no MineableNodes container" % name)
		map.free()
		return fails

	var reachable: Dictionary = {}
	var blocked: Dictionary = {}
	var tile_size: int = _walkable(map, reachable, blocked)
	if tile_size <= 0:
		fails.append("%s could not derive walkable set" % name)
		map.free()
		return fails

	var counts: Dictionary = {}
	for child: Node in container.get_children():
		var node_name: String = String(child.name)
		for prefix: String in (entry["patches"] as Dictionary):
			if not node_name.begins_with(prefix):
				continue
			counts[prefix] = int(counts.get(prefix, 0)) + 1
			var node2d: Node2D = child as Node2D
			var data: MineableNodeResource = child.get("data") as MineableNodeResource
			var want_slug: String = String((entry["patches"][prefix] as Array)[0])
			if data == null or data.ore == null:
				fails.append("%s %s has no node resource" % [name, node_name])
				continue
			var got_slug: String = String(data.ore.get_meta(&"slug", &""))
			if got_slug != want_slug:
				fails.append("%s %s yields %s, want %s" % [
					name, node_name, got_slug, want_slug
				])
			if data.required_tool != &"sickle":
				fails.append("%s %s is not a sickle patch" % [name, node_name])
			var cell := Vector2i(
				int(floor(node2d.position.x / float(tile_size))),
				int(floor(node2d.position.y / float(tile_size)))
			)
			if blocked.has(cell):
				fails.append("%s %s at %s is inside a wall" % [name, node_name, cell])
			elif not reachable.has(cell):
				fails.append("%s %s at %s is unreachable from the Entrance" % [
					name, node_name, cell
				])

	for prefix: String in (entry["patches"] as Dictionary):
		var want: int = int((entry["patches"][prefix] as Array)[1])
		var got: int = int(counts.get(prefix, 0))
		if got != want:
			fails.append("%s %s count %d != %d" % [name, prefix, got, want])
		else:
			print("  ", name, " ", prefix, " x", got, " on walkable ground")

	# Nothing the map already had may have been displaced by the insert.
	for prefix: String in (entry["keep"] as Dictionary):
		var kept: int = 0
		for child: Node in container.get_children():
			if String(child.name).begins_with(prefix):
				kept += 1
		var want_kept: int = int(entry["keep"][prefix])
		if kept != want_kept:
			fails.append("%s lost %s: %d of %d remain" % [
				name, prefix, kept, want_kept
			])
	map.free()
	return fails


## Fills [param reachable] and [param blocked] and returns the tile size, using
## the same derivation as tools/audit_biome_collision.gd: blocked comes from the
## tiles' real collision polygons, and reachable is flood-filled from the
## Entrance warper.
func _walkable(map: Node, reachable: Dictionary, blocked: Dictionary) -> int:
	var layers: Array[TileMapLayer] = []
	var tiles: Node = map.get_node_or_null("Tiles")
	if tiles != null:
		for child: Node in tiles.get_children():
			if child is TileMapLayer:
				layers.append(child as TileMapLayer)
	if layers.is_empty():
		return 0

	var used: Dictionary = {}
	for layer: TileMapLayer in layers:
		var ts: TileSet = layer.tile_set
		for cell: Vector2i in layer.get_used_cells():
			used[cell] = true
			var src := ts.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
			if src == null:
				continue
			var coords: Vector2i = layer.get_cell_atlas_coords(cell)
			if not src.has_tile(coords):
				continue
			var td: TileData = src.get_tile_data(
				coords, layer.get_cell_alternative_tile(cell)
			)
			if td != null and td.get_collision_polygons_count(0) > 0:
				blocked[cell] = true

	var tile_size: int = layers[0].tile_set.tile_size.x
	var entrance: Node2D = map.get_node_or_null("Entrance") as Node2D
	if entrance == null:
		return 0
	var start := Vector2i(
		int(floor(entrance.position.x / float(tile_size))),
		int(floor(entrance.position.y / float(tile_size)))
	)
	if blocked.has(start) or not used.has(start):
		return 0
	var queue: Array[Vector2i] = [start]
	reachable[start] = true
	var qi: int = 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cur + d
			if reachable.has(n) or blocked.has(n) or not used.has(n):
				continue
			reachable[n] = true
			queue.append(n)
	return tile_size
