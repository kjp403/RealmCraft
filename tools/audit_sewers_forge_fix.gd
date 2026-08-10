extends SceneTree
## One-shot QA for sewers blockers / doors + forge animated lava tiles.


func _initialize() -> void:
	var ts: TileSet = load("res://source/common/gameplay/maps/tilesets/sewers_tileset.tres")
	var src := ts.get_source(0) as TileSetAtlasSource
	for c in [Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(6, 1), Vector2i(7, 1)]:
		var td := src.get_tile_data(c, 0)
		var n := 0 if td == null else td.get_collision_polygons_count(0)
		print("sewers src0 ", c, " coll=", n)

	var fts: TileSet = load("res://source/common/gameplay/maps/tilesets/fire_forge_tileset.tres")
	var asrc := fts.get_source(1) as TileSetAtlasSource
	print("forge anim frames row0=", asrc.get_tile_animation_frames_count(Vector2i(0, 0)))
	print("forge anim frames row1=", asrc.get_tile_animation_frames_count(Vector2i(0, 1)))
	print("forge sources=", fts.get_source_count())
	var main := fts.get_source(0) as TileSetAtlasSource
	print("forge main atlas tiles=", main.get_tiles_count(), " region=", main.texture_region_size)

	var scene: PackedScene = load("res://source/common/gameplay/maps/maps/sewers/sewers.tscn")
	var map: Node = scene.instantiate()
	var ground: TileMapLayer = map.get_node("Tiles/Ground")
	var props: TileMapLayer = map.get_node("Tiles/Props")
	var bad := 0
	var doors := 0
	for cell: Vector2i in ground.get_used_cells():
		if ground.get_cell_source_id(cell) != 0:
			continue
		var atlas: Vector2i = ground.get_cell_atlas_coords(cell)
		if atlas.x >= 6 and atlas.y <= 1:
			bad += 1
	for cell2: Vector2i in props.get_used_cells():
		var sid := props.get_cell_source_id(cell2)
		var ac: Vector2i = props.get_cell_atlas_coords(cell2)
		var is_door := false
		# Pixel-dungeon door pair
		if sid == 0 and ac in [Vector2i(6, 6), Vector2i(7, 6)]:
			is_door = true
		# Chests / hatches that read as "tiny doors" on open floor
		if sid == 0 and ac in [Vector2i(0, 8), Vector2i(1, 8)]:
			is_door = true
		# DarkCastle door / manhole tiles
		if sid == 2 and ac in [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)]:
			is_door = true
		if is_door:
			doors += 1
			print("door_prop cell=", cell2, " sid=", sid, " atlas=", ac)
	print("sewers ground wallfill_on_floor=", bad, " tiny_doors=", doors)
	map.free()

	var forge_scene: PackedScene = load("res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn")
	var forge: Node = forge_scene.instantiate()
	var fg: TileMapLayer = forge.get_node("Tiles/Ground")
	var legacy := 0
	var anim_lava := 0
	var solid_lava := 0
	for cell3: Vector2i in fg.get_used_cells():
		var sid2 := fg.get_cell_source_id(cell3)
		var ac3: Vector2i = fg.get_cell_atlas_coords(cell3)
		if sid2 == 1:
			anim_lava += 1
		elif sid2 == 0 and ac3 == Vector2i(1, 11):
			solid_lava += 1
		elif sid2 != 0 and sid2 != 2 and sid2 != 3:
			legacy += 1
	print("forge ground anim_lava_cells=", anim_lava, " solid_lava=", solid_lava, " unexpected_sources=", legacy)
	forge.free()

	var ok := (
		bad == 0
		and doors == 0
		and main.texture_region_size == Vector2i(16, 16)
		and (anim_lava > 0 or solid_lava > 0)
		and legacy == 0
	)
	if ok:
		print("SEWERS_FORGE_FIX_AUDIT_PASS")
		quit(0)
		return
	print("SEWERS_FORGE_FIX_AUDIT_FAIL")
	quit(1)
