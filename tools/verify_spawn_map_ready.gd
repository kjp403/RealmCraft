extends SceneTree
## Both spawn readers must wait for the map before asking it where to put a
## player. Warpers self-register from their own _ready and the map is added with
## add_child.call_deferred, so a reader that races the load gets an empty
## registry and get_spawn_position falls through to (0, 0) — the top-left corner,
## which is border wall outdoors and unlit rock in a cave. It is silent: the
## player simply appears somewhere they cannot be.
##
## Source-level on purpose. The failure is one missing `await` on a code path,
## and reproducing it needs a live world charging a brand-new biome.
##
##   godot --headless --path . -s tools/verify_spawn_map_ready.gd

const INSTANCE := "res://source/server/world/components/instance_server.gd"
const MANAGER := "res://source/server/world/components/instance_manager.gd"


func _init() -> void:
	var fails: Array[String] = []
	var inst: String = FileAccess.get_file_as_string(INSTANCE)
	var mgr: String = FileAccess.get_file_as_string(MANAGER)

	if not inst.contains("func await_map_ready() -> void:"):
		fails.append("ServerInstance.await_map_ready is gone — nothing gates the spawn readers")
	if not inst.contains("await instance_map.ready"):
		fails.append("await_map_ready no longer waits for the map to enter the tree")
	if not inst.contains("await get_tree().process_frame"):
		fails.append("await_map_ready no longer waits a frame for warpers to register")

	# The join path.
	if not _awaits_before_spawn(inst, "func spawn_player", "get_spawn_position"):
		fails.append("spawn_player reads get_spawn_position without awaiting await_map_ready")
	# The warp path — the one that shipped broken, and the reason new zones put
	# the first arrival in the corner.
	if not _awaits_before_spawn(mgr, "func player_switch_instance", "get_spawn_position"):
		fails.append("player_switch_instance reads get_spawn_position without awaiting await_map_ready")

	for f: String in fails:
		printerr("FAIL: ", f)
	if fails.is_empty():
		print("VERIFY_PASS spawn_map_ready")
		quit(0)
		return
	printerr("VERIFY_FAIL (%d)" % fails.size())
	quit(1)


## True when [param func_name]'s body awaits await_map_ready BEFORE it reads
## [param reader].
func _awaits_before_spawn(src: String, func_name: String, reader: String) -> bool:
	var start: int = src.find(func_name)
	if start < 0:
		return false
	var read_at: int = src.find(reader, start)
	var wait_at: int = src.find("await_map_ready()", start)
	return wait_at >= 0 and read_at >= 0 and wait_at < read_at
