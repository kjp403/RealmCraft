extends SceneTree
## Create desert / fire_forge / sewers TileSet resources from imported atlases.
## Run after Godot imports PNGs:
##   godot --headless --path . --import
##   godot --headless --path . -s tools/build_biome_tilesets.gd

const OUT_DIR := "res://source/common/gameplay/maps/tilesets/"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_build_desert()
	_build_fire_forge()
	_build_sewers()
	print("BIOME_TILESETS_PASS")
	quit(0)


func _build_desert() -> void:
	var ts := TileSet.new()
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 0)
	_add_atlas(
		ts,
		0,
		"res://assets/sprites/environment/world_tileset/Desert/Ground.png",
		16,
		true
	)
	_add_atlas(
		ts,
		1,
		"res://assets/sprites/environment/world_tileset/Desert/Props.png",
		16,
		true
	)
	_add_atlas(
		ts,
		2,
		"res://assets/sprites/environment/world_tileset/Desert/Sand.png",
		16,
		true
	)
	# Cliff / rock cells used as Walls get collision.
	_mark_collision(ts, 0, [
		Vector2i(7, 5), Vector2i(8, 5), Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 6),
		Vector2i(7, 12), Vector2i(8, 12), Vector2i(7, 13), Vector2i(8, 13),
		Vector2i(5, 4), Vector2i(4, 5), Vector2i(2, 5), Vector2i(3, 5),
	])
	_save(ts, OUT_DIR + "desert_tileset.tres")


func _build_fire_forge() -> void:
	var ts := TileSet.new()
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 0)
	_add_atlas(ts, 0, "res://assets/sprites/environment/fire_forge/tiles.png", 16, true)
	_mark_collision(ts, 0, [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
		Vector2i(2, 0), Vector2i(0, 2), Vector2i(4, 2),
		Vector2i(10, 18), Vector2i(12, 18), Vector2i(8, 19),
	])
	_save(ts, OUT_DIR + "fire_forge_tileset.tres")


func _build_sewers() -> void:
	var ts := TileSet.new()
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 0)
	_add_atlas(ts, 0, "res://assets/sprites/environment/pixel_dungeon/dungeon_tileset.png", 16, true)
	_add_atlas(ts, 1, "res://assets/sprites/environment/rf_catacombs/mainlevbuild.png", 32, true)
	# Pixel dungeon wall-ish purple stone
	_mark_collision(ts, 0, [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
		Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3),
		Vector2i(0, 4), Vector2i(5, 4),
	])
	# RF wall blocks (source 1) — coarse 32px collision for accents if used on Walls
	_mark_collision(ts, 1, [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
	])
	_save(ts, OUT_DIR + "sewers_tileset.tres")


func _add_atlas(ts: TileSet, source_id: int, tex_path: String, tile: int, create_all: bool) -> void:
	var tex: Texture2D = load(tex_path) as Texture2D
	assert(tex != null, "missing texture %s" % tex_path)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(tile, tile)
	var cols: int = int(tex.get_width() / tile)
	var rows: int = int(tex.get_height() / tile)
	if create_all:
		# Always create the full atlas grid. Skipping "empty" cells via CPU image
		# is unreliable with compressed imports and can yield 0 tiles.
		for y in rows:
			for x in cols:
				src.create_tile(Vector2i(x, y))
	ts.add_source(src, source_id)
	print("atlas ", tex_path, " source=", source_id, " tiles=", src.get_tiles_count())


func _mark_collision(ts: TileSet, source_id: int, cells: Array) -> void:
	var src := ts.get_source(source_id) as TileSetAtlasSource
	var poly := PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)
	])
	# RF 32px tiles need larger poly
	if src.texture_region_size.x >= 32:
		poly = PackedVector2Array([
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


func _save(ts: TileSet, path: String) -> void:
	var err := ResourceSaver.save(ts, path)
	assert(err == OK, "save failed %s" % path)
	print("wrote ", path)
