extends Node
## Build Starfall Grove — the dedicated high-tier woodcutting zone.
##
##   godot --path . --mode=client res://tools/build_starfall_grove.tscn
##
## Run as a SCENE, not with `-s`: this loads Goblin Woodland as a reference and
## that map pulls NPC scenes, which reach the Client / ClientState autoloads a
## `-s` run does not provide.
##
## Same approach as build_ossuran_arena.gd, and for the same reason: the tiles
## are LEARNED from a map that already exists and already looks right, not
## picked by index or by average colour. The overworld set's path, dirt and
## cliff cells are DIRECTIONAL — a north path edge only reads along the north
## side — so choosing variants by hand scatters loose cobble across the field
## instead of drawing a road. Each cell's ROLE is the bitmask of which of its
## four neighbours share its material, and every cell with the same role gets
## the tile Goblin Woodland most often uses for that role.
##
## The GRAMMAR is Woodland's too, because that map is the quality bar: one open
## field you walk across, dirt roads joining named places, ground-material
## patches marking each place, and SPARSE tree clumps. Earlier passes built
## disconnected clearings floating in a void and then buried the void in
## thousands of decorative trees; neither is what any shipping map here does.
##
## Places, in walking order from the arrival portal:
##   Grovewatch Camp   — campfire, the way home
##   Wisp Hollow       — Wispwood (lv60), teal
##   Glimmer Rise      — Glimmer-birch (lv80), electric blue
##   Nebula Terrace    — Nebula Palm (lv70), violet
##   Rosewood Heart    — Supernova Rosewood (lv85), the showpiece
##   The Unquarried Shelf — RESERVED and bare on purpose (see _shelf_note)

const REFERENCE := "res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn"
const OUT := "res://source/common/gameplay/maps/maps/starfall_grove/starfall_grove.tscn"
const INST := "res://source/common/gameplay/maps/instance/instance_collection/"
const NODES := "res://source/common/gameplay/maps/components/mineable_nodes/"
const WOODLAND_TS := "res://source/common/gameplay/maps/tilesets/woodland_tileset.tres"

const W: int = 140
const H: int = 96
## Cells of cliff between the field edge and the end of the map.
const BORDER: int = 3

const SRC_VEG: int = 2
const SRC_TREE_SMALL: int = 3
const SRC_TREE_MED: int = 4
const SRC_TREE_BIG: int = 5

var _bounds := Rect2i(0, 0, W, H)

## Learned from the reference map in _ready.
var _grass: Array = []
var _grass_detail: Array = []
var _path_roles: Dictionary = {}
var _dirt_roles: Dictionary = {}
var _wall_roles: Dictionary = {}


func _ready() -> void:
	var packed: PackedScene = load(REFERENCE)
	if packed == null:
		printerr("could not load ", REFERENCE)
		get_tree().quit(1)
		return
	var root: Node = packed.instantiate()
	var ground_ref: TileMapLayer = _find_layer(root, &"Ground")
	var features_ref: TileMapLayer = _find_layer(root, &"Features")
	var walls_ref: TileMapLayer = _find_layer(root, &"Walls")
	if ground_ref == null or features_ref == null or walls_ref == null:
		printerr("reference map is missing Ground / Features / Walls")
		root.free()
		get_tree().quit(1)
		return

	var ts: TileSet = ground_ref.tile_set
	_grass = _tiles_of_family(ground_ref, ts, &"grass")
	_grass_detail = _tiles_of_family(features_ref, ts, &"grass")
	_path_roles = _learn_roles(features_ref, ts, &"stone")
	_dirt_roles = _learn_roles(features_ref, ts, &"dirt")
	_wall_roles = _learn_roles(walls_ref, ts, &"")
	root.free()

	if _grass.is_empty() or _path_roles.is_empty() or _wall_roles.is_empty():
		printerr("could not learn the Woodland palette")
		get_tree().quit(1)
		return
	print("learned: grass %d, detail %d, path roles %d, dirt roles %d, wall roles %d" % [
		_grass.size(), _grass_detail.size(), _path_roles.size(),
		_dirt_roles.size(), _wall_roles.size()])

	_build(ts)
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# Learning the reference palette
# ---------------------------------------------------------------------------

