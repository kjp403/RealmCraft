extends SceneTree
## Gate for contiguous Goblin Woodlands East (woodland tileset only).
## Run: godot --headless --path . -s tools/verify_woodland_east_expand.gd

func _initialize() -> void:
	var fails: PackedStringArray = PackedStringArray()

	var txt := FileAccess.get_file_as_string("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn")
	if not txt.contains("WoodlandEastPortal"):
		fails.append("WoodlandEastPortal missing")
	if not txt.contains("woodland_east.tres"):
		fails.append("woodland_east instance missing from woodland")
	if txt.contains("desert_tileset") or txt.contains("sewers_tileset") or txt.contains("fire_forge_tileset"):
		fails.append("woodland_tiles must not reference foreign biome tilesets")
	if txt.contains("camera_limit_right = 17072"):
		fails.append("stripe mega camera still present")

	var map: Node = load("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn").instantiate()
	var ground: TileMapLayer = map.find_child("Ground", true, false)
	var walls: TileMapLayer = map.find_child("Walls", true, false)
	var rect: Rect2i = ground.get_used_rect()
	print("woodland ground_rect=", rect)
	if rect.size.x >= 250:
		fails.append("stripe mega-expansion still present (width=%d)" % rect.size.x)
	if rect.size.x < 200:
		fails.append("east grove missing (width=%d)" % rect.size.x)
	var blocked := 0
	for y in range(34, 46):
		for x in range(177, 181):
			if walls.get_cell_source_id(Vector2i(x, y)) >= 0:
				blocked += 1
	if blocked > 0:
		fails.append("east gate blocked (%d)" % blocked)

	var portal := map.find_child("WoodlandEastPortal", true, false)
	if portal == null:
		fails.append("WoodlandEastPortal missing")
	elif int(portal.get("warper_id")) != 59 or int(portal.get("target_id")) != 60:
		fails.append("WoodlandEastPortal bad ids")

	var east_path := "res://source/common/gameplay/maps/maps/woodland/woodland_east.tscn"
	if not ResourceLoader.exists(east_path):
		fails.append("woodland_east.tscn missing")
	else:
		var east_txt := FileAccess.get_file_as_string(east_path)
		# HARD RULE: woodland art only
		for bad in ["desert_tileset", "sewers_tileset", "fire_forge_tileset", "maps/desert/", "maps/sewers/", "maps/fire_forge/"]:
			if east_txt.contains(bad):
				fails.append("woodland_east uses forbidden art/path: %s" % bad)
		if not east_txt.contains("woodland_tileset.tres"):
			fails.append("woodland_east must use woodland_tileset.tres")
		var east: Node = load(east_path).instantiate()
		var eg: TileMapLayer = east.find_child("Ground", true, false)
		if eg == null:
			fails.append("woodland_east missing Ground")
		else:
			var er: Rect2i = eg.get_used_rect()
			print("east ground_rect=", er, " cells=", eg.get_used_cells().size())
			if eg.get_used_cells().size() < 4000:
				fails.append("east ground too sparse: %d" % eg.get_used_cells().size())
			if er.size.x < 120 or er.size.y < 100:
				fails.append("east ground too small: %s" % er)
			# Must include woodland water + sand variety (not foreign tilesets)
			var has_water := false
			var has_sandish := false
			for c in eg.get_used_cells():
				if eg.get_cell_source_id(c) == 8:
					has_water = true
				var a: Vector2i = eg.get_cell_atlas_coords(c)
				if eg.get_cell_source_id(c) == 0 and a.x >= 10 and a.x <= 14:
					has_sandish = true
			if not has_water:
				fails.append("east missing woodland water ponds")
			if not has_sandish:
				fails.append("east missing woodland sand clearings")
		var decor: TileMapLayer = east.find_child("Decor", true, false)
		if decor == null or decor.get_used_cells().size() < 200:
			fails.append("east tree decor too sparse")
		else:
			print("east trees/decor=", decor.get_used_cells().size())
		var entrance := east.find_child("Entrance", true, false)
		var back := east.find_child("WoodlandPortal", true, false)
		if entrance == null or int(entrance.get("warper_id")) != 60:
			fails.append("east Entrance bad")
		if back == null or int(back.get("warper_id")) != 160:
			fails.append("east WoodlandPortal bad")
		east.free()

	for stale in ["east_dunes.tres", "east_wetlands.tres", "east_ash_fields.tres", "woodland_east_wilds.tres"]:
		var p := "res://source/common/gameplay/maps/instance/instance_collection/biomes/%s" % stale
		if ResourceLoader.exists(p):
			fails.append("stale instance still present: %s" % stale)

	map.free()
	if fails.is_empty():
		print("VERIFY_PASS woodland_east_expand")
		quit(0)
		return
	print("VERIFY_FAIL woodland_east_expand")
	for f in fails:
		print(" - ", f)
	quit(1)
