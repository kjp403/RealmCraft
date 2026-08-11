extends SceneTree
## Append stair portals from Desert / Sewers / Fire Forge to their sub-levels.
##
## The three surface maps are finished art and this tool treats them that way:
## it inserts `ext_resource` lines and appends `[node ...]` blocks as text, and
## never touches a `tile_map_data` line. Re-running is a no-op once the nodes
## are present.
##
## Stairs sit deliberately FAR from the hub portal. Parking them next to the
## arrival plaza let players drop straight through and skip the surface zone
## entirely, so placement is by flood-fill distance: the tool loads each map,
## derives the blocked set from tile collision polygons exactly like
## `audit_biome_collision.gd` does, BFS-es out from the existing Entrance, and
## puts each stair at one of the most distant reachable cells — with the two
## stairs on a map pushed apart from each other as well.
##
## Re-running repositions: any stair nodes this tool previously wrote are
## stripped from the text before the new ones are appended, so the surface maps
## never accumulate duplicates and the tile data is still never touched.
##
##   godot --headless --path . -s tools/add_biome_stairs.gd

const INST := "res://source/common/gameplay/maps/instance/instance_collection/biomes/"

## One entry per surface map. `up` and `down` each describe a sub-level exit:
## the portal the player steps into, and the landing they return onto.
const STAIRS: Array[Dictionary] = [
	{
		"path": "res://source/common/gameplay/maps/maps/desert/desert.tscn",
		"root": "desert",
		"exits": [
			{
				"name": "Terrace", "instance": "sunspire_terraces", "label": "Sunspire Terraces",
				"color": "Color(0.92, 0.78, 0.4, 1)", "portal_id": 150, "landing_id": 50,
				"target_id": 40,
			},
			{
				"name": "Tomb", "instance": "sunken_tombs", "label": "The Sunken Tombs",
				"color": "Color(0.52, 0.42, 0.24, 1)", "portal_id": 151, "landing_id": 51,
				"target_id": 41,
			},
		],
	},
	{
		"path": "res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
		"root": "sewers",
		"exits": [
			{
				"name": "Gutter", "instance": "gutterworks", "label": "The Gutterworks",
				"color": "Color(0.45, 0.7, 0.5, 1)", "portal_id": 152, "landing_id": 52,
				"target_id": 42,
			},
			{
				"name": "Cistern", "instance": "drowned_cistern", "label": "The Drowned Cistern",
				"color": "Color(0.2, 0.5, 0.55, 1)", "portal_id": 153, "landing_id": 53,
				"target_id": 43,
			},
		],
	},
	{
		"path": "res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
		"root": "fire_forge",
		"exits": [
			{
				"name": "Gallery", "instance": "bellows_gallery", "label": "The Bellows Gallery",
				"color": "Color(0.95, 0.55, 0.2, 1)", "portal_id": 154, "landing_id": 54,
				"target_id": 44,
			},
			{
				"name": "Deeps", "instance": "cinder_deeps", "label": "The Cinder Deeps",
				"color": "Color(0.6, 0.14, 0.04, 1)", "portal_id": 155, "landing_id": 55,
				"target_id": 45,
			},
		],
	},
]

## How far above its portal a landing sits, in cells. Matches the gap the surface
## maps already use between their hub Entrance and their hub Portal.
const LANDING_LIFT := 5

## Minimum gap in cells between the two stairs on one surface map, so both
## exits are not tucked into the same far corner.
const MIN_STAIR_SEPARATION := 24


func _initialize() -> void:
	var touched: int = 0
	for entry in STAIRS:
		if _add(entry):
			touched += 1
	print("BIOME_STAIRS_PASS touched=", touched)
	quit(0)


