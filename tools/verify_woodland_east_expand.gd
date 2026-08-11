extends SceneTree
## Gate for contiguous Goblin Woodlands East expansion.
## Run: godot --headless --path . -s tools/verify_woodland_east_expand.gd

func _initialize() -> void:
	var fails: PackedStringArray = PackedStringArray()

	# Never touch these biome maps.
	for forbidden in [
		"res://source/common/gameplay/maps/maps/desert/desert.tscn",
		"res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
		"res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
	]:
		if not ResourceLoader.exists(forbidden):
			fails.append("missing reference biome (unexpected): %s" % forbidden)

	var txt := FileAccess.get_file_as_string("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn")
	if not txt.contains("WoodlandEastPortal"):
		fails.append("WoodlandEastPortal missing")
	if not txt.contains("WoodlandEastLanding"):
		fails.append("WoodlandEastLanding missing")
	if not txt.contains("woodland_east.tres"):
		fails.append("woodland_east instance ext_resource missing")
	if txt.contains("woodland_east_wilds.tres"):
		fails.append("old east_wilds hub still referenced")
	if txt.contains("EastWildsPortal"):
		fails.append("old EastWildsPortal still present")
	if not txt.contains("WoodlandEastShore"):
		fails.append("WoodlandEastShore missing")
	if txt.contains("BiomeLandmarks"):
		fails.append("BiomeLandmarks stub labels still present")
	if txt.contains("camera_limit_right = 17072"):
		fails.append("camera still at stripe mega-expansion 17072")

	var map: Node = load("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn").instantiate()
	var ground: TileMapLayer = map.find_child("Ground", true, false)
	var walls: TileMapLayer = map.find_child("Walls", true, false)
	var rect: Rect2i = ground.get_used_rect()
	print("ground_rect=", rect)
	if rect.position.x != 0 or rect.position.y != 0:
		fails.append("west origin shifted")
	if rect.size.x >= 250:
		fails.append("stripe mega-expansion still present (ground width=%d, want <250)" % rect.size.x)
	if rect.size.x < 200:
		fails.append("east grove missing (ground width=%d)" % rect.size.x)
	if ground.get_cell_source_id(Vector2i(50, 80)) < 0:
		fails.append("legacy inland ground missing")

	var blocked := 0
	for y in range(34, 46):
		for x in range(177, 181):
			if walls.get_cell_source_id(Vector2i(x, y)) >= 0:
				blocked += 1
	if blocked > 0:
		fails.append("main east gate blocked (%d)" % blocked)

	var portal := map.find_child("WoodlandEastPortal", true, false)
	if portal == null:
		fails.append("WoodlandEastPortal node missing")
	elif int(portal.get("warper_id")) != 59 or int(portal.get("target_id")) != 60:
		fails.append("WoodlandEastPortal ids want warper=59 target=60 got %s/%s" % [
			str(portal.get("warper_id")), str(portal.get("target_id"))
		])
	var landing := map.find_child("WoodlandEastLanding", true, false)
	if landing == null:
		fails.append("WoodlandEastLanding node missing")
	elif int(landing.get("warper_id")) != 60:
		fails.append("WoodlandEastLanding warper_id want 60")

	# Contiguous expansion map — one outdoor wing, not portal-hub biomes.
	var east_path := "res://source/common/gameplay/maps/maps/woodland/woodland_east.tscn"
	if not ResourceLoader.exists(east_path):
		fails.append("woodland_east map missing")
	else:
		var east: Node = load(east_path).instantiate()
		print("loaded woodland_east root=", east.name)
		for layer_name in ["GroundWood", "GroundDunes", "GroundWetlands", "GroundAsh", "Backdrop"]:
			var layer: TileMapLayer = east.find_child(layer_name, true, false)
			if layer == null:
				fails.append("woodland_east missing %s" % layer_name)
				continue
			var gr: Rect2i = layer.get_used_rect()
			print(layer_name, " used=", gr, " cells=", layer.get_used_cells().size())
			if layer_name != "Backdrop" and layer.get_used_cells().size() < 800:
				fails.append("%s too sparse: %d" % [layer_name, layer.get_used_cells().size()])
		var entrance := east.find_child("Entrance", true, false)
		var back := east.find_child("WoodlandPortal", true, false)
		if entrance == null or int(entrance.get("warper_id")) != 60:
			fails.append("woodland_east Entrance warper_id want 60")
		if back == null or int(back.get("warper_id")) != 160 or int(back.get("target_id")) != 60:
			fails.append("woodland_east WoodlandPortal ids want 160→60")
		# No deep-links into Desert / Sewers / Fire Forge instances.
		var scene_txt := FileAccess.get_file_as_string(east_path)
		for bad in ["desert.tres", "sewers.tres", "fire_forge.tres", "east_dunes", "east_wetlands", "east_ash"]:
			if scene_txt.contains(bad):
				fails.append("woodland_east still references %s" % bad)
		# Camera covers the outdoor wing
		if not scene_txt.contains("camera_limit_right = 3856"):
			# allow nearby sizes from SURFACE_S
			var cam_ok := false
			for n in range(3500, 4500):
				if scene_txt.contains("camera_limit_right = %d" % n):
					cam_ok = true
					break
			if not cam_ok:
				fails.append("woodland_east camera_limit_right unexpected")
		east.free()

	# Old hub/stub maps must not be the travel targets anymore.
	for stale in [
		"res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland_east_wilds.tres",
		"res://source/common/gameplay/maps/instance/instance_collection/biomes/east_dunes.tres",
		"res://source/common/gameplay/maps/instance/instance_collection/biomes/east_wetlands.tres",
		"res://source/common/gameplay/maps/instance/instance_collection/biomes/east_ash_fields.tres",
	]:
		if ResourceLoader.exists(stale):
			fails.append("stale instance still present (remove): %s" % stale)

	var tres := "res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland_east.tres"
	if not ResourceLoader.exists(tres):
		fails.append("missing instance: %s" % tres)
	else:
		var ir = load(tres)
		if ir == null or String(ir.instance_name) != "woodland_east":
			fails.append("bad woodland_east instance_name")
		elif not ResourceLoader.exists(ir.map_path):
			fails.append("woodland_east map_path missing: %s" % ir.map_path)

	map.free()
	if fails.is_empty():
		print("VERIFY_PASS woodland_east_expand")
		quit(0)
		return
	print("VERIFY_FAIL woodland_east_expand")
	for f in fails:
		print(" - ", f)
	quit(1)
