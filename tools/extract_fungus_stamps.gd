extends SceneTree
## Extract several authored Fungus wall+ground windows for stamping.

func _initialize() -> void:
	var map = (load("res://source/common/gameplay/maps/maps/fungus_cave/fungus_cave.tscn") as PackedScene).instantiate()
	var walls: TileMapLayer = map.get_node("Tiles/Walls")
	var ground: TileMapLayer = map.get_node("Tiles/Ground")
	var jobs: Array = [
		{"name": "wide", "ww": 28, "hh": 14, "gmin": 120, "gmax": 320, "wmin": 40},
		{"name": "tall", "ww": 16, "hh": 18, "gmin": 90, "gmax": 250, "wmin": 35},
		{"name": "square", "ww": 18, "hh": 14, "gmin": 80, "gmax": 220, "wmin": 30},
	]
	DirAccess.make_dir_recursive_absolute("res://tools/stamps")
	for job in jobs:
		var best_score := -1
		var best := Vector2i(-999, -999)
		var WW: int = job["ww"]
		var HH: int = job["hh"]
		for y in range(-75, 5):
			for x in range(-35, 45):
				var gcount := 0
				var wcount := 0
				var border_w := 0
				for oy in range(HH):
					for ox in range(WW):
						var c := Vector2i(x + ox, y + oy)
						var on_border := ox == 0 or oy == 0 or ox == WW - 1 or oy == HH - 1
						if ground.get_cell_source_id(c) >= 0:
							gcount += 1
						if walls.get_cell_source_id(c) >= 0:
							wcount += 1
							if on_border:
								border_w += 1
				if gcount < int(job["gmin"]) or gcount > int(job["gmax"]):
					continue
				if wcount < int(job["wmin"]):
					continue
				var score: int = wcount * 3 + border_w * 5 + gcount
				if score > best_score:
					best_score = score
					best = Vector2i(x, y)
		print(job["name"], " origin=", best, " score=", best_score)
		var path := "res://tools/stamps/fungus_%s.txt" % String(job["name"])
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_line("SIZE %d %d" % [WW, HH])
		f.store_line("ORIGIN %d %d" % [best.x, best.y])
		for oy in range(HH):
			for ox in range(WW):
				var c2 := best + Vector2i(ox, oy)
				if ground.get_cell_source_id(c2) >= 0:
					var ga := ground.get_cell_atlas_coords(c2)
					f.store_line("G %d %d %d %d" % [ox, oy, ga.x, ga.y])
				if walls.get_cell_source_id(c2) >= 0:
					var wa := walls.get_cell_atlas_coords(c2)
					f.store_line("W %d %d %d %d" % [ox, oy, wa.x, wa.y])
		f.close()
		print(" wrote ", path)
	quit(0)
