extends SceneTree
## Append only new trpg_* sprites/enemy_types to content indexes (no rewrite of existing entries).

func _initialize() -> void:
	_append_new(
		&"sprites",
		"res://source/common/registry/indexes/sprites_index.tres",
		"res://source/common/gameplay/characters/sprite_frames",
		"trpg_"
	)
	_append_new(
		&"enemy_types",
		"res://source/common/registry/indexes/enemy_types_index.tres",
		"res://source/common/gameplay/characters/npc/types",
		"trpg_"
	)
	print("TRPG_INDEX_APPEND_PASS")
	quit(0)


func _append_new(content_name: StringName, index_path: String, scan_path: String, prefix: String) -> void:
	var content_index: ContentIndex = load(index_path) as ContentIndex
	assert(content_index != null)
	var existing: Dictionary = {}
	for entry: Dictionary in content_index.entries:
		existing[entry[&"slug"]] = true

	var paths := _collect(scan_path)
	paths.sort()
	var added := 0
	for resource_path: String in paths:
		var slug_str := resource_path.get_file().get_basename()
		if not slug_str.begins_with(prefix):
			continue
		var slug := StringName(slug_str)
		if existing.has(slug):
			continue
		var resource: Resource = load(resource_path)
		if resource == null:
			continue
		var id: int = content_index.next_id
		content_index.next_id += 1
		resource.set_meta(&"slug", slug)
		resource.set_meta(&"id", id)
		ResourceSaver.save(resource, resource_path)
		content_index.entries.append({
			&"id": id,
			&"slug": slug,
			&"path": resource_path,
			&"hash": FileAccess.get_sha256(resource_path),
		})
		added += 1
		print("add ", content_name, " ", slug, " id=", id)
	content_index.version = int(Time.get_unix_time_from_system())
	ResourceSaver.save(content_index, index_path)
	print(content_name, " added=", added, " next_id=", content_index.next_id)


func _collect(path: String) -> PackedStringArray:
	var abs_path := ProjectSettings.globalize_path(path)
	var out := PackedStringArray()
	_walk(abs_path, path, out)
	return out


func _walk(abs_dir: String, res_dir: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var abs_child := abs_dir.path_join(name)
			var res_child := res_dir.path_join(name)
			if dir.current_is_dir():
				_walk(abs_child, res_child, out)
			elif name.ends_with(".tres"):
				out.append(res_child)
		name = dir.get_next()
	dir.list_dir_end()