## Average opaque colour of one atlas cell, so a tile can be sorted into a
## material family without anybody transcribing atlas coordinates by hand.
func _tile_color(ts: TileSet, sid: int, atlas: Vector2i) -> Color:
	var src := ts.get_source(sid) as TileSetAtlasSource
	if src == null or src.texture == null:
		return Color(0, 0, 0, 0)
	var img: Image = src.texture.get_image()
	var region: Rect2i = src.get_tile_texture_region(atlas)
	var total := Vector3.ZERO
	var n: int = 0
	for y in range(region.position.y, region.end.y, 2):
		for x in range(region.position.x, region.end.x, 2):
			if x >= img.get_width() or y >= img.get_height():
				continue
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			total += Vector3(c.r, c.g, c.b)
			n += 1
	if n == 0:
		return Color(0, 0, 0, 0)
	return Color(total.x / n, total.y / n, total.z / n, 1.0)


## Material family of a tile: grass (green wins), dirt (warm brown), stone (the
## desaturated cobble the roads are paved with). Everything else is "".
func _family(c: Color) -> StringName:
	if c.a < 0.5:
		return &""
	if c.g > c.r and c.g > c.b:
		return &"grass"
	if c.r - c.b > 0.30:
		return &"dirt"
	if c.r > 0.30 and c.r - c.b < 0.30:
		return &"stone"
	return &""


## Every distinct tile of one family used on a layer, ranked by how often the
## reference map paints it — index 0 is the material's plain fill.
func _tiles_of_family(layer: TileMapLayer, ts: TileSet, want: StringName) -> Array:
	var counts: Dictionary = {}
	for cell: Vector2i in layer.get_used_cells():
		var key: String = "%d|%d|%d" % [
			layer.get_cell_source_id(cell),
			layer.get_cell_atlas_coords(cell).x,
			layer.get_cell_atlas_coords(cell).y,
		]
		counts[key] = int(counts.get(key, 0)) + 1
	var ranked: Array = counts.keys()
	ranked.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
	var out: Array = []
	for key: String in ranked:
		var parts: PackedStringArray = key.split("|")
		var sid: int = int(parts[0])
		var atlas := Vector2i(int(parts[1]), int(parts[2]))
		if want != &"" and _family(_tile_color(ts, sid, atlas)) != want:
			continue
		out.append([sid, atlas])
		if out.size() >= 6:
			break
	return out


## role (4-neighbour bitmask within the same family) -> [source_id, atlas].
## `want` empty means "every tile on this layer is one family", which is how the
## cliff border is learned.
func _learn_roles(layer: TileMapLayer, ts: TileSet, want: StringName) -> Dictionary:
	var mine: Dictionary = {}
	for cell: Vector2i in layer.get_used_cells():
		var sid: int = layer.get_cell_source_id(cell)
		var atlas: Vector2i = layer.get_cell_atlas_coords(cell)
		if want != &"" and _family(_tile_color(ts, sid, atlas)) != want:
			continue
		mine[cell] = [sid, atlas]

	var tally: Dictionary = {}
	for cell: Vector2i in mine:
		var entry: Array = mine[cell]
		var key: String = "%d|%d|%d" % [entry[0], entry[1].x, entry[1].y]
		var role: int = _role_of(mine, cell)
		if not tally.has(role):
			tally[role] = {}
		tally[role][key] = int(tally[role].get(key, 0)) + 1

	var out: Dictionary = {}
	for role: int in tally:
		var counts: Dictionary = tally[role]
		var ranked: Array = counts.keys()
		ranked.sort_custom(func(a: String, b: String) -> bool: return counts[a] > counts[b])
		var parts: PackedStringArray = str(ranked[0]).split("|")
		out[role] = [int(parts[0]), Vector2i(int(parts[1]), int(parts[2]))]
	return out


