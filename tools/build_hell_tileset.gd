extends SceneTree
## Build the 32×32 Brimstone Vault TileSet from the dark hell sheet.
## Collision lives on the 3×3 room rims, pillars, spikes, and cyan pools —
## never on the walkable floor fills.
##   godot --headless --path . --import
##   godot --headless --path . -s tools/build_hell_tileset.gd

const OUT := "res://source/common/gameplay/maps/tilesets/hell_tileset.tres"
const TILES := "res://assets/sprites/environment/hell/tiles_dark.png"


func _initialize() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(32, 32)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 0)

	_add_atlas(ts, 0, TILES)
	_mark_collision(ts, 0, _blocking_cells(), 32)

	var err := ResourceSaver.save(ts, OUT)
	assert(err == OK, "save failed")
	print("HELL_TILESET_PASS ", OUT, " blocking=", _blocking_cells().size())
	quit(0)


func _blocking_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	# Four 3×3 room templates — rims plus the hollow centres (used as the
	# brimstone well void; never stamped on walkable floor).
	for origin in [Vector2i(0, 0), Vector2i(3, 0), Vector2i(0, 3), Vector2i(3, 3)]:
		for oy in 3:
			for ox in 3:
				cells.append(origin + Vector2i(ox, oy))
	# Plus-shaped corridor rims (centres at (10,1) and (10,4) are floor).
	for cell in [
		Vector2i(9, 0), Vector2i(10, 0), Vector2i(11, 0), Vector2i(12, 0),
		Vector2i(9, 1), Vector2i(11, 1), Vector2i(12, 1),
		Vector2i(9, 2), Vector2i(10, 2), Vector2i(11, 2), Vector2i(12, 2),
		Vector2i(9, 3), Vector2i(10, 3), Vector2i(11, 3), Vector2i(12, 3),
		Vector2i(9, 4), Vector2i(11, 4),
		Vector2i(9, 5), Vector2i(10, 5), Vector2i(11, 5), Vector2i(12, 5),
	]:
		cells.append(cell)
	# Oval-room rim (centre row is floor).
	for cell in [
		Vector2i(0, 6), Vector2i(2, 6), Vector2i(4, 6), Vector2i(5, 6),
		Vector2i(0, 7), Vector2i(4, 7), Vector2i(5, 7),
		Vector2i(0, 8), Vector2i(2, 8), Vector2i(4, 8), Vector2i(5, 8),
		Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6),
	]:
		cells.append(cell)
	# Cyan pools, pillars, spikes, skull-rock piles that should block.
	for cell in [
		Vector2i(13, 0), Vector2i(14, 0), Vector2i(13, 1), Vector2i(14, 1),
		Vector2i(13, 2), Vector2i(14, 2), Vector2i(13, 3), Vector2i(14, 3),
		Vector2i(13, 4), Vector2i(14, 4), Vector2i(13, 5), Vector2i(14, 5),
		Vector2i(13, 6), Vector2i(14, 6), Vector2i(13, 7), Vector2i(14, 7),
		Vector2i(13, 8), Vector2i(14, 8),
		Vector2i(15, 0), Vector2i(16, 0), Vector2i(15, 2), Vector2i(16, 2),
		Vector2i(15, 3), Vector2i(16, 3), Vector2i(15, 4), Vector2i(16, 4),
		Vector2i(15, 5), Vector2i(16, 5),
	]:
		cells.append(cell)
	return cells


func _add_atlas(ts: TileSet, source_id: int, tex_path: String) -> void:
	var tex: Texture2D = load(tex_path) as Texture2D
	assert(tex != null, "missing %s" % tex_path)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(32, 32)
	var cols: int = int(tex.get_width() / 32)
	var rows: int = int(tex.get_height() / 32)
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
