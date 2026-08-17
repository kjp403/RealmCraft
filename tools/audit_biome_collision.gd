extends SceneTree
## Collision gate for the built biome maps.
##
## Instead of asserting on atlas coordinates, this loads each scene, derives the
## blocked set from the tile collision polygons actually present on every layer,
## and flood-fills from the Entrance warper. That is the check that would have
## caught the invisible walls in the sewers: a tile that looks like floor but
## carries a collision polygon shows up here as unreachable space.
##   godot --headless --path . -s tools/audit_biome_collision.gd

const MAPS := [
	{"path": "res://source/common/gameplay/maps/maps/desert/desert.tscn", "min": 1500},
	{"path": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn", "min": 1500},
	{"path": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn", "min": 1500},
	{"path": "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn", "min": 1000},
	# Biome sub-levels (tools/build_biome_levels.gd).
	{"path": "res://source/common/gameplay/maps/maps/desert/sunspire_terraces.tscn", "min": 1200},
	{"path": "res://source/common/gameplay/maps/maps/desert/sunken_tombs.tscn", "min": 1200},
	{"path": "res://source/common/gameplay/maps/maps/sewers/gutterworks.tscn", "min": 1200},
	{"path": "res://source/common/gameplay/maps/maps/sewers/drowned_cistern.tscn", "min": 1200},
	{"path": "res://source/common/gameplay/maps/maps/sewers/ossuary.tscn", "min": 800},
	{"path": "res://source/common/gameplay/maps/maps/fire_forge/bellows_gallery.tscn", "min": 1200},
	{"path": "res://source/common/gameplay/maps/maps/fire_forge/cinder_deeps.tscn", "min": 1200},
]


func _initialize() -> void:
	var failures: int = 0
	for entry in MAPS:
		if not _check(String(entry["path"]), int(entry["min"])):
			failures += 1
	if failures == 0:
		print("BIOME_COLLISION_AUDIT_PASS")
		quit(0)
		return
	print("BIOME_COLLISION_AUDIT_FAIL ", failures)
	quit(1)


func _check(path: String, minimum: int) -> bool:
	var scene: PackedScene = load(path)
	var map: Node = scene.instantiate()
	var name := path.get_file()

	var layers: Array = []
	var tiles: Node = map.get_node_or_null("Tiles")
	if tiles != null:
		for child in tiles.get_children():
			if child is TileMapLayer:
				layers.append(child)

	var blocked: Dictionary = {}
	var used: Dictionary = {}
	for layer: TileMapLayer in layers:
		var ts: TileSet = layer.tile_set
		for cell: Vector2i in layer.get_used_cells():
			used[cell] = true
			var source_id := layer.get_cell_source_id(cell)
			var src := ts.get_source(source_id) as TileSetAtlasSource
			if src == null:
				continue
			var coords := layer.get_cell_atlas_coords(cell)
			if not src.has_tile(coords):
				continue
			var td := src.get_tile_data(coords, layer.get_cell_alternative_tile(cell))
			if td != null and td.get_collision_polygons_count(0) > 0:
				blocked[cell] = true

	var entrance: Node2D = map.get_node_or_null("Entrance")
	if entrance == null:
		print("FAIL ", name, " no Entrance warper")
		map.free()
		return false
	var tile_size: int = layers[0].tile_set.tile_size.x
	var start := Vector2i(
		int(floor(entrance.position.x / float(tile_size))),
		int(floor(entrance.position.y / float(tile_size)))
	)
	if blocked.has(start):
		print("FAIL ", name, " entrance ", start, " is blocked")
		map.free()
		return false

	var seen: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var qi: int = 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cur + d
			if seen.has(n) or blocked.has(n) or not used.has(n):
				continue
			seen[n] = true
			queue.append(n)

	var portal: Node2D = map.get_node_or_null("Portal")
	if portal == null:
		for child in map.get_children():
			if String(child.name).ends_with("Portal"):
				portal = child as Node2D
				break
	var portal_ok := true
	if portal != null:
		var pcell := Vector2i(
			int(floor(portal.position.x / float(tile_size))),
			int(floor(portal.position.y / float(tile_size)))
		)
		portal_ok = seen.has(pcell)
		if not portal_ok:
			print("FAIL ", name, " portal ", pcell, " unreachable from entrance")

	var ok: bool = seen.size() >= minimum and portal_ok
	print(
		("OK   " if ok else "FAIL "), name,
		" reachable=", seen.size(), " blocked=", blocked.size(), " min=", minimum
	)
	map.free()
	return ok
