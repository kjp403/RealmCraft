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
	_add_atlas(ts, 0, "res://assets/sprites/environment/world_tileset/Desert/Ground.png", 16, true)
	_add_atlas(ts, 1, "res://assets/sprites/environment/world_tileset/Desert/Props.png", 16, true)
	_add_atlas(ts, 2, "res://assets/sprites/environment/world_tileset/Desert/Sand.png", 16, true)
	# SciGho outdoor house accents (lanterns / lattice / roof stalls)
	_add_atlas(ts, 3, "res://assets/sprites/environment/starter_platformer/OutdoorHouseSet.png", 16, true)
	_mark_collision(ts, 0, [
		Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4),
		Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4),
		Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0),
		Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5), Vector2i(4, 5),
		Vector2i(7, 5), Vector2i(8, 5), Vector2i(7, 6), Vector2i(8, 6), Vector2i(9, 6),
		Vector2i(7, 12), Vector2i(8, 12), Vector2i(7, 13), Vector2i(8, 13),
		Vector2i(0, 7), Vector2i(1, 7), Vector2i(2, 7), Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7),
		Vector2i(0, 8), Vector2i(1, 8), Vector2i(4, 8), Vector2i(5, 8),
		Vector2i(0, 9), Vector2i(1, 9), Vector2i(4, 9), Vector2i(5, 9),
		Vector2i(0, 10), Vector2i(1, 10), Vector2i(4, 10), Vector2i(5, 10),
		Vector2i(0, 11), Vector2i(1, 11), Vector2i(4, 11), Vector2i(5, 11),
		Vector2i(0, 12), Vector2i(1, 12), Vector2i(4, 12), Vector2i(5, 12),
		Vector2i(0, 13), Vector2i(5, 13),
		Vector2i(0, 14), Vector2i(1, 14), Vector2i(4, 14), Vector2i(5, 14),
	])
	_mark_collision(ts, 3, [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1),
		Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(0, 3),
		Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
		Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4),
		Vector2i(1, 4),  # stone lantern
	])
	_save(ts, OUT_DIR + "desert_tileset.tres")


func _build_fire_forge() -> void:
	var ts := TileSet.new()
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 0)
	# 0 = main forge sheet, 1 = SciGho starter fire, 2 = DG Fire Zone free masonry
	_add_atlas(ts, 0, "res://assets/sprites/environment/fire_forge/tiles.png", 16, true)
	_add_atlas(ts, 1, "res://assets/sprites/environment/starter_platformer/FireSet.png", 16, true)
	_add_atlas(ts, 2, "res://assets/sprites/environment/dg_fire/all_tiles_free.png", 16, true)
	var wall_and_block: Array = [
		# shell
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
		Vector2i(2, 0), Vector2i(0, 2), Vector2i(4, 2),
		Vector2i(0, 0), Vector2i(4, 0), Vector2i(0, 4), Vector2i(4, 4),
		Vector2i(1, 0), Vector2i(3, 0), Vector2i(1, 4), Vector2i(3, 4),
		# fence / rail
		Vector2i(10, 16), Vector2i(11, 16), Vector2i(12, 16),
		Vector2i(10, 17), Vector2i(11, 17), Vector2i(12, 17),
		Vector2i(10, 18), Vector2i(11, 18), Vector2i(12, 18),
		Vector2i(10, 19), Vector2i(11, 19), Vector2i(12, 19),
		Vector2i(8, 19),
	]
	# Lava hazard tiles (collision when painted on Ground)
	for y in range(13, 25):
		for x in range(19, 25):
			wall_and_block.append(Vector2i(x, y))
	_mark_collision(ts, 0, wall_and_block)
	# Starter FireSet — lava / fire vents / spikes / rock (blocking)
	_mark_collision(ts, 1, [
		Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(4, 4),
		Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4),
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
		Vector2i(3, 0), Vector2i(4, 0), Vector2i(4, 1),
	])
	# DG fire free — brick shells / well rings / pillars
	_mark_collision(ts, 2, [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1),
		Vector2i(1, 2), Vector2i(4, 2), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3),
		Vector2i(8, 1), Vector2i(9, 1), Vector2i(10, 1),
		Vector2i(8, 2), Vector2i(10, 2), Vector2i(8, 3), Vector2i(9, 3), Vector2i(10, 3),
		Vector2i(6, 2), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5),
	])
	_save(ts, OUT_DIR + "fire_forge_tileset.tres")


func _build_sewers() -> void:
	var ts := TileSet.new()
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 0)
	# 0 = pixel dungeon, 1 = RF catacombs 32px, 2 = DarkCastle, 3 = DG Set 1
	_add_atlas(ts, 0, "res://assets/sprites/environment/pixel_dungeon/dungeon_tileset.png", 16, true)
	_add_atlas(ts, 1, "res://assets/sprites/environment/rf_catacombs/mainlevbuild.png", 32, true)
	_add_atlas(ts, 2, "res://assets/sprites/environment/starter_platformer/DarkCastle.png", 16, true)
	_add_atlas(ts, 3, "res://assets/sprites/environment/dg_dungeon/set1.png", 16, true)
	_mark_collision(ts, 0, [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0),
		Vector2i(0, 1), Vector2i(5, 1),
		Vector2i(0, 2), Vector2i(5, 2),
		Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3),
		Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4),
		Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0), Vector2i(9, 0),
		Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1), Vector2i(9, 1),
	])
	_mark_collision(ts, 1, [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
	])
	# DarkCastle walls / doors / grates / gargoyles
	_mark_collision(ts, 2, [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(4, 0),
		Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2), Vector2i(1, 2),
		Vector2i(2, 1), Vector2i(2, 2),
		Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 3), Vector2i(4, 4),
		Vector2i(4, 1), Vector2i(4, 2),
	])
	# DG Set1 — wall / pillar / arch shells (skip arrow UI tiles in top-left)
	var dg_walls: Array = []
	for y in range(7, 11):
		for x in range(0, 16):
			dg_walls.append(Vector2i(x, y))
	for y in range(11, 14):
		for x in range(11, 16):
			dg_walls.append(Vector2i(x, y))
	_mark_collision(ts, 3, dg_walls)
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
