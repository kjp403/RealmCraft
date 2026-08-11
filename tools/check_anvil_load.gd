extends SceneTree
func _init() -> void:
	var s = load("res://source/common/gameplay/crafting/resources/anvil.tres")
	if s == null:
		print("VERIFY_FAIL anvil null")
		quit(1)
		return
	print("VERIFY_PASS name=", s.station_name, " recipes=", s.recipes.size())
	var bad := 0
	for r in s.recipes:
		if r == null or r.output_item == null:
			bad += 1
	print("bad_outputs=", bad)
	quit(0 if bad == 0 else 1)
