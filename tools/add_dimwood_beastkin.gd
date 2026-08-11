extends SceneTree
## Add the beastkin packs to DimWood (`forest/forest.tscn`).
##
## DimWood is hand-authored art, not generated, so this tool treats it the way
## `add_biome_stairs.gd` treats the surface maps: it edits the scene as TEXT,
## inserting `ext_resource` lines, rewriting the two replication id maps and
## appending `[node ...]` blocks. It never touches a `tile_map_data` line, and
## re-running strips whatever it wrote last time, so the map cannot accumulate
## duplicates.
##
## Placement is derived, not authored: the blocked set comes from the tile
## collision polygons, a flood fill runs out from `DimWoodEntrance`, and each
## pack is dropped on a reachable cell picked far from the entrance and spread
## apart from the other packs. That is the only way to place mobs into a
## hand-drawn map without eyeballing coordinates that break the moment the art
## moves.
##
## Zones no longer gate on combat level — mobs display theirs and the player
## decides — so the beastkin (36-55) sit in DimWood alongside its level 20-25
## bandits deliberately. The deeper packs are the higher ones.
##
##   godot --headless --path . -s tools/add_dimwood_beastkin.gd

const MAP := "res://source/common/gameplay/maps/maps/forest/forest.tscn"
const HOSTILE := "res://source/common/gameplay/characters/npc/hostile_npc.tscn"
const TYPES := "res://source/common/gameplay/characters/npc/types/"

## `[node_base, type slug, count, rank]`. `rank` orders packs by distance from
## the entrance, so the strongest sit deepest: 0 is nearest, 5 is furthest.
const PACKS: Array = [
	["Werewolf", "trpg/trpg_werewolf", 4, 0],
	["Werebear", "trpg/trpg_werebear", 3, 1],
	["WerewolfStalker", "trpg/trpg_werewolf_stalker", 3, 2],
	["CragYeti", "trpg/trpg_crag_yeti", 3, 3],
	["SnowYeti", "trpg/trpg_snow_yeti", 3, 4],
	["FogGiant", "trpg/trpg_fog_giant", 2, 5],
]

## Cells kept between packs, and between a pack and anything already in the map.
const PACK_GAP := 14
const MEMBER_GAP := 3


func _initialize() -> void:
	var abs_path := ProjectSettings.globalize_path(MAP)
	var text := FileAccess.get_file_as_string(abs_path)
	assert(text != "", "cannot read %s" % MAP)
	text = _strip_previous(text)

	var ranked := _ranked_by_distance()
	assert(not ranked.is_empty(), "no reachable cells in DimWood")
	var used := _occupied_cells()

	# Slice the reachable set into bands by distance so a pack's rank actually
	# means something; picking globally-farthest for everything piles them up.
	var placed: Array = []
	var taken: Dictionary = used.duplicate()
	for pack: Array in PACKS:
		var rank: int = int(pack[3])
		var lo: int = int(float(ranked.size()) * (0.35 + 0.10 * float(rank)))
		var anchor := _first_free(ranked, taken, lo)
		_reserve(taken, anchor, PACK_GAP)
		for i in int(pack[2]):
			var cell := _first_free(ranked, taken, _index_of(ranked, anchor))
			_reserve(taken, cell, MEMBER_GAP)
			placed.append({
				"name": String(pack[0]) if i == 0 else "%s%d" % [pack[0], i + 1],
				"type": TYPES + String(pack[1]) + ".tres",
				"pos": Vector2(cell.x * 16 + 8, cell.y * 16 + 8),
			})
		print("  %-16s rank=%d anchor=%s x%d" % [pack[0], rank, anchor, int(pack[2])])

	text = _insert_ext(text, placed)
	text = _extend_id_maps(text, placed)
	text = _append_nodes(text, placed)

	var f := FileAccess.open(MAP, FileAccess.WRITE)
	assert(f != null, "cannot write %s" % MAP)
	f.store_string(text)
	f.close()
	print("DIMWOOD_BEASTKIN_PASS added=", placed.size())
	quit(0)


func _index_of(ranked: Array, cell: Vector2i) -> int:
	var at := ranked.find(cell)
	return 0 if at < 0 else at


