class_name ContentRegistryHub


static var _content_by_name: Dictionary[StringName, ContentRegistry]
static var _versions: Dictionary[StringName, int]


static func _static_init() -> void:
	# Master + gateway are data-only servers — they don't render anything, so
	# loading the sprite/skin registries is pure waste. GameMode reads the
	# --mode= cmdline arg first so this works in a unified server binary too.
	if GameMode.is_master_server() or GameMode.is_gateway_server():
		return
	const INDEXES_DIR: String = "res://source/common/registry/indexes/"
	for index_path: String in ResourceLoader.list_directory(INDEXES_DIR):
		# Load UNTYPED and check. A typed assignment here throws on anything in
		# this folder that is not a ContentIndex, and the throw aborts the whole
		# loop — every registry after it silently never registers, which reads in
		# game as "all my items vanished". One stray file must not do that.
		var loaded: Resource = ResourceLoader.load(INDEXES_DIR + index_path)
		var content_index: ContentIndex = loaded as ContentIndex
		if content_index == null:
			push_error("ContentRegistryHub: %s is not a ContentIndex — skipping. Only "
				% index_path + "content indexes belong in registry/indexes/.")
			continue
		register_registry(
			index_path.trim_suffix("_index.tres"),
			content_index
		)
		#print_debug(content_index.entries)
	#print("_content_by_name = ", _content_by_name)


static func register_registry(content_name: StringName, content_index: ContentIndex) -> void:
	#var content_registry: ContentRegistry = ContentRegistry.new(content_index)
	_content_by_name[content_name] = ContentRegistry.new(content_index)
	_versions[content_name] = content_index.version


static func registry_of(content_name: StringName) -> ContentRegistry:
	return _content_by_name.get(content_name, null)


static func version_of(content_name: StringName) -> int:
	return _versions.get(content_name, 0)


static func id_from_slug(content_name: StringName, slug: StringName) -> int:
	return registry_of(content_name).id_from_slug(slug)


static func load_by_id(
	content_name: StringName,
	id: int,
	cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE
) -> Resource:
	var path: StringName = registry_of(content_name).path_from_id(id)
	if path.is_empty():
		return null
	return ResourceLoader.load(path, "", cache_mode)


static func load_by_slug(
	content_name: StringName,
	slug: StringName,
	cache_mode: ResourceLoader.CacheMode = ResourceLoader.CACHE_MODE_REUSE
) -> Resource:
	var path: StringName = registry_of(content_name).path_from_slug(slug)
	if path.is_empty():
		return null
	return ResourceLoader.load(path, "", cache_mode)


class CachedContent:
	pass
