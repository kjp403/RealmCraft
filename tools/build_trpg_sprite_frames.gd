extends SceneTree
## Build SpriteFrames + stub EnemyTypeResources from tools/trpg_import_catalog.json.
## Run after copy_trpg_character_sheets.py and a Godot import pass:
##   godot --headless --path . --import
##   godot --headless --path . -s tools/build_trpg_sprite_frames.gd

const CATALOG_PATH := "res://tools/trpg_import_catalog.json"
const SPRITES_DIR := "res://source/common/gameplay/characters/sprite_frames/"
const TYPES_DIR := "res://source/common/gameplay/characters/npc/types/trpg/"
const ASSETS_DIR := "res://assets/sprites/characters/"


func _initialize() -> void:
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("Missing catalog: %s" % CATALOG_PATH)
		quit(1)
		return

	var text := FileAccess.get_file_as_string(CATALOG_PATH)
	var catalog: Variant = JSON.parse_string(text)
	if typeof(catalog) != TYPE_ARRAY:
		push_error("Bad catalog JSON")
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TYPES_DIR))

	var built := 0
	for entry: Variant in catalog:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		var slug: String = str(d.get("slug", ""))
		var display: String = str(d.get("display_name", slug))
		var anims: Dictionary = d.get("anims", {})
		if slug.is_empty() or anims.is_empty():
			continue
		if _build_one(slug, display, anims):
			built += 1

	_append_indexes_only()
	print("TRPG_BUILD_PASS characters=", built)
	quit(0)


func _build_one(slug: String, display: String, anims: Dictionary) -> bool:
	var frames := SpriteFrames.new()
	# Remove default empty anim Godot adds
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	var order := ["idle", "walk", "run", "death", "attack", "special", "hurt", "block", "attack_3"]
	var seen: Dictionary = {}
	for key: String in order:
		if not anims.has(key):
			continue
		_add_anim(frames, slug, key, anims[key])
		seen[key] = true

	# Ensure run exists (locomotion uses run)
	if frames.has_animation(&"walk") and not frames.has_animation(&"run"):
		_clone_anim(frames, &"walk", &"run")
	elif frames.has_animation(&"idle") and not frames.has_animation(&"run"):
		_clone_anim(frames, &"idle", &"run")

	# Any leftover anim keys
	for key: Variant in anims.keys():
		var ks := str(key)
		if seen.has(ks):
			continue
		_add_anim(frames, slug, ks, anims[key])

	var skin_path := SPRITES_DIR + slug + ".tres"
	var prev_skin_id: Variant = null
	if FileAccess.file_exists(skin_path):
		var prev_skin: Resource = load(skin_path)
		if prev_skin != null and prev_skin.has_meta(&"id"):
			prev_skin_id = prev_skin.get_meta(&"id")
	frames.set_meta(&"slug", StringName(slug))
	if prev_skin_id != null:
		frames.set_meta(&"id", prev_skin_id)
	var err := ResourceSaver.save(frames, skin_path)
	if err != OK:
		push_error("Failed save skin %s: %s" % [skin_path, error_string(err)])
		return false
	print("skin ", skin_path)

	# Stub enemy type — ready to place later; not spawned on maps.
	var type_path := TYPES_DIR + slug + ".tres"
	var prev_type_id: Variant = null
	var etype: EnemyTypeResource = null
	if FileAccess.file_exists(type_path):
		etype = load(type_path) as EnemyTypeResource
		if etype != null and etype.has_meta(&"id"):
			prev_type_id = etype.get_meta(&"id")
	if etype == null:
		etype = EnemyTypeResource.new()
		etype.max_health = 80.0
		etype.attack_damage = 8.0
		etype.attack_cooldown = 1.4
		etype.move_speed = 70
		etype.distance_to_attack = 22
		etype.max_distance_from_spawn = 260
		etype.detection_radius = 120
		etype.chase_on_area = false
		etype.is_lone = true
		etype.wander_radius = 48.0
		etype.xp_reward = 10
		etype.respawn_delay = 12.0
	etype.enemy_type = StringName(slug)
	etype.display_name = display
	etype.skin = load(skin_path) as SpriteFrames
	etype.set_meta(&"slug", StringName(slug))
	if prev_type_id != null:
		etype.set_meta(&"id", prev_type_id)

	err = ResourceSaver.save(etype, type_path)
	if err != OK:
		push_error("Failed save type %s: %s" % [type_path, error_string(err)])
		return false
	print("type ", type_path)
	return true