func _add(entry: Dictionary) -> bool:
	var path: String = entry["path"]
	var text: String = FileAccess.get_file_as_string(path)
	assert(text != "", "cannot read %s" % path)

	var exits: Array = entry["exits"]
	# Strip anything a previous run of this tool wrote, so re-running moves the
	# stairs instead of duplicating them.
	text = _strip_previous(text, exits)

	# Distance-ranked reachable cells, computed BEFORE the new nodes exist.
	var ranked := _ranked_by_distance(path)
	assert(not ranked.is_empty(), "no reachable cells in %s" % path)
	var reachable: Dictionary = {}
	for cell: Vector2i in ranked:
		reachable[cell] = true

	# Reserve the tiles the map already uses so a stair never lands on the hub
	# portal or the respawn point.
	var used: Dictionary = _existing_node_cells(path)

	var header_add := ""
	var body_add := ""
	var claimed: Array[Vector2i] = []
	for e: Dictionary in exits:
		var inst_path: String = INST + String(e["instance"]) + ".tres"
		var res_id := "stair_%s" % String(e["instance"])
		header_add += "[ext_resource type=\"Resource\" path=\"%s\" id=\"%s\"]\n" % [inst_path, res_id]

		var portal_cell := _far_cell(ranked, used, claimed)
		claimed.append(portal_cell)
		_reserve(used, portal_cell)
		var landing_cell := _free_near(reachable, used, portal_cell - Vector2i(0, LANDING_LIFT))
		_reserve(used, landing_cell)

		body_add += "\n[node name=\"%sLanding\" parent=\".\" instance=ExtResource(\"5_warper\")]\n" % e["name"]
		body_add += "position = %s\n" % _vec(landing_cell)
		body_add += "warper_id = %d\n" % int(e["landing_id"])

		body_add += "\n[node name=\"%sStair\" parent=\".\" instance=ExtResource(\"6_portal\")]\n" % e["name"]
		body_add += "position = %s\n" % _vec(portal_cell)
		body_add += "portal_color = %s\n" % e["color"]
		body_add += "destination_label = \"%s\"\n" % e["label"]
		body_add += "target_instance = ExtResource(\"%s\")\n" % res_id
		body_add += "warper_id = %d\n" % int(e["portal_id"])
		body_add += "target_id = %d\n" % int(e["target_id"])
		print("  ", path.get_file(), " ", e["name"], " portal=", portal_cell, " landing=", landing_cell)

	# Insert the new ext_resources immediately before the root node header. That
	# marker is a short, unique line, so the edit cannot disturb tile data.
	# (`_strip_previous` already removed any earlier copy of both.)
	var marker := "\n[node name=\"%s\" type=\"Node2D\"" % entry["root"]
	var at: int = text.find(marker)
	assert(at >= 0, "root node header not found in %s" % path)
	var out := text.substr(0, at) + "\n" + header_add + text.substr(at + 1)
	if not out.ends_with("\n"):
		out += "\n"
	out += body_add

	var f := FileAccess.open(path, FileAccess.WRITE)
	assert(f != null, "cannot write %s" % path)
	f.store_string(out)
	f.close()
	return true


func _vec(cell: Vector2i) -> String:
	return "Vector2(%s, %s)" % [str(float(cell.x * 16 + 8)), str(float(cell.y * 16 + 8))]


func _reserve(used: Dictionary, cell: Vector2i) -> void:
	for oy in range(-2, 3):
		for ox in range(-2, 3):
			used[cell + Vector2i(ox, oy)] = true


## Remove the ext_resource lines and node blocks a previous run wrote. Matching
## is on this tool's own generated ids and node names, so nothing hand-authored
## in these scenes can be caught by it.
func _strip_previous(text: String, exits: Array) -> String:
	var drop_ids: Array[String] = []
	var drop_nodes: Array[String] = []
	for e: Dictionary in exits:
		drop_ids.append("id=\"stair_%s\"" % String(e["instance"]))
		drop_nodes.append("[node name=\"%sLanding\"" % String(e["name"]))
		drop_nodes.append("[node name=\"%sStair\"" % String(e["name"]))

	var out: Array[String] = []
	var skipping := false
	for line in text.split("\n"):
		if line.begins_with("[ext_resource"):
			var drop := false
			for id in drop_ids:
				if line.contains(id):
					drop = true
					break
			if drop:
				continue
		if line.begins_with("[node "):
			skipping = false
			for marker in drop_nodes:
				if line.begins_with(marker):
					skipping = true
					break
			if skipping:
				# Also swallow the blank line that preceded this block.
				while not out.is_empty() and out[out.size() - 1].strip_edges().is_empty():
					out.remove_at(out.size() - 1)
				continue
		if skipping:
			continue
		out.append(line)
	return "\n".join(out)


