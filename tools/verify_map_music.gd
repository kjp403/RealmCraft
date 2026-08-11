extends SceneTree
## Verify every map's music rotation: each map still resolves a base track, its
## music_playlist entries all load, and no map lists the same .ogg twice.
##   godot --headless --path . -s tools/verify_map_music.gd


func _initialize() -> void:
	var scenes: PackedStringArray = _find_scenes("res://source/common/gameplay/maps/maps")
	assert(not scenes.is_empty(), "no map scenes found")

	var maps: int = 0
	var rotating: int = 0
	var used: Dictionary = {}
	for scene_path: String in scenes:
		var packed: PackedScene = load(scene_path)
		assert(packed != null, "failed to load %s" % scene_path)
		var node: Node = packed.instantiate()
		if not (node is Map):
			node.free()
			continue
		maps += 1

		var map: Map = node as Map
		if map.music == null:
			# Legal: the map inherits whatever is already playing (small interiors).
			assert(map.music_playlist.is_empty(),
				"%s sets music_playlist but no base music, so the rotation is ignored" % scene_path)
			map.free()
			continue

		var seen: Dictionary = {map.music.resource_path: true}
		used[map.music.resource_path] = true
		for track: AudioStream in map.music_playlist:
			assert(track != null, "%s has an empty music_playlist slot" % scene_path)
			assert(track.get_length() > 0.0,
				"%s: unreadable track %s" % [scene_path, track.resource_path])
			assert(not seen.has(track.resource_path),
				"%s lists %s twice" % [scene_path, track.resource_path])
			seen[track.resource_path] = true
			used[track.resource_path] = true

		if not map.music_playlist.is_empty():
			rotating += 1
		print("OK ", scene_path.get_file(), " tracks=", seen.size())
		map.free()

	# The client's own rotations (boss fights, login screen) are path lists, so a typo
	# there only shows up at runtime — resolve them here instead.
	var client_script: GDScript = load("res://source/client/autoload/client.gd")
	var gateway_script: GDScript = load("res://source/client/gateway/gateway.gd")
	var client_tracks: Array[String] = client_script.MUSIC_BOSS_FIGHT.duplicate()
	client_tracks.append(client_script.MUSIC_BOSS_VICTORY)
	client_tracks.append_array(gateway_script.MUSIC_GATEWAY)
	for path: String in client_tracks:
		assert(ResourceLoader.exists(path), "missing client track %s" % path)
		used[path] = true

	print("maps with a rotation: ", rotating, "/", maps)
	print("distinct tracks in use: ", used.size())
	print("MAP_MUSIC_VERIFY_PASS")
	quit(0)


func _find_scenes(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_find_scenes(full))
		elif entry.ends_with(".tscn"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
