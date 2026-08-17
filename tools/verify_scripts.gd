@tool
extends Node
## Parse gate: load EVERY .gd under source/ and report any that fail.
##
## `--headless --import` does NOT catch this: it imports resources and only
## compiles scripts that something actually loads, so a parse error in a menu
## script nothing instantiates at import time sails straight through. A GDScript
## parse error makes the scene instantiate WITHOUT its script, which for a
## full-rect UI Control means an invisible panel that pins ClientState.menu_open
## and freezes the player. That shipped as Boss Hunt's contract board.
##
## Run: godot --headless --path . tools/verify_scripts.tscn

const ROOT: String = "res://source/"


func _ready() -> void:
	var failures: PackedStringArray = PackedStringArray()
	var count: int = 0
	for path: String in _all_scripts(ROOT):
		count += 1
		var res: Resource = ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE)
		if res == null:
			failures.append(path)
	print("scanned %d scripts" % count)
	if failures.is_empty():
		print("VERIFY_PASS")
	else:
		for f: String in failures:
			printerr("FAIL: %s" % f)
		printerr("VERIFY_FAIL (%d)" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)


func _all_scripts(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_all_scripts(full))
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return out
