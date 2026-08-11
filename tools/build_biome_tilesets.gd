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
	# 0 = Top Down Lava sheet (floors / lava fill — individual 16×16 only)
	# 1 = GIF-derived animated lava (7 frames × N rows; paint origin cell only)
	# 2 = packed 16×16 props (rocks / chest)
	# 3 = DG Fire free masonry (proper wall shell tiles)
	# 4 = Fire Forge foundry sheet — the only bank in this biome with a genuinely
	#     textured walkable floor. DG Fire's "floor" cells (source 3, cols 5/7)
	#     are flat single-colour fills, which is what made every Forge level read
	#     as a painted background. `forgefloor.gd` owns the cell picks.
	_add_atlas(ts, 0, "res://assets/sprites/environment/lava_forge_16/freelavatileset_sheet.png", 16, true)
	_add_atlas(ts, 1, "res://assets/sprites/environment/lava_forge_16/lava_tile_anim_strip.png", 16, true)
	_add_atlas(ts, 2, "res://assets/sprites/environment/lava_forge_16/forge_props_16.png", 16, true)
	_add_atlas(ts, 3, "res://assets/sprites/environment/dg_fire/all_tiles_free.png", 16, true)
	_add_atlas(ts, 4, "res://assets/sprites/environment/fire_forge/tiles.png", 16, true)
	_setup_row_animations(ts, 1, 7, 8.0)

	# Lava hazard on source 0 (static fill + edges) + anim origins on source 1.
	_mark_collision(ts, 0, [
		Vector2i(1, 11), Vector2i(2, 11), Vector2i(7, 11),
		Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11),
		Vector2i(2, 13), Vector2i(3, 13), Vector2i(6, 13),
		Vector2i(18, 13), Vector2i(19, 13), Vector2i(20, 13), Vector2i(26, 13),
	])
	var anim_block: Array = []
	var anim_src := ts.get_source(1) as TileSetAtlasSource
	var anim_rows: int = int(anim_src.texture.get_height() / 16)
	for y in anim_rows:
		anim_block.append(Vector2i(0, y))
	_mark_collision(ts, 1, anim_block)
	# DG Fire wall shells / pillars / well rings
	_mark_collision(ts, 3, [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
		Vector2i(0, 1), Vector2i(3, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2),
		Vector2i(1, 1), Vector2i(2, 1),
		Vector2i(8, 1), Vector2i(9, 1), Vector2i(10, 1),
		Vector2i(8, 2), Vector2i(10, 2), Vector2i(8, 3), Vector2i(9, 3), Vector2i(10, 3),
		Vector2i(6, 2), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5),
	])
	# Raw volcanic rock mass on the lava sheet (cols 1-7, rows 3-8). The Cinder
	# Deeps fills the deep void with this instead of foundry masonry, so it has
	# to block like a wall. Unpainted by fire_forge.tscn, which only ever touches
	# source 0 at the lava row, so marking it cannot change that map.
	var rock_block: Array = []
	for y in range(3, 9):
		for x in range(1, 8):
			rock_block.append(Vector2i(x, y))
	_mark_collision(ts, 0, rock_block)
	# Source 4 is deliberately collision-free: `forgefloor.gd` only ever paints
	# walkable floor, flat wear decals and see-through catwalk mesh from it. A
	# blocking tile in that bank would land under the player's feet on Ground.
	_save(ts, OUT_DIR + "fire_forge_tileset.tres")


func _build_sewers() -> void:
	var ts := TileSet.new()
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 2)
	ts.set_physics_layer_collision_mask(0, 0)
	# 0 = pixel dungeon, 1 = RF catacombs 32px, 2 = DarkCastle, 3 = DG Set 1,
	# 4 = DG water ripples (overlay only — sparse alpha over solid stone floors)
	_add_atlas(ts, 0, "res://assets/sprites/environment/pixel_dungeon/dungeon_tileset.png", 16, true)
	_add_atlas(ts, 1, "res://assets/sprites/environment/rf_catacombs/mainlevbuild.png", 32, true)
	_add_atlas(ts, 2, "res://assets/sprites/environment/starter_platformer/DarkCastle.png", 16, true)
	_add_atlas(ts, 3, "res://assets/sprites/environment/dg_dungeon/set1.png", 16, true)
	_add_atlas(ts, 4, "res://assets/sprites/environment/dg_dungeon/water.png", 16, true)
	# Wall shell only — do NOT mark (6,1)/(7,1) as floor-safe; those are wall-fill
	# and must never be painted on Ground (that created the sewers "invisible horizontal walls").
	_mark_collision(ts, 0, [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0),
		Vector2i(0, 1), Vector2i(5, 1),
		Vector2i(0, 2), Vector2i(5, 2),
		Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3),
		Vector2i(0, 4), Vector2i(1, 4), Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4),
		Vector2i(6, 0), Vector2i(7, 0), Vector2i(8, 0), Vector2i(9, 0),
		Vector2i(6, 1), Vector2i(7, 1), Vector2i(8, 1), Vector2i(9, 1),
		# Doors — if ever painted on Props they still block; keep collision so they
		# are only safe when used as intentional wall openings (we no longer stamp them on floors).
		Vector2i(6, 6), Vector2i(7, 6),
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


func _setup_row_animations(ts: TileSet, source_id: int, frames: int, speed: float) -> void:
	var src := ts.get_source(source_id) as TileSetAtlasSource
	var rows: int = int(src.texture.get_height() / src.texture_region_size.y)
	for y in rows:
		var origin := Vector2i(0, y)
		# Animation frames occupy the next (frames-1) atlas cells — remove any
		# pre-created tiles there or set_tile_animation_* will fail.
		for x in range(1, frames):
			var cell := Vector2i(x, y)
			if src.has_tile(cell):
				src.remove_tile(cell)
		if not src.has_tile(origin):
			src.create_tile(origin)
		src.set_tile_animation_columns(origin, frames)
		src.set_tile_animation_separation(origin, Vector2i(0, 0))
		src.set_tile_animation_frames_count(origin, frames)
		src.set_tile_animation_speed(origin, speed)
	print("animated source=", source_id, " rows=", rows, " frames=", frames)


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