## Which of a cell's four neighbours share its material, as a bitmask
## (1 N, 2 S, 4 W, 8 E).
func _role_of(mask: Dictionary, cell: Vector2i) -> int:
	var role: int = 0
	if mask.has(cell + Vector2i(0, -1)):
		role |= 1
	if mask.has(cell + Vector2i(0, 1)):
		role |= 2
	if mask.has(cell + Vector2i(-1, 0)):
		role |= 4
	if mask.has(cell + Vector2i(1, 0)):
		role |= 8
	return role


func _find_layer(node: Node, wanted: StringName) -> TileMapLayer:
	if node is TileMapLayer and node.name == wanted:
		return node as TileMapLayer
	for child: Node in node.get_children():
		var hit: TileMapLayer = _find_layer(child, wanted)
		if hit != null:
			return hit
	return null


## Paint every cell of `mask` with the learned tile for its role.
func _paint_roles(layer: TileMapLayer, mask: Dictionary, roles: Dictionary) -> void:
	if roles.is_empty():
		return
	var fallback: Array = roles.get(15, roles.values()[0])
	for cell: Vector2i in mask:
		var tile: Array = roles.get(_role_of(mask, cell), fallback)
		layer.set_cell(cell, tile[0], tile[1])


func _new_layer(ts: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	return layer


# ---------------------------------------------------------------------------
# The map
# ---------------------------------------------------------------------------

func _build(ts: TileSet) -> void:
	var ground := _new_layer(ts)
	var walls := _new_layer(ts)
	var props := _new_layer(ts)
	var overlay := _new_layer(ts)   # roads + material patches, above Ground

	var places: Dictionary = {
		"camp": Vector2i(18, 78),
		"wisp": Vector2i(30, 44),
		"cross": Vector2i(62, 54),
		"glimmer": Vector2i(62, 16),
		"nebula": Vector2i(112, 32),
		"rose": Vector2i(88, 74),
		"shelf": Vector2i(122, 80),
	}

	# --- The field ----------------------------------------------------------
	# ONE open, walk-anywhere field with an organic outline, the way Goblin
	# Woodland is one field. Not clearings joined by corridors.
	var field: Dictionary = {}
	for spot: Array in [
		[Vector2i(70, 48), 54.0, 0.10, 701],
		[Vector2i(34, 60), 30.0, 0.16, 702],
		[Vector2i(108, 56), 30.0, 0.16, 703],
		[Vector2i(66, 20), 26.0, 0.18, 704],
	]:
		MapKit.blob(field, spot[0], spot[1], spot[2], spot[3], _bounds)
	field = MapKit.smooth(field, _bounds, 2, 5, 4)
	# Keep the field clear of the map edge so the cliff border always fits.
	for cell: Vector2i in field.keys():
		if cell.x < BORDER or cell.y < BORDER or cell.x >= W - BORDER or cell.y >= H - BORDER:
			field.erase(cell)
	var home: Vector2i = LevelKit.pick_open(field, places["camp"])
	field = MapKit.largest_region(field, home)
	for key: String in places.keys():
		places[key] = LevelKit.pick_open(field, places[key])
	home = places["camp"]

	var grass_atlases: Array = []
	for entry: Array in _grass:
		grass_atlases.append(entry[1])
	for cell: Vector2i in field:
		ground.set_cell(cell, _grass[0][0], MapKit._pick(grass_atlases, cell, 751))

	# --- Cliff border -------------------------------------------------------
	# A BORDER-deep ring of cliff and nothing past it. Beyond the ring the map
	# simply ends: no ground, no props, nothing for a player to see or reach.
	var wall: Dictionary = {}
	for y in H:
		for x in W:
			var cell := Vector2i(x, y)
			if field.has(cell) or not _within(field, cell, BORDER):
				continue
			wall[cell] = true
	_paint_roles(walls, wall, _wall_roles)

	# --- Roads --------------------------------------------------------------
	# The dirt roads ARE the layout: they are how a player reads where the
	# stands are before they can see them.
	var road: Dictionary = {}
	for link: Array in [
		["camp", "cross", 711], ["cross", "wisp", 712], ["cross", "glimmer", 713],
		["cross", "nebula", 714], ["cross", "rose", 715], ["rose", "shelf", 716],
	]:
		MapKit.tunnel(road, places[link[0]], places[link[1]], 1.6, 4.0, link[2], _bounds)
	for cell: Vector2i in road.keys():
		if not field.has(cell):
			road.erase(cell)
	_paint_roles(overlay, road, _path_roles)

	# --- Ground patches -----------------------------------------------------
	# Each stand stands on its own bare earth, so a place reads as a place from
	# across the field rather than as grass with trees on it.
	var dirt: Dictionary = {}
	for spot: Array in [
		["wisp", 9.0, 721], ["glimmer", 9.0, 722], ["nebula", 9.0, 723],
		["rose", 8.0, 724], ["camp", 6.0, 725],
	]:
		MapKit.blob(dirt, places[spot[0]], spot[1], 0.28, spot[2], _bounds)
	for cell: Vector2i in dirt.keys():
		if not field.has(cell) or road.has(cell):
			dirt.erase(cell)
	_paint_roles(overlay, dirt, _dirt_roles)

	# _shelf_note: the Unquarried Shelf is paved bare stone and deliberately has
	# no trees on it. The four high ore tiers (Dragon / Obsidian / Celestial /
	# Astralite) landed as a CAVE reached from here rather than as a stand on it
	# — see MiningCavePortal below and build_starfall_mining_cave.gd. The ground,
	# the road from Rosewood Heart and ShelfGlow were already waiting for them.
	var shelf: Dictionary = {}
	MapKit.blob(shelf, places["shelf"], 11.0, 0.24, 726, _bounds)
	for cell: Vector2i in shelf.keys():
		if not field.has(cell):
			shelf.erase(cell)
	_paint_roles(overlay, shelf, _path_roles)

	# --- Stands -------------------------------------------------------------
	var stands: Dictionary = {}
	var gather_nodes: Array = []
	for stand: Array in [
		["wisp", "wispwood_tree", 7, 7, "Wispwood"],
		["glimmer", "glimmer_birch_tree", 6, 7, "GlimmerBirch"],
		["nebula", "nebula_palm_tree", 6, 7, "NebulaPalm"],
		["rose", "supernova_rosewood_tree", 4, 6, "Rosewood"],
	]:
		var wanted: Array = _ring(places[stand[0]], int(stand[3]), int(stand[2]))
		var spots: Array[Vector2i] = LevelKit.pick_spread(field, wanted, 6)
		for i in spots.size():
			gather_nodes.append({
				"name": "%s%d" % [stand[4], i + 1],
				"data": NODES + stand[1] + ".tres",
				"pos": LevelKit.tile_pos(spots[i]),
			})
		for c: Vector2i in LevelKit.keepout(spots, 3).keys():
			stands[c] = true

	# --- Tree clumps --------------------------------------------------------
	# Authored clumps, not a scatter over the whole map. Woodland carries a few
	# dozen trees across a field larger than this one; a "forest" of thousands
	# of props is noise, and props never belong off the painted ground.
	var free: Dictionary = {}
	for cell: Vector2i in field:
		if stands.has(cell) or road.has(cell) or shelf.has(cell):
			continue
		free[cell] = true
	for cell: Vector2i in LevelKit.keepout([home], 6).keys():
		free.erase(cell)

	var solid: Dictionary = {}
	var clumps: Array = [
		Vector2i(46, 34), Vector2i(24, 26), Vector2i(84, 20), Vector2i(104, 16),
		Vector2i(126, 50), Vector2i(96, 46), Vector2i(40, 72), Vector2i(62, 82),
		Vector2i(18, 54), Vector2i(76, 62), Vector2i(110, 70), Vector2i(34, 88),
		Vector2i(52, 44), Vector2i(92, 88),
	]
	var big: Array = [[0, 0, 5, 8], [5, 0, 5, 8], [0, 8, 5, 8], [5, 8, 5, 8]]
	var med: Array = [[0, 0, 3, 6], [3, 0, 3, 6], [0, 6, 3, 6], [3, 6, 3, 6]]
	var small: Array = [[2, 0, 2, 4], [6, 0, 2, 4], [10, 0, 2, 4], [14, 0, 2, 4]]
	for i in clumps.size():
		var at: Vector2i = LevelKit.pick_open(free, clumps[i])
		var near: Array = []
		for oy in range(-6, 7):
			for ox in range(-6, 7):
				var c: Vector2i = at + Vector2i(ox, oy)
				if free.has(c):
					near.append(c)
		LevelKit.scatter_props(props, SRC_TREE_BIG, near, big, 0.16, 5, 730 + i, free, solid)
		LevelKit.scatter_props(props, SRC_TREE_MED, near, med, 0.14, 4, 750 + i, free, solid)
		LevelKit.scatter_props(props, SRC_TREE_SMALL, near, small, 0.12, 3, 770 + i, free, solid)

	# Bushes along the field edge only — the boundary wants texture, the middle
	# of a skilling field wants to stay walkable.
	var rim: Array = []
	for cell: Vector2i in free:
		if _within(wall, cell, 2):
			rim.append(cell)
	LevelKit.scatter_props(props, SRC_VEG, rim, [
		[0, 0, 2, 2], [3, 0, 2, 2], [6, 0, 2, 2], [9, 0, 2, 2],
	], 0.10, 5, 790, free, solid)

	var walk: Dictionary = LevelKit.walkable(field, wall)
	for cell: Vector2i in solid.keys():
		walk.erase(cell)
	walk = MapKit.largest_region(walk, home)

	var detail: Array = []
	for entry: Array in _grass_detail:
		if entry[1] not in grass_atlases:
			detail.append(entry[1])
	if not detail.is_empty():
		LevelKit.scatter_flat(overlay, _grass[0][0], free.keys(), detail, 0.03, 6, 795, solid)

	# --- Lighting -----------------------------------------------------------
	var lights: Array = []
	for lit: Array in [
		["WispGlow", "wisp", "Color(0.16, 0.86, 0.95, 1)", 0.75, 3.2],
		["GlimmerGlow", "glimmer", "Color(0.30, 0.66, 1, 1)", 0.8, 3.2],
		["NebulaGlow", "nebula", "Color(0.72, 0.34, 0.95, 1)", 0.72, 3.2],
		["RoseGlow", "rose", "Color(1, 0.36, 0.60, 1)", 0.95, 3.6],
		["ShelfGlow", "shelf", "Color(0.95, 0.78, 0.45, 1)", 0.45, 2.8],
		["CampGlow", "camp", "Color(1, 0.78, 0.45, 1)", 0.6, 2.6],
	]:
		lights.append({
			"name": lit[0], "pos": LevelKit.tile_pos(LevelKit.pick_open(walk, places[lit[1]])),
			"color": lit[2], "energy": lit[3], "scale": lit[4],
		})

	var decos: Array = []
	var lantern_plan: Array = [
		["wisp", Vector2i(-10, 5), "Color(0.25, 0.9, 0.95, 1)"],
		["wisp", Vector2i(10, -6), "Color(0.25, 0.9, 0.95, 1)"],
		["glimmer", Vector2i(-10, 6), "Color(0.35, 0.7, 1, 1)"],
		["glimmer", Vector2i(10, 5), "Color(0.35, 0.7, 1, 1)"],
		["nebula", Vector2i(-11, 5), "Color(0.78, 0.4, 1, 1)"],
		["nebula", Vector2i(9, -7), "Color(0.78, 0.4, 1, 1)"],
		["rose", Vector2i(-9, -6), "Color(1, 0.42, 0.65, 1)"],
		["rose", Vector2i(9, 6), "Color(1, 0.42, 0.65, 1)"],
		["cross", Vector2i(-6, 0), "Color(0.7, 0.8, 1, 1)"],
		["cross", Vector2i(6, 0), "Color(0.7, 0.8, 1, 1)"],
		["shelf", Vector2i(-8, -5), "Color(1, 0.86, 0.55, 1)"],
		["camp", Vector2i(-6, -4), "Color(1, 0.8, 0.5, 1)"],
	]
	for i in lantern_plan.size():
		var plan: Array = lantern_plan[i]
		decos.append({
			"name": "GroveLantern%d" % (i + 1),
			"frames": "deco_candle_a" if i % 2 == 0 else "deco_candle_b",
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, places[plan[0]] + plan[1])),
			"scale": 1.3, "light": 0.7, "color": plan[2],
		})

	var critters: Array = []
	var critter_names := ["critter_stag", "critter_badger", "critter_boar"]
	var critter_spots: Array = [
		Vector2i(44, 30), Vector2i(80, 40), Vector2i(30, 66), Vector2i(100, 60),
		Vector2i(70, 26), Vector2i(56, 68), Vector2i(116, 44), Vector2i(24, 40),
	]
	for i in critter_spots.size():
		critters.append({
			"name": "GroveCritter%d" % (i + 1),
			"frames": critter_names[i % critter_names.size()],
			"pos": LevelKit.tile_pos(LevelKit.pick_open(walk, critter_spots[i])),
			"scale": 0.9, "wander_radius": 56.0,
		})

	print("Starfall Grove: walk=%d nodes=%d tree props=%d" % [
		walk.size(), gather_nodes.size(), solid.size()])

	LevelKit.write_map({
		"root": "starfall_grove",
		"out": OUT,
		"tileset": WOODLAND_TS,
		# Dusk, not night: dark enough that the trees and lanterns are the
		# brightest things on screen, light enough to read the field you cross.
		"bg": "Color(0.035, 0.045, 0.075, 1)",
		"modulate": "Color(0.52, 0.57, 0.74, 1)",
		"music": "res://assets/audio/music/lost_woods.ogg",
		"playlist": ["res://assets/audio/music/alone.ogg"],
		"layers": {
			"Ground": LevelKit.b64(ground),
			"Walls": LevelKit.b64(walls),
			"Props": LevelKit.b64(props),
			"Overlay": LevelKit.b64(overlay),
		},
		"cam_right": W * 16 + 16,
		"cam_bottom": H * 16 + 16,
		"camps": [{"name": "GroveCampfire", "pos": LevelKit.tile_pos(home + Vector2i(0, -3))}],
		"lights": lights,
		"decos": decos,
		"critters": critters,
		"nodes": gather_nodes,
		"spawn": LevelKit.tile_pos(home),
		"warpers": [
			{"name": "Entrance", "pos": LevelKit.tile_pos(home), "id": 33},
			# Where a player lands coming back UP out of the mine. Sits on the
			# Unquarried Shelf, which this map has always paved and lit for the
			# high ore tiers — they are a cave off it rather than a stand on it.
			{"name": "CaveMouth", "pos": LevelKit.tile_pos(places["shelf"]), "id": 35},
		],
		"portals": [
			{
				"name": "HubPortal", "pos": LevelKit.tile_pos(home + Vector2i(3, 2)),
				"id": 133, "target_id": 33, "instance": INST + "overworld.tres",
				"label": "Castle Garden", "color": "Color(0.36, 0.86, 0.82, 1)",
			},
			{
				"name": "MiningCavePortal",
				"pos": LevelKit.tile_pos(places["shelf"] + Vector2i(3, -2)),
				"id": 134, "target_id": 34,
				"instance": INST + "biomes/starfall_mining_cave.tres",
				"label": "Starfall Mining Cave", "color": "Color(0.82, 0.55, 1, 1)",
			},
		],
	})
	print("wrote ", OUT)


## True when `cell` is within `radius` cells of any member of `mask`.
func _within(mask: Dictionary, cell: Vector2i, radius: int) -> bool:
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			if mask.has(cell + Vector2i(ox, oy)):
				return true
	return false


## Authored spots on a ring around a place, so a stand reads as trees AROUND
## ground you stand on rather than a clump you have to walk through.
func _ring(at: Vector2i, radius: int, count: int) -> Array:
	var out: Array = []
	for i in count:
		var ang: float = TAU * float(i) / float(count) + 0.4
		out.append(at + Vector2i(int(round(cos(ang) * radius)), int(round(sin(ang) * radius * 0.8))))
	return out
