extends SceneTree
## Build TileSet for RPG Worlds Caves (32×32). Used by Mining Cave only —
## does not replace mining_cave_tileset.tres (shared with The Hollow).
##   godot --headless --path . --import
##   godot --headless --path . -s tools/build_rpgw_cave_tileset.gd

const OUT := "res://source/common/gameplay/maps/tilesets/rpgw_caves_tileset.tres"
const MAIN := "res://assets/sprites/environment/rpgw_caves/MainLev2.0.png"
const DECO := "res://assets/sprites/environment/rpgw_caves/decorative.png"

## Wall / ledge / void-shell tiles that block movement when placed on Walls.
const WALL_CELLS: Array[Vector2i] = [
	# Glowing orange chamber shell (demo room 0–8,0–7)
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(7, 1), Vector2i(8, 1), Vector2i(9, 1),
	Vector2i(0, 2), Vector2i(1, 2), Vector2i(8, 2), Vector2i(9, 2),
	Vector2i(0, 3), Vector2i(1, 3), Vector2i(8, 3), Vector2i(9, 3),
	Vector2i(0, 4), Vector2i(1, 4), Vector2i(8, 4), Vector2i(9, 4),
	Vector2i(0, 5), Vector2i(1, 5), Vector2i(8, 5), Vector2i(9, 5),
	Vector2i(0, 6), Vector2i(1, 6), Vector2i(2, 6), Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6),
	Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7),
	# Tall pillar / narrow passage accents
	Vector2i(10, 0), Vector2i(11, 0), Vector2i(12, 0), Vector2i(13, 0), Vector2i(14, 0),
	Vector2i(10, 1), Vector2i(14, 1), Vector2i(10, 2), Vector2i(14, 2),
	Vector2i(10, 3), Vector2i(14, 3), Vector2i(10, 4), Vector2i(14, 4),
	Vector2i(10, 5), Vector2i(14, 5), Vector2i(10, 6), Vector2i(14, 6),
	Vector2i(10, 7), Vector2i(11, 7), Vector2i(12, 7), Vector2i(13, 7), Vector2i(14, 7),
	# Extra glowing ledge pieces (right strip)
	Vector2i(15, 0), Vector2i(16, 0), Vector2i(17, 0), Vector2i(18, 0), Vector2i(19, 0),
	Vector2i(15, 1), Vector2i(16, 1), Vector2i(17, 1), Vector2i(18, 1), Vector2i(19, 1),
	Vector2i(15, 2), Vector2i(16, 2), Vector2i(17, 2), Vector2i(18, 2), Vector2i(19, 2),
	Vector2i(30, 0), Vector2i(31, 0), Vector2i(32, 0), Vector2i(33, 0), Vector2i(34, 0),
	Vector2i(30, 1), Vector2i(31, 1), Vector2i(32, 1), Vector2i(33, 1), Vector2i(34, 1),
	Vector2i(30, 2), Vector2i(31, 2), Vector2i(32, 2), Vector2i(33, 2), Vector2i(34, 2),
	Vector2i(30, 3), Vector2i(31, 3), Vector2i(32, 3), Vector2i(33, 3), Vector2i(34, 3),
	Vector2i(30, 4), Vector2i(31, 4), Vector2i(32, 4), Vector2i(33, 4), Vector2i(34, 4),
	Vector2i(30, 5), Vector2i(31, 5), Vector2i(32, 5), Vector2i(33, 5), Vector2i(34, 5),
	# Fill / dark rock clumps used as wall fill
	Vector2i(7, 5), Vector2i(8, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5), Vector2i(5, 5),
]


func _initialize() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 0)
	_add_atlas(ts, 0, MAIN, 32)
	_add_atlas(ts, 1, DECO, 32)
	_mark_collision(ts, 0, WALL_CELLS)
	# Decorative rocks / pillars that block
	_mark_collision(ts, 1, [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
		Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0),
		Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1),
		Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2), Vector2i(8, 2),
		Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3),
	])
	var err := ResourceSaver.save(ts, OUT)
	assert(err == OK, "save failed")
	print("RPGW_CAVE_TILESET_PASS ", OUT)
	quit(0)


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


func _mark_collision(ts: TileSet, source_id: int, cells: Array) -> void:
	var src := ts.get_source(source_id) as TileSetAtlasSource
	var poly := PackedVector2Array([
		Vector2(-16, -16), Vector2(16, -16), Vector2(16, 16), Vector2(-16, 16)
	])
	for c in cells:
		var atlas: Vector2i = c
		if not src.has_tile(atlas):
			src.create_tile(atlas)
		var td := src.get_tile_data(atlas, 0)
		if td == null:
			continue
		td.add_collision_polygon(0)
		td.set_collision_polygon_points(0, 0, poly)
