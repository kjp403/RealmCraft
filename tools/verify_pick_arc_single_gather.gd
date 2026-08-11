extends SceneTree
## Verifies PickArc gathers at most one MineableNode per swing (nearest wins),
## and that Mining Cave has a well-spaced mithril field.
## Text-only so it does not depend on autoload compile health.
## Run: godot --headless --path . -s tools/verify_pick_arc_single_gather.gd

const CAVE := "res://source/common/gameplay/maps/maps/mining_cave/mining_cave.tscn"
const PICK := "res://source/common/gameplay/combat/pick_arc.gd"


func _initialize() -> void:
	var failures: PackedStringArray = PackedStringArray()

	var src := FileAccess.get_file_as_string(PICK)
	if not src.contains("_apply_nearest_gather") or not src.contains("_gather_applied"):
		failures.append("pick_arc.gd missing single-gather nearest selection")
	# Count call sites only (ignore comments mentioning the method name).
	var call_count := 0
	for line: String in src.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("#"):
			continue
		if "register_gather_hit(" in trimmed:
			call_count += 1
	if call_count != 1:
		failures.append(
			"pick_arc.gd should call register_gather_hit exactly once (got %d)" % call_count
		)

	var cave := FileAccess.get_file_as_string(CAVE)
	var mithril_pos: Array[Vector2] = []
	var lines := cave.split("\n")
	var i := 0
	while i < lines.size():
		var line: String = lines[i]
		if line.begins_with('[node name="MithrilVein') and 'parent="MineableNodes"' in line:
			var pos := Vector2.ZERO
			var found := false
			for j in range(i + 1, mini(i + 8, lines.size())):
				var pl: String = lines[j]
				if pl.begins_with("[node "):
					break
				if pl.begins_with("position = Vector2("):
					var inner := pl.trim_prefix("position = Vector2(").trim_suffix(")")
					var parts := inner.split(",")
					if parts.size() == 2:
						pos = Vector2(parts[0].strip_edges().to_float(), parts[1].strip_edges().to_float())
						found = true
					break
			if found:
				mithril_pos.append(pos)
			else:
				failures.append("mithril node missing position near line %d" % (i + 1))
		i += 1

	if mithril_pos.size() < 12:
		failures.append("expected >= 12 mithril veins, got %d" % mithril_pos.size())
	var min_sep: float = INF
	for a in mithril_pos.size():
		for b in range(a + 1, mithril_pos.size()):
			min_sep = minf(min_sep, mithril_pos[a].distance_to(mithril_pos[b]))
	if min_sep < 96.0:
		failures.append("mithril veins too close: min_sep=%.1f (want >= 96)" % min_sep)
	print("mithril_count=", mithril_pos.size(), " min_sep=", snappedf(min_sep, 0.1))

	if failures.is_empty():
		print("VERIFY_PASS")
		quit(0)
	else:
		for f: String in failures:
			push_error(f)
		print("VERIFY_FAIL count=", failures.size())
		quit(1)