func _add_anim(frames: SpriteFrames, slug: String, key: String, info: Variant) -> void:
	var meta: Dictionary = info
	var file: String = str(meta.get("file", ""))
	var frame_count: int = int(meta.get("frames", 0))
	var fw: int = int(meta.get("frame_w", 100))
	var fh: int = int(meta.get("frame_h", 100))
	if file.is_empty() or frame_count <= 0:
		return
	var tex_path := ASSETS_DIR + slug + "/" + file
	var tex: Texture2D = load(tex_path) as Texture2D
	if tex == null:
		push_warning("Missing texture %s" % tex_path)
		return
	var anim_name := StringName(key)
	if frames.has_animation(anim_name):
		frames.remove_animation(anim_name)
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, key in ["idle", "walk", "run"])
	var speed := 8.0
	match key:
		"idle":
			speed = 6.0
		"attack", "special", "attack_3":
			speed = 10.0
		"death", "hurt":
			speed = 8.0
	frames.set_animation_speed(anim_name, speed)
	for i in frame_count:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame(anim_name, atlas)


func _clone_anim(frames: SpriteFrames, from_anim: StringName, to_anim: StringName) -> void:
	if frames.has_animation(to_anim):
		frames.remove_animation(to_anim)
	frames.add_animation(to_anim)
	frames.set_animation_loop(to_anim, frames.get_animation_loop(from_anim))
	frames.set_animation_speed(to_anim, frames.get_animation_speed(from_anim))
	var count := frames.get_frame_count(from_anim)
	for i in count:
		frames.add_frame(to_anim, frames.get_frame_texture(from_anim, i), frames.get_frame_duration(from_anim, i))


func _append_indexes_only() -> void:
	## Add trpg_* entries without rewriting existing index rows / stripping UIDs.
	_append_prefix(
		&"sprites",
		"res://source/common/registry/indexes/sprites_index.tres",
		"res://source/common/gameplay/characters/sprite_frames",
		"trpg_"
	)
	_append_prefix(
		&"enemy_types",
		"res://source/common/registry/indexes/enemy_types_index.tres",
		"res://source/common/gameplay/characters/npc/types",
		"trpg_"
	)


func _append_prefix(content_name: StringName, index_path: String, scan_path: String, prefix: String) -> void:
	var content_index: ContentIndex = load(index_path) as ContentIndex
	var existing: Dictionary = {}
	for entry: Dictionary in content_index.entries:
		existing[entry[&"slug"]] = true
	var paths := _collect_paths(scan_path, PackedStringArray(["*.tres"]))
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
	content_index.version = int(Time.get_unix_time_from_system())
	ResourceSaver.save(content_index, index_path)
	print("index append ", content_name, " added=", added)


func _generate_index(content_name: StringName, scan_path: String, filters: PackedStringArray) -> void:
	## Unused full rebuild kept for emergencies — prefer _append_indexes_only.
	pass


func _collect_paths(path: String, filters: PackedStringArray) -> PackedStringArray:
	var abs_path := ProjectSettings.globalize_path(path)
	var out := PackedStringArray()
	_walk(abs_path, path, filters, out)
	return out


func _walk(abs_dir: String, res_dir: String, filters: PackedStringArray, out: PackedStringArray) -> void:
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var abs_child := abs_dir.path_join(name)
		var res_child := res_dir.path_join(name)
		if dir.current_is_dir():
			_walk(abs_child, res_child, filters, out)
		else:
			for filter: String in filters:
				if res_child.match(filter) or name.match(filter):
					out.append(res_child)
					break
		name = dir.get_next()
	dir.list_dir_end()
