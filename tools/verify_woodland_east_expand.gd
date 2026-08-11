extends SceneTree
## Gate for woodland east wilds expansion (hub + 3 biomes, no stripe mega-fill).
## Run: godot --headless --path . -s tools/verify_woodland_east_expand.gd

func _initialize() -> void:
	var fails: PackedStringArray = PackedStringArray()

	var txt := FileAccess.get_file_as_string("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn")
	if not txt.contains("EastWildsPortal"):
		fails.append("EastWildsPortal missing")
	if not txt.contains("EastWildsLanding"):
		fails.append("EastWildsLanding missing")
	if not txt.contains("woodland_east_wilds.tres"):
		fails.append("east wilds instance ext_resource missing")
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
	# Short transition grove only — not the 5x stripe fill (~1000+ wide).
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

	var portal := map.find_child("EastWildsPortal", true, false)
	if portal == null:
		fails.append("EastWildsPortal node missing")
	elif int(portal.get("warper_id")) != 59 or int(portal.get("target_id")) != 60:
		fails.append("EastWildsPortal ids want warper=59 target=60 got %s/%s" % [
			str(portal.get("warper_id")), str(portal.get("target_id"))
		])
	var landing := map.find_child("EastWildsLanding", true, false)
	if landing == null:
		fails.append("EastWildsLanding node missing")
	elif int(landing.get("warper_id")) != 60:
		fails.append("EastWildsLanding warper_id want 60")

	var maps := {
		"hub": "res://source/common/gameplay/maps/maps/woodland/woodland_east_wilds.tscn",
		"dunes": "res://source/common/gameplay/maps/maps/woodland/east_dunes.tscn",
		"wetlands": "res://source/common/gameplay/maps/maps/woodland/east_wetlands.tscn",
		"ash": "res://source/common/gameplay/maps/maps/woodland/east_ash_fields.tscn",
	}
	var want_ids := {
		"hub": {"Entrance": 60, "WoodlandPortal": 160, "DunesPortal": 71, "WetlandsPortal": 72, "AshPortal": 73},
		"dunes": {"Entrance": 61, "Portal": 161},
		"wetlands": {"Entrance": 62, "Portal": 162},
		"ash": {"Entrance": 63, "Portal": 163},
	}
	for key in maps.keys():
		var path: String = maps[key]
		if not ResourceLoader.exists(path):
			fails.append("%s map missing: %s" % [key, path])
			continue
		var scene: Node = load(path).instantiate()
		print("loaded ", key, " root=", scene.name)
		var g: TileMapLayer = scene.find_child("Ground", true, false)
		if g == null:
			fails.append("%s missing Ground" % key)
		else:
			var gr: Rect2i = g.get_used_rect()
			print(key, " ground_rect=", gr)
			if gr.size.x >= 250:
				fails.append("%s ground too wide (stripe?): %d" % [key, gr.size.x])
			if gr.size.x < 40 or gr.size.y < 40:
				fails.append("%s ground too small: %s" % [key, gr])
		for node_name in want_ids[key].keys():
			var n: Node = scene.find_child(node_name, true, false)
			if n == null:
				fails.append("%s missing %s" % [key, node_name])
				continue
			var wid: int = int(n.get("warper_id"))
			var expect: int = int(want_ids[key][node_name])
			if wid != expect:
				fails.append("%s.%s warper_id=%d want %d" % [key, node_name, wid, expect])
		if key != "hub":
			var p: Node = scene.find_child("Portal", true, false)
			if p and int(p.get("target_id")) != 60:
				fails.append("%s Portal target_id want 60" % key)
		scene.free()

	var tres := [
		"res://source/common/gameplay/maps/instance/instance_collection/biomes/woodland_east_wilds.tres",
		"res://source/common/gameplay/maps/instance/instance_collection/biomes/east_dunes.tres",
		"res://source/common/gameplay/maps/instance/instance_collection/biomes/east_wetlands.tres",
		"res://source/common/gameplay/maps/instance/instance_collection/biomes/east_ash_fields.tres",
	]
	for tpath in tres:
		if not ResourceLoader.exists(tpath):
			fails.append("missing instance: %s" % tpath)
			continue
		var ir = load(tpath)
		if ir == null or String(ir.instance_name).is_empty():
			fails.append("bad instance resource: %s" % tpath)
		elif not ResourceLoader.exists(ir.map_path):
			fails.append("%s map_path missing: %s" % [tpath, ir.map_path])

	map.free()
	if fails.is_empty():
		print("VERIFY_PASS woodland_east_expand")
		quit(0)
		return
	print("VERIFY_FAIL woodland_east_expand")
	for f in fails:
		print(" - ", f)
	quit(1)
