extends SceneTree
## Append any new ability .tres files under ability_collection into abilities_index.tres,
## assigning stable new ids and writing metadata back onto each resource.


const INDEX_PATH := "res://source/common/registry/indexes/abilities_index.tres"
const SCAN_PATH := "res://source/common/gameplay/combat/ability/ability_collection"


func _init() -> void:
	var index: ContentIndex = load(INDEX_PATH) as ContentIndex
	assert(index != null)
	var known: Dictionary = {}
	for entry: Dictionary in index.entries:
		known[String(entry[&"slug"])] = true
		known[String(entry[&"path"])] = true

	var added: int = 0
	var paths: PackedStringArray = _collect(SCAN_PATH)
	paths.sort()
	for resource_path: String in paths:
		var slug: String = resource_path.get_file().get_basename()
		if known.has(slug) or known.has(resource_path):
			# Refresh hash for edited existing entries.
			for entry: Dictionary in index.entries:
				if String(entry[&"path"]) == resource_path or String(entry[&"slug"]) == slug:
					entry[&"hash"] = FileAccess.get_sha256(resource_path)
					break
			continue
		var resource: Resource = load(resource_path)
		if resource == null:
			push_warning("skip unloadable %s" % resource_path)
			continue
		var id: int = index.next_id
		index.next_id += 1
		resource.set_meta(&"slug", StringName(slug))
		resource.set_meta(&"id", id)
		ResourceSaver.save(resource, resource_path)
		index.entries.append({
			&"id": id,
			&"slug": StringName(slug),
			&"path": resource_path,
			&"hash": FileAccess.get_sha256(resource_path),
		})
		added += 1
		print("ADDED ", slug, " id=", id)

	index.version = int(Time.get_unix_time_from_system())
	var err: Error = ResourceSaver.save(index, INDEX_PATH)
	assert(err == OK)
	print("INDEX_OK added=", added, " next_id=", index.next_id, " entries=", index.entries.size())
	quit()


func _collect(path: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full: String = path.path_join(name)
		if dir.current_is_dir():
			out.append_array(_collect(full))
		elif name.ends_with(".tres"):
			out.append(full)
		name = dir.get_next()
	return out
