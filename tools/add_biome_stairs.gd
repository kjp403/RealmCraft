extends SceneTree
## Append stair portals from Desert / Sewers / Fire Forge to their sub-levels.
##
## The three surface maps are finished art and this tool treats them that way:
## it inserts `ext_resource` lines and appends `[node ...]` blocks as text, and
## never touches a `tile_map_data` line. Re-running is a no-op once the nodes
## are present.
##
## Landing positions are not authored by hand. The tool loads each map, derives
## the blocked set from the tile collision polygons exactly like
## `audit_biome_collision.gd` does, flood-fills from the existing Entrance, and
## snaps every new node onto a cell that is provably reachable.
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
				"target_id": 40, "offset": Vector2i(-8, 2),
			},
			{
				"name": "Tomb", "instance": "sunken_tombs", "label": "The Sunken Tombs",
				"color": "Color(0.52, 0.42, 0.24, 1)", "portal_id": 151, "landing_id": 51,
				"target_id": 41, "offset": Vector2i(8, 2),
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
				"target_id": 42, "offset": Vector2i(-8, 2),
			},
			{
				"name": "Cistern", "instance": "drowned_cistern", "label": "The Drowned Cistern",
				"color": "Color(0.2, 0.5, 0.55, 1)", "portal_id": 153, "landing_id": 53,
				"target_id": 43, "offset": Vector2i(8, 2),
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
				"target_id": 44, "offset": Vector2i(-8, 2),
			},
			{
				"name": "Deeps", "instance": "cinder_deeps", "label": "The Cinder Deeps",
				"color": "Color(0.6, 0.14, 0.04, 1)", "portal_id": 155, "landing_id": 55,
				"target_id": 45, "offset": Vector2i(8, 2),
			},
		],
	},
]

## How far above its portal a landing sits, in cells. Matches the gap the surface
## maps already use between their hub Entrance and their hub Portal.
const LANDING_LIFT := 5


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
	var pending: Array = []
	for e: Dictionary in exits:
		if text.contains("name=\"%sStair\"" % e["name"]):
			print("skip ", path.get_file(), " ", e["name"], " (already wired)")
			continue
		pending.append(e)
	if pending.is_empty():
		return false

	var reachable := _reachable_cells(path)
	assert(not reachable.is_empty(), "no reachable cells in %s" % path)
	var origin := _entrance_cell(path)

	# Reserve the tiles the map already uses so a stair never lands on the hub
	# portal or the respawn point.
	var used: Dictionary = _existing_node_cells(path)

	var header_add := ""
	var body_add := ""
	for e: Dictionary in pending:
		var inst_path: String = INST + String(e["instance"]) + ".tres"
		var res_id := "stair_%s" % String(e["instance"])
		header_add += "[ext_resource type=\"Resource\" path=\"%s\" id=\"%s\"]\n" % [inst_path, res_id]

		var portal_cell := _free_near(reachable, used, origin + e["offset"])
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


func _entrance_cell(path: String) -> Vector2i:
	var map: Node = (load(path) as PackedScene).instantiate()
	var entrance := map.get_node("Entrance") as Node2D
	var cell := Vector2i(int(floor(entrance.position.x / 16.0)), int(floor(entrance.position.y / 16.0)))
	map.free()
	return cell


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
func _reachable_cells(path: String) -> Dictionary:
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
	map.free()
	return seen