func _first_free(ranked: Array, taken: Dictionary, from_index: int) -> Vector2i:
	for i in range(mini(from_index, ranked.size() - 1), ranked.size()):
		if not taken.has(ranked[i]):
			return ranked[i]
	for i in ranked.size():
		if not taken.has(ranked[i]):
			return ranked[i]
	return ranked[0]


func _reserve(taken: Dictionary, cell: Vector2i, radius: int) -> void:
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			taken[cell + Vector2i(ox, oy)] = true


## Every node this tool wrote before, by name prefix, plus its ext_resources.
func _strip_previous(text: String) -> String:
	var drop_nodes: Array[String] = []
	for pack: Array in PACKS:
		drop_nodes.append("[node name=\"%s\"" % String(pack[0]))
	var out: Array[String] = []
	var skipping := false
	for line in text.split("\n"):
		if line.begins_with("[ext_resource") and line.contains("id=\"bk_"):
			continue
		if line.begins_with("[node "):
			skipping = false
			for marker in drop_nodes:
				# Exact-or-numbered match: "Werewolf" must not eat "WerewolfStalker".
				if line.begins_with(marker) or line.begins_with(marker.substr(0, marker.length() - 1)) \
						and _numbered_variant(line, marker):
					skipping = true
					break
			if skipping:
				while not out.is_empty() and out[out.size() - 1].strip_edges().is_empty():
					out.remove_at(out.size() - 1)
				continue
		if skipping:
			continue
		out.append(line)
	var joined := "\n".join(out)
	return _strip_id_map_entries(joined)


func _numbered_variant(line: String, marker: String) -> bool:
	var base := marker.substr("[node name=\"".length())
	base = base.substr(0, base.length() - 1)
	var rest := line.substr("[node name=\"".length())
	var quote := rest.find("\"")
	if quote < 0:
		return false
	var node_name := rest.substr(0, quote)
	if not node_name.begins_with(base):
		return false
	var tail := node_name.substr(base.length())
	return tail.is_empty() or tail.is_valid_int()


## Remove this tool's entries from both id maps, leaving the hand-authored ones
## and their ids untouched.
func _strip_id_map_entries(text: String) -> String:
	var bases: Array[String] = []
	for pack: Array in PACKS:
		bases.append(String(pack[0]))
	var out: Array[String] = []
	for line in text.split("\n"):
		var drop := false
		for base in bases:
			if line.contains("NodePath(\"%s\")" % base):
				drop = true
				break
			# Numbered members.
			var at := line.find("NodePath(\"%s" % base)
			if at >= 0:
				drop = true
				break
		if drop:
			continue
		out.append(line)
	# A stripped trailing entry can leave a dangling comma before the closing "}".
	var joined := "\n".join(out)
	joined = joined.replace(",\n}", "\n}")
	return joined


func _insert_ext(text: String, placed: Array) -> String:
	var lines := "[ext_resource type=\"PackedScene\" uid=\"uid://v32667qwpj2l\" path=\"%s\" id=\"bk_hostile\"]\n" % HOSTILE
	var seen: Dictionary = {}
	for p: Dictionary in placed:
		var tpath: String = p["type"]
		if seen.has(tpath):
			continue
		seen[tpath] = "bk_t%d" % seen.size()
		lines += "[ext_resource type=\"Resource\" path=\"%s\" id=\"%s\"]\n" % [tpath, seen[tpath]]
	_ext_ids = seen
	# Godot requires every [ext_resource] before the first [sub_resource] or
	# [node], so these go directly after the last existing ext_resource rather
	# than in front of the root header — DimWood has sub_resources in between,
	# and inserting there produces a scene that silently fails to load.
	var out_lines: Array[String] = []
	var last_ext: int = -1
	var split := text.split("\n")
	for i in split.size():
		out_lines.append(split[i])
		if split[i].begins_with("[ext_resource"):
			last_ext = i
	assert(last_ext >= 0, "no ext_resource block found")
	var block := lines.strip_edges(false, true).split("\n")
	var merged: Array[String] = []
	for i in out_lines.size():
		merged.append(out_lines[i])
		if i == last_ext:
			for b in block:
				merged.append(b)
	return "\n".join(merged)


