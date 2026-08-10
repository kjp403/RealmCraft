extends SceneTree
## Surgically rewrite MineableNodes positions in mining_cave.tscn to the
## wall-aligned plan (does not rebuild rooms/walls/props).
## Run: godot --headless --path . -s tools/reposition_mining_ores.gd

const MAP_PATH := "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"

## Same plan as tools/build_mining_cave.gd _place_ores().
const PLAN: Array = [
	{"name": "CopperVein1", "pos": Vector2(248, 264)},
	{"name": "CopperVein2", "pos": Vector2(296, 296)},
	{"name": "TinVein1", "pos": Vector2(296, 376)},
	{"name": "CopperVein3", "pos": Vector2(408, 88)},
	{"name": "CopperVein4", "pos": Vector2(472, 88)},
	{"name": "CopperVein5", "pos": Vector2(520, 88)},
	{"name": "TinVein2", "pos": Vector2(584, 120)},
	{"name": "TinVein3", "pos": Vector2(376, 280)},
	{"name": "TinVein4", "pos": Vector2(600, 296)},
	{"name": "IronVein1", "pos": Vector2(616, 392)},
	{"name": "IronVein2", "pos": Vector2(808, 408)},
	{"name": "IronVein3", "pos": Vector2(840, 456)},
	{"name": "IronVein4", "pos": Vector2(840, 536)},
	{"name": "CoalVein1", "pos": Vector2(888, 216)},
	{"name": "CoalVein2", "pos": Vector2(1032, 248)},
	{"name": "CoalVein3", "pos": Vector2(1096, 280)},
	{"name": "CoalVein4", "pos": Vector2(1112, 392)},
	{"name": "CoalVein5", "pos": Vector2(1192, 376)},
]


func _initialize() -> void:
	var abs_path := ProjectSettings.globalize_path(MAP_PATH)
	var text := FileAccess.get_file_as_string(abs_path)
	if text.is_empty():
		push_error("failed to read mining_cave")
		quit(1)
		return

	var updated := 0
	for entry in PLAN:
		var name: String = entry["name"]
		var pos: Vector2 = entry["pos"]
		var re := RegEx.new()
		re.compile(
			"(\\[node name=\"%s\" parent=\"MineableNodes\"[^\\]]*\\]\\n(?:[^\\[]|\\n)*?position = Vector2\\()[^)]+(\\\\))"
			% name
		)
		# Simpler line-based replace: find the node block and replace its position line.
		var marker := '[node name="%s" parent="MineableNodes"' % name
		var idx := text.find(marker)
		if idx < 0:
			push_error("missing node %s" % name)
			quit(1)
			return
		var pos_key := "position = Vector2("
		var pos_idx := text.find(pos_key, idx)
		if pos_idx < 0 or pos_idx > idx + 250:
			push_error("position not found for %s" % name)
			quit(1)
			return
		var start := pos_idx + pos_key.length()
		var end := text.find(")", start)
		var new_pos := "%s, %s" % [str(pos.x), str(pos.y)]
		text = text.substr(0, start) + new_pos + text.substr(end)
		updated += 1
		print("set ", name, " -> ", pos)

	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("updated=", updated, " wrote=", abs_path)
	quit(0 if updated == PLAN.size() else 1)
