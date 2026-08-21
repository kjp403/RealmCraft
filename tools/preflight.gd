extends Node
## Pre-merge sweep: load everything the game loads and report anything that
## fails, so a broken resource or a script that no longer parses is caught here
## instead of by players. CI only builds the website — it never opens the
## Godot project — so this is the only gate the game code has.
##   godot --path . --mode=client res://tools/preflight.tscn

const SKIP_DIRS: Array[String] = ["res://tools", "res://addons", "res://.godot"]

var _errors: Array[String] = []
var _scripts: int = 0
var _scenes: int = 0
var _resources: int = 0


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var files: Array[String] = []
	_walk("res://source", files)
	for path: String in files:
		if path.ends_with(".gd"):
			_check_script(path)
		elif path.ends_with(".tscn"):
			_check_scene(path)
		elif path.ends_with(".tres"):
			_check_resource(path)

	print("--- preflight ---")
	print("scripts %d, scenes %d, resources %d" % [_scripts, _scenes, _resources])
	if _errors.is_empty():
		print("PREFLIGHT_PASS")
	else:
		for e: String in _errors:
			print("  FAIL ", e)
		print("PREFLIGHT_FAIL (%d)" % _errors.size())
	get_tree().quit(0 if _errors.is_empty() else 1)


func _walk(dir_path: String, out: Array[String]) -> void:
	for skip: String in SKIP_DIRS:
		if dir_path.begins_with(skip):
			return
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			_walk(full, out)
		elif name.ends_with(".gd") or name.ends_with(".tscn") or name.ends_with(".tres"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()


func _check_script(path: String) -> void:
	_scripts += 1
	# load() hands back a GDScript object even when the source failed to parse,
	# so the object being non-null proves nothing. reload() returns the actual
	# compile result — this is what catches a silent parse error that would
	# otherwise drop a whole class and no-op a feature in the live build.
	var script: GDScript = load(path) as GDScript
	if script == null:
		_errors.append("%s: will not load" % path)
		return
	var err: int = script.reload()
	# ERR_ALREADY_IN_USE just means the script is live right now (autoloads and
	# every class_name global are), not that it is broken.
	if err != OK and err != ERR_ALREADY_IN_USE:
		_errors.append("%s: does not compile (%s)" % [path, error_string(err)])


func _check_scene(path: String) -> void:
	_scenes += 1
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		_errors.append("%s: will not load" % path)
	elif not packed.can_instantiate():
		_errors.append("%s: cannot instantiate" % path)


func _check_resource(path: String) -> void:
	_resources += 1
	var res: Resource = load(path)
	if res == null:
		_errors.append("%s: will not load" % path)