var _ext_ids: Dictionary = {}


## Append to both dictionaries, continuing from the highest id already present so
## a hand-authored mob never loses its sync id.
func _extend_id_maps(text: String, placed: Array) -> String:
	var next_id := 0
	for line in text.split("\n"):
		var colon := line.find(": NodePath(")
		if colon <= 0:
			continue
		var head := line.substr(0, colon).strip_edges()
		if head.is_valid_int():
			next_id = maxi(next_id, int(head) + 1)

	var add_id := ""
	var add_node := ""
	for p: Dictionary in placed:
		add_id += ",\n%d: NodePath(\"%s\")" % [next_id, p["name"]]
		add_node += ",\nNodePath(\"%s\"): %d" % [p["name"], next_id]
		next_id += 1

	var out := text
	var i_at := out.find("id_to_node = {")
	var i_end := out.find("\n}", i_at)
	out = out.substr(0, i_end) + add_id + out.substr(i_end)
	var n_at := out.find("node_to_id = {")
	var n_end := out.find("\n}", n_at)
	out = out.substr(0, n_end) + add_node + out.substr(n_end)
	return out


func _append_nodes(text: String, placed: Array) -> String:
	var out := text
	if not out.ends_with("\n"):
		out += "\n"
	for p: Dictionary in placed:
		out += "\n[node name=\"%s\" parent=\"ReplicatedPropsContainer\" instance=ExtResource(\"bk_hostile\")]\n" % p["name"]
		out += "position = Vector2(%s, %s)\n" % [str(p["pos"].x), str(p["pos"].y)]
		out += "debug_draw_ranges = false\n"
		out += "enemy_data = ExtResource(\"%s\")\n" % _ext_ids[p["type"]]
		out += "weapon = null\n"
	return out


## Cells any existing node already stands on, so a pack never lands on the
## campfire, a mineable node or another mob.
func _occupied_cells() -> Dictionary:
	var map: Node = (load(MAP) as PackedScene).instantiate()
	var out: Dictionary = {}
	for child in map.get_children():
		if child is Node2D:
			_reserve(out, _cell_of(child as Node2D), 4)
		for grand in child.get_children():
			if grand is Node2D:
				_reserve(out, _cell_of(grand as Node2D), 4)
	map.free()
	return out


func _cell_of(n: Node2D) -> Vector2i:
	return Vector2i(int(floor(n.position.x / 16.0)), int(floor(n.position.y / 16.0)))


## Reachable cells ordered nearest-first from `DimWoodEntrance`, blocked derived
## from tile collision exactly like `audit_biome_collision.gd` does.
func _ranked_by_distance() -> Array[Vector2i]:
	var map: Node = (load(MAP) as PackedScene).instantiate()
	var blocked: Dictionary = {}
	var used: Dictionary = {}
	for layer in _tile_layers(map):
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

	# The tile layers extend past the playable area — the flood fill reaches
	# scenery cells the camera never shows, and a pack placed there is a mob the
	# player can never see or fight. Clip to the map's own camera limits.
	var bounds := Rect2i(
		Vector2i(int(map.camera_limit_left / 16.0), int(map.camera_limit_top / 16.0)),
		Vector2i(
			int((map.camera_limit_right - map.camera_limit_left) / 16.0),
			int((map.camera_limit_bottom - map.camera_limit_top) / 16.0)
		)
	)

	var start_node := map.get_node_or_null("DimWoodEntrance") as Node2D
	if start_node == null:
		start_node = map.get_node_or_null("RespawnPoint") as Node2D
	assert(start_node != null, "DimWood has no entrance to flood fill from")
	var start := _cell_of(start_node)

	var dist: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
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

	var cells: Array[Vector2i] = []
	for cell: Vector2i in dist.keys():
		if bounds.has_point(cell):
			cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return int(dist[a]) < int(dist[b])
	)
	return cells


func _tile_layers(node: Node) -> Array[TileMapLayer]:
	var out: Array[TileMapLayer] = []
	for child in node.get_children():
		if child is TileMapLayer:
			out.append(child as TileMapLayer)
		out.append_array(_tile_layers(child))
	return out
