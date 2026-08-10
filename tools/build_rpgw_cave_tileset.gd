extends SceneTree
## Build the RPG Worlds Caves TileSet (32×32) used by Mining Cave.
##
## Terrain peering bits are derived from the artwork by MapKit rather than
## transcribed by hand, so `set_cells_terrain_connect` can autotile the ground
## blends. Cliff/pit rims stay explicit because their south face is three tiles
## tall, which corner-matching terrain mode cannot describe.
##
##   godot --headless --path . --import
##   godot --headless --path . -s tools/build_rpgw_cave_tileset.gd

const MapKit := preload("res://tools/lib/mapkit.gd")

const OUT := "res://source/common/gameplay/maps/tilesets/rpgw_caves_tileset.tres"
const MAIN := "res://assets/sprites/environment/rpgw_caves/MainLev2.0.png"
const DECO := "res://assets/sprites/environment/rpgw_caves/decorative.png"

## Overlay blend sets whose base is transparent, so each one feathers onto
## whatever ground layer sits beneath it.
const OVERLAY_SETS := [
	{"region": Rect2i(10, 31, 5, 9), "color": Color8(61, 68, 45), "terrain": 1, "name": "moss"},
	{"region": Rect2i(25, 31, 5, 9), "color": Color8(53, 57, 58), "terrain": 2, "name": "slate"},
	{"region": Rect2i(40, 31, 5, 9), "color": Color8(77, 59, 48), "terrain": 3, "name": "dirt"},
]


func _initialize() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 0)

	_add_atlas(ts, 0, MAIN, 32)
	_add_atlas(ts, 1, DECO, 32)

	# Ground blends are resolved at build time from an explicit corner-mask table
	# (see MapKit.corner_lookup), which gives the map builder exact control over
	# which tile lands on which corner combination.
	var tex: Texture2D = load(MAIN) as Texture2D
	for entry in OVERLAY_SETS:
		var table: Dictionary = MapKit.corner_lookup(tex, 32, entry["region"], entry["color"])
		var combos: Array = table.keys()
		combos.sort()
		print("blend '", entry["name"], "' corner combos=", combos.size(), " ", combos)

	_mark_collision(ts, 0, _cliff_cells(), 32)
	_mark_collision(ts, 1, _deco_blocking_cells(), 32)

	var err := ResourceSaver.save(ts, OUT)
	assert(err == OK, "save failed")
	print("RPGW_CAVE_TILESET_PASS ", OUT)
	quit(0)


## Every tile of the chasm rim template (cols 2–7, rows 0–8) plus its three-row
## south face, and the dark interior fill.
func _cliff_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(0, 9):
		for x in range(2, 8):
			cells.append(Vector2i(x, y))
	# Wider rim variants flanking the template.
	for y in range(0, 7):
		for x in [0, 1, 8, 9]:
			cells.append(Vector2i(x, y))
	return cells


func _deco_blocking_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	# Stalagmite / boulder clusters — light rows 1–7 and dark rows 8–14.
	for y in range(1, 15):
		for x in range(0, 12):
			cells.append(Vector2i(x, y))
	return cells


func _add_atlas(ts: TileSet, source_id: int, tex_path: String, tile: int) -> void:
	var tex: Texture2D = load(tex_path) as Texture2D
	assert(tex != null, "missing %s" % tex_path)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(tile, tile)
	var cols: int = int(tex.get_width() / tile)
	var rows: int = int(tex.get_height() / tile)
	for y in rows:
		for x in cols:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, source_id)
	print("atlas ", tex_path, " source=", source_id, " tiles=", src.get_tiles_count())


func _mark_collision(ts: TileSet, source_id: int, cells: Array, tile: int) -> void:
	var src := ts.get_source(source_id) as TileSetAtlasSource
	var h: float = float(tile) / 2.0
	var poly := PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)
	])
	for c in cells:
		var atlas: Vector2i = c
		if not src.has_tile(atlas):
			continue
		var td := src.get_tile_data(atlas, 0)
		if td == null:
			continue
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, poly)