## Reachable cells ordered farthest-first by step count from the Entrance.
func _ranked_by_distance(path: String) -> Array[Vector2i]:
	var dist := _reachable_distances(path)
	var cells: Array[Vector2i] = []
	for cell: Vector2i in dist.keys():
		cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return int(dist[a]) > int(dist[b])
	)
	return cells


## The most distant unused cell that is also well clear of stairs already
## placed on this map, so the two exits do not end up in the same corner.
func _far_cell(ranked: Array[Vector2i], used: Dictionary, claimed: Array[Vector2i]) -> Vector2i:
	var min_gap_sq: int = MIN_STAIR_SEPARATION * MIN_STAIR_SEPARATION
	var fallback := Vector2i(-1, -1)
	for cell: Vector2i in ranked:
		if used.has(cell):
			continue
		if fallback == Vector2i(-1, -1):
			fallback = cell
		var ok := true
		for other: Vector2i in claimed:
			if (cell - other).length_squared() < min_gap_sq:
				ok = false
				break
		if ok:
			return cell
	return fallback


func _free_near(reachable: Dictionary, used: Dictionary, wanted: Vector2i) -> Vector2i:
	var best := wanted
	var best_d: int = 1 << 30
	for cell: Vector2i in reachable.keys():
		if used.has(cell):
			continue
		var d: int = (cell - wanted).length_squared()
		if d < best_d:
			best_d = d
			best = cell
	return best


func _existing_node_cells(path: String) -> Dictionary:
	var map: Node = (load(path) as PackedScene).instantiate()
	var out: Dictionary = {}
	for child in map.get_children():
		if child is not Node2D:
			continue
		var n := child as Node2D
		var cell := Vector2i(int(floor(n.position.x / 16.0)), int(floor(n.position.y / 16.0)))
		for oy in range(-2, 3):
			for ox in range(-2, 3):
				out[cell + Vector2i(ox, oy)] = true
	map.free()
	return out


## Same derivation the collision audit uses: blocked comes from the tile data,
## not from a hand-kept list, so a stair can never be placed inside rock.
## Returns cell -> step count from the Entrance, which is what ranks placement.
func _reachable_distances(path: String) -> Dictionary:
	var map: Node = (load(path) as PackedScene).instantiate()
	var blocked: Dictionary = {}
	var used: Dictionary = {}
	var tiles: Node = map.get_node_or_null("Tiles")
	if tiles != null:
		for child in tiles.get_children():
			if child is not TileMapLayer:
				continue
			var layer := child as TileMapLayer
			var ts: TileSet = layer.tile_set
			for cell: Vector2i in layer.get_used_cells():
				used[cell] = true
				var src := ts.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
				if src == null:
					continue
				var coords := layer.get_cell_atlas_coords(cell)
				if not src.has_tile(coords):
					continue
				var td := src.get_tile_data(coords, layer.get_cell_alternative_tile(cell))
				if td != null and td.get_collision_polygons_count(0) > 0:
					blocked[cell] = true

	var entrance := map.get_node("Entrance") as Node2D
	var start := Vector2i(int(floor(entrance.position.x / 16.0)), int(floor(entrance.position.y / 16.0)))
	var dist: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	dist[start] = 0
	var qi: int = 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = cur + d
			if dist.has(n) or blocked.has(n) or not used.has(n):
				continue
			dist[n] = int(dist[cur]) + 1
			queue.append(n)
	map.free()
	return dist
