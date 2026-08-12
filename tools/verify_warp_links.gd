extends SceneTree
## Headless integrity check for every warp link in the game.
## Run: godot --headless --path . -s tools/verify_warp_links.gd
## Expect: VERIFY_PASS
##
## A Warper names its destination as (target_instance, target_id). The id is
## looked up in the DESTINATION map's warper registry at runtime; if it is not
## there the lookup used to fall through to Vector2.ZERO, which on a tiled
## outdoor map is the top-left border wall — players arrived wedged inside it
## and their client hung. Map.get_spawn_position now degrades to the home spawn
## instead, but a link pointing at a non-existent id is still a content bug, so
## catch it here rather than in production.
##
## Scenes are read as text (like the other verify_* tools) so this needs neither
## autoloads nor an import pass.

const MAPS_DIR := "res://source/common/gameplay/maps"
const WARPER_PATH_FRAGMENT := "maps/components/interaction_areas/warper"

var _failures: PackedStringArray = PackedStringArray()
var _scene_by_uid: Dictionary = {}      # uid -> scene path
var _instance_by_uid: Dictionary = {}   # uid -> {name, map_uid}


func _init() -> void:
	var scenes: PackedStringArray = _files_under("res://source", ".tscn")
	for path: String in scenes:
		var uid: String = _header_uid(path)
		if not uid.is_empty():
			_scene_by_uid[uid] = path
	for path: String in _files_under(MAPS_DIR + "/instance", ".tres"):
		_index_instance(path)

	var checked: int = 0
	for path: String in scenes:
		checked += _check_scene(path)

	print("checked %d warp links across %d scenes" % [checked, scenes.size()])
	if _failures.is_empty():
		print("VERIFY_PASS warp_links")
		quit(0)
	else:
		print("VERIFY_FAIL")
		for line: String in _failures:
			print("  - ", line)
		quit(1)


func _check_scene(path: String) -> int:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return 0

	# ext_resource id -> uid, for the Resource entries a target_instance points at.
	var ext: Dictionary = {}
	var res_rx := RegEx.create_from_string(
		'\\[ext_resource type="Resource" uid="(uid://[^"]+)" path="[^"]*" id="([^"]+)"'
	)
	for m: RegExMatch in res_rx.search_all(text):
		ext[m.get_string(2)] = m.get_string(1)

	var target_rx := RegEx.create_from_string(
		'target_instance = ExtResource\\("([^"]+)"\\)'
	)
	var id_rx := RegEx.create_from_string("target_id = (\\d+)")
	var name_rx := RegEx.create_from_string('name="([^"]+)"')

	var count: int = 0
	for block: String in text.split("\n[node "):
		var target: RegExMatch = target_rx.search(block)
		var target_id: RegExMatch = id_rx.search(block)
		if target == null or target_id == null:
			continue
		count += 1
		var node_name: RegExMatch = name_rx.search(block)
		var label: String = "%s :: %s" % [path.get_file(), node_name.get_string(1) if node_name else "?"]

		var uid: String = ext.get(target.get_string(1), "")
		if uid.is_empty() or not _instance_by_uid.has(uid):
			continue # target_instance authored without a uid — nothing to resolve against
		var entry: Dictionary = _instance_by_uid[uid]
		var dest: String = _scene_by_uid.get(entry["map_uid"], "")
		if dest.is_empty():
			_failures.append("%s -> %s: map_path %s resolves to no scene"
				% [label, entry["name"], entry["map_uid"]])
			continue
		var ids: Dictionary = _warper_ids(dest)
		if not ids.has(int(target_id.get_string(1))):
			_failures.append("%s -> %s (%s): target_id %s has no warper (map has %s)"
				% [label, entry["name"], dest.get_file(), target_id.get_string(1), ids.keys()])
	return count


## Every warper id registered by [param scene]. A warper/portal instance with no
## explicit warper_id keeps the export default of 0, which is a real id.
func _warper_ids(scene: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(scene)
	var ids: Dictionary = {}
	if not text.contains(WARPER_PATH_FRAGMENT):
		return ids

	# ext_resource ids of the warper/portal scenes, so we only count real warpers.
	var warper_ext: Dictionary = {}
	var scene_rx := RegEx.create_from_string(
		'\\[ext_resource type="PackedScene"[^\\]]*path="res://[^"]*%s[^"]*"[^\\]]*id="([^"]+)"'
		% WARPER_PATH_FRAGMENT
	)
	for m: RegExMatch in scene_rx.search_all(text):
		warper_ext[m.get_string(1)] = true

	var id_rx := RegEx.create_from_string("\nwarper_id = (\\d+)")
	for block: String in text.split("\n[node "):
		var header: String = block.split("\n")[0]
		var is_warper: bool = false
		for ext_id: String in warper_ext:
			if header.contains('instance=ExtResource("%s")' % ext_id):
				is_warper = true
				break
		if not is_warper:
			continue
		var m: RegExMatch = id_rx.search(block)
		ids[int(m.get_string(1)) if m != null else 0] = true
	return ids


func _index_instance(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	var uid: RegExMatch = RegEx.create_from_string('\\[gd_resource[^\\]]*uid="(uid://[^"]+)"').search(text)
	var map_uid: RegExMatch = RegEx.create_from_string('map_path = "(uid://[^"]+)"').search(text)
	if uid == null or map_uid == null:
		return
	var name_match: RegExMatch = RegEx.create_from_string('instance_name = &"([^"]+)"').search(text)
	_instance_by_uid[uid.get_string(1)] = {
		"name": name_match.get_string(1) if name_match else path.get_file(),
		"map_uid": map_uid.get_string(1),
	}


func _header_uid(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var m: RegExMatch = RegEx.create_from_string('uid="(uid://[^"]+)"').search(file.get_line())
	return m.get_string(1) if m != null else ""


func _files_under(root: String, suffix: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var pending: PackedStringArray = PackedStringArray([root])
	while not pending.is_empty():
		var dir_path: String = pending[-1]
		pending.remove_at(pending.size() - 1)
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			continue
		for name: String in dir.get_directories():
			pending.append(dir_path.path_join(name))
		for name: String in dir.get_files():
			if name.ends_with(suffix):
				out.append(dir_path.path_join(name))
	return out
