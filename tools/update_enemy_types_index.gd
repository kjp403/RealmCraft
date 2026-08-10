@tool
extends SceneTree
## Headless, additive stand-in for the TinyMMO panel's "Update" on the enemy
## types index: allocates ids for enemy type resources that are not indexed
## yet, stamps `metadata/slug` + `metadata/id` on them, and appends entries.
##
## Additive for the same reason `update_items_index.gd` is: a full rebuild from
## a headless `-s` run silently drops anything that fails to load without the
## editor, which would prune live ids out of the registry.
##
##   godot --headless --path . -s tools/update_enemy_types_index.gd

const INDEX_PATH: String = "res://source/common/registry/indexes/enemy_types_index.tres"


func _init() -> void:
	var index: ContentIndex = ResourceLoader.load(INDEX_PATH) as ContentIndex
	if index == null:
		printerr("Could not load ", INDEX_PATH)
		quit(1)
		return

	var indexed: Dictionary[StringName, bool] = {}
	for entry: Dictionary in index.entries:
		indexed[StringName(entry.get(&"slug", &""))] = true

	var paths: PackedStringArray = _collect(index.scan_path, index.filters)
	paths.sort()

	var entries: Array[Dictionary] = index.entries.duplicate()
	var added: int = 0
	for path: String in paths:
		var slug: StringName = StringName(path.get_file().get_basename())
		if indexed.has(slug):
			continue
		var resource: Resource = ResourceLoader.load(path)
		if resource == null or resource is not EnemyTypeResource:
			continue
		indexed[slug] = true

		var id: int = index.next_id
		index.next_id += 1
		resource.set_meta(&"slug", slug)
		resource.set_meta(&"id", id)
		ResourceSaver.save(resource, path)
		entries.append({
			&"id": id,
			&"slug": slug,
			&"path": path,
			&"hash": FileAccess.get_sha256(path),
		})
		added += 1
		print("stamped %s -> id %d" % [slug, id])

	if added == 0:
		print("enemy types index already up to date (", entries.size(), " entries)")
		quit(0)
		return

	index.version = int(Time.get_unix_time_from_system())
	index.entries = entries
	var err: Error = ResourceSaver.save(index, INDEX_PATH)
	if err != OK:
		printerr("Save failed: ", error_string(err))
		quit(1)
		return
	print("enemy types indexed: ", entries.size(), " next_id: ", index.next_id)
	quit(0)


func _collect(path: String, filters: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		var full: String = path + "/" + entry
		if dir.current_is_dir():
			out.append_array(_collect(full, filters))
		else:
			for filter: String in filters:
				if full.match(filter):
					out.append(full)
					break
		entry = dir.get_next()
	dir.list_dir_end()
	return out
