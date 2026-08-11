extends SceneTree
## Contiguous Goblin Woodlands East (on woodland_tiles, woodland art only).

func _initialize() -> void:
	var fails: PackedStringArray = PackedStringArray()
	var txt := FileAccess.get_file_as_string("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn")
	if txt.contains("desert_tileset") or txt.contains("sewers_tileset") or txt.contains("fire_forge_tileset"):
		fails.append("foreign biome tileset on woodland")
	if txt.contains("camera_limit_right = 17072"):
		fails.append("stripe mega camera")
	if txt.contains("WoodlandEastPortal") or txt.contains("EastWildsPortal"):
		fails.append("portal hub still present — east must be walkable contiguous")
	if not txt.contains("EastWingLandmarks"):
		fails.append("EastWingLandmarks missing")
	if not txt.contains("WoodlandEastShore"):
		fails.append("WoodlandEastShore missing")

	var map: Node = load("res://source/common/gameplay/maps/maps/woodland/woodland_tiles.tscn").instantiate()
	var ground: TileMapLayer = map.find_child("Ground", true, false)
	var walls: TileMapLayer = map.find_child("Walls", true, false)
	var decor: TileMapLayer = map.find_child("Decor", true, false)
	var rect: Rect2i = ground.get_used_rect()
	print("ground_rect=", rect)
	if rect.position.x != 0:
		fails.append("west origin shifted")
	if rect.size.x < 300:
		fails.append("east wing too short (width=%d)" % rect.size.x)
	if rect.size.x > 450:
		fails.append("looks like stripe mega-fill (width=%d)" % rect.size.x)
	# No distant stripe columns
	var far := 0
	for y in range(0, 100):
		if ground.get_cell_source_id(Vector2i(500, y)) >= 0:
			far += 1
	if far > 0:
		fails.append("stripe remnants at x=500")

	var blocked := 0
	for y in range(34, 46):
		for x in range(177, 181):
			if walls.get_cell_source_id(Vector2i(x, y)) >= 0:
				blocked += 1
	if blocked > 0:
		fails.append("east gate blocked")

	# Contiguous walk from gate into wing
	if ground.get_cell_source_id(Vector2i(182, 40)) < 0:
		fails.append("no floor just east of gate")
	if ground.get_cell_source_id(Vector2i(212, 42)) < 0:
		fails.append("crossroads missing")

	# Floor language: grass must dominate east wing
	var grass := 0
	var dirt := 0
	var sand := 0
	var stone := 0
	var water := 0
	var other := 0
	for c in ground.get_used_cells():
		if c.x < 181:
			continue
		var sid := ground.get_cell_source_id(c)
		var a := ground.get_cell_atlas_coords(c)
		if sid == 8:
			water += 1
		elif a.y == 10 and a.x >= 1 and a.x <= 3:
			grass += 1
		elif a.x >= 10 and a.x <= 14:
			sand += 1
		elif a.x >= 16:
			stone += 1
		elif a.x >= 5 and a.x <= 8:
			dirt += 1
		else:
			other += 1
	print("east mix grass=", grass, " dirt=", dirt, " sand=", sand, " stone=", stone, " water=", water, " other=", other)
	if grass < dirt * 2:
		fails.append("grass does not dominate east wing")
	if water < 80:
		fails.append("not enough ponds")
	if sand < 200:
		fails.append("beach too small")
	if stone < 50:
		fails.append("stone accents missing")
	if grass < int(float(dirt + sand + stone + water) * 1.5):
		fails.append("grass must dominate east wing vs other materials")
	var decor_n := decor.get_used_cells().size()
	var east_decor := 0
	for c in decor.get_used_cells():
		if c.x >= 181:
			east_decor += 1
	print("east_trees=", east_decor)
	if east_decor > 220:
		fails.append("too many trees choking walkability (%d)" % east_decor)
	if east_decor < 40:
		fails.append("east wing too barren (%d trees)" % east_decor)
	# Paths must be tree-free near crossroads / gate
	for c in [Vector2i(182, 40), Vector2i(212, 42), Vector2i(230, 16), Vector2i(300, 42)]:
		if decor.get_cell_source_id(c) >= 0:
			fails.append("tree on critical path cell %s" % c)

	# Desert/Sewers/Fire Forge maps must exist untouched (sanity)
	for p in [
		"res://source/common/gameplay/maps/maps/desert/desert.tscn",
		"res://source/common/gameplay/maps/maps/sewers/sewers.tscn",
		"res://source/common/gameplay/maps/maps/fire_forge/fire_forge.tscn",
	]:
		if not ResourceLoader.exists(p):
			fails.append("missing biome map %s" % p)

	map.free()
	if fails.is_empty():
		print("VERIFY_PASS woodland_east_expand")
		quit(0)
		return
	print("VERIFY_FAIL woodland_east_expand")
	for f in fails:
		print(" - ", f)
	quit(1)
