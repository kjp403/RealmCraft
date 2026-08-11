extends SceneTree
## Gate for woodland east expansion. Run: godot --headless --path . -s tools/verify_woodland_east_expand.gd

func _initialize() -> void:
	var fails: PackedStringArray = PackedStringArray()
	var txt := FileAccess.get_file_as_string("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn")
	if not txt.contains("aoi_mode = 1"):
		fails.append("aoi_mode GRID not set")
	if not txt.contains("WoodlandEastShore"):
		fails.append("WoodlandEastShore missing")
	if not txt.contains("woodland_east_shore.tscn"):
		fails.append("east shore ext_resource missing")
	if not txt.contains("camera_limit_right = 17072"):
		fails.append("camera_limit_right not expanded (expected 17072 for 5x)")
	if txt.contains("position = Vector2(2460, 1780)"):
		fails.append("BeachVoidEast still at old x=2460")
	if not ResourceLoader.exists("res://source/common/gameplay/maps/maps/woodland/woodland_east_shore.tscn"):
		fails.append("east shore scene missing")
	var cove := FileAccess.get_file_as_string("res://source/common/gameplay/maps/maps/woodland/woodland_deep_cove.tscn")
	if not cove.contains("rim_east = false"):
		fails.append("DeepCove rim_east should be open for east shore join")

	var map: Node = load("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn").instantiate()
	var ground: TileMapLayer = map.find_child("Ground", true, false)
	var walls: TileMapLayer = map.find_child("Walls", true, false)
	var rect: Rect2i = ground.get_used_rect()
	print("ground_rect=", rect)
	if rect.position.x != 0 or rect.position.y != 0:
		fails.append("west origin shifted — existing woodland disturbed")
	# 5× east: origin width 177 + expansion from 181 → ~1066 cells wide
	if rect.size.x < 1000 or rect.size.x > 1200:
		fails.append("east width unexpected for 5x: %s" % rect.size.x)
	# Existing spawn-area ground near entrance still present
	if ground.get_cell_source_id(Vector2i(50, 80)) < 0:
		fails.append("legacy inland ground missing at (50,80)")
	# Expansion samples
	if ground.get_cell_source_id(Vector2i(400, 20)) < 0:
		fails.append("desert band missing ground")
	if ground.get_cell_source_id(Vector2i(400, 50)) < 0:
		fails.append("swamp band missing ground")
	if ground.get_cell_source_id(Vector2i(400, 80)) < 0:
		fails.append("volcano band missing ground")
	# Gate open through seal
	var blocked := 0
	for y in range(34, 46):
		for x in range(177, 181):
			if walls.get_cell_source_id(Vector2i(x, y)) >= 0:
				blocked += 1
	if blocked > 0:
		fails.append("main east gate still blocked (%d wall cells)" % blocked)
	# Fungus portal still present
	if map.find_child("FungusCavePortal", true, false) == null:
		fails.append("FungusCavePortal missing")
	if map.find_child("WoodlandEastShore", true, false) == null:
		fails.append("EastShore node missing at runtime")

	if fails.is_empty():
		print("VERIFY_PASS woodland_east_expand")
		quit(0)
		return
	print("VERIFY_FAIL woodland_east_expand")
	for f in fails:
		print(" - ", f)
	quit(1)
