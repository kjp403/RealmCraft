extends Node
## Screenshot the REAL CollectionLogMenu at the shipping 960x540 client size,
## driven by a REAL payload out of CollectionLogManager.build_payload — not a
## hand-written dictionary. If the payload shape ever drifts from what the menu
## reads, these previews break, which is the point.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_collection_log_previews.tscn
##
## The scene route is not a style choice: `-s` starts a bare SceneTree with no
## autoloads, and collection_log_menu.gd references Client, ClientState and
## Toaster — under `-s` it fails to COMPILE, so there is nothing to screenshot.
## `--mode=client` keeps the Client autoload alive instead of self-freeing.
##
## Nothing here touches player data: the fixture is a throwaway PlayerResource
## built in memory, never saved.

const MENU_SCENE: String = "res://source/client/ui/menus/collection_log/collection_log_menu.tscn"
const OUT_DIR: String = "res://previews"
## The project's base viewport. Previews are captured here, so what you see is
## exactly the layout the client produces — not a roomier canvas that hides
## clipping.
const W: int = 960
const H: int = 540

var _sv: SubViewport
var _menu: Control


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var out_abs: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_abs)

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, H)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.transparent_bg = false
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	# Stand-in for the world behind the menu, so the shell's dim backdrop reads
	# the way it does over a real map instead of over pure black.
	var ground: ColorRect = ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.20, 0.24, 0.28)
	_sv.add_child(ground)

	var scene: PackedScene = load(MENU_SCENE) as PackedScene
	if scene == null:
		push_error("Could not load %s" % MENU_SCENE)
		get_tree().quit(1)
		return
	_menu = scene.instantiate() as Control
	_sv.add_child(_menu)

	await get_tree().process_frame
	await get_tree().process_frame

	# Three states worth looking at: a log part-way, a log one drop from green,
	# and a finished one. Selection is driven by clicking the real list rows.
	var payload: Dictionary = _fixture()
	_menu.call(&"_apply_state", payload)
	await _settle()
	await _shot(out_abs, "collection-log-partial.png")

	_select(1)
	await _settle()
	await _shot(out_abs, "collection-log-nearly.png")

	_select(2)
	await _settle()
	await _shot(out_abs, "collection-log-green.png")

	print("PREVIEWS_OK -> %s" % out_abs)
	get_tree().quit(0)


## A believable spread across the three shipped logs, built by driving the REAL
## manager rather than by writing the payload out by hand.
func _fixture() -> Dictionary:
	var pr: PlayerResource = PlayerResource.new()
	var logs: Array[BossCollectionLog] = CollectionLogManager.all_logs()
	for i: int in logs.size():
		var boss_log: BossCollectionLog = logs[i]
		# How much of each log is filled: a third, all-but-one, then all of it.
		var fill: int = boss_log.total_items()
		match i:
			0: fill = maxi(1, int(round(boss_log.total_items() * 0.34)))
			1: fill = maxi(1, boss_log.total_items() - 1)
		for k: int in 40 + i * 33:
			CollectionLogManager.increment_boss_kill(pr, boss_log.boss_id)
		for j: int in fill:
			# Duplicates on purpose: the quantity badge only renders past the
			# first copy, so a fixture that grants exactly one of everything
			# would screenshot a feature that looks absent.
			for _dupe: int in 1 + (j % 3):
				CollectionLogManager.add_item_to_log(
					pr, boss_log.boss_id, boss_log.log_items[j])
		# A few more dry kills after the last unlock, so the streak readout has
		# something to show rather than always sitting at 0.
		for k: int in 7 + i * 4:
			CollectionLogManager.increment_boss_kill(pr, boss_log.boss_id)
	var payload: Dictionary = CollectionLogManager.build_payload(pr)
	payload["ok"] = true
	return payload


## Click the nth boss row, the way a player would — so the previews exercise the
## real selection path instead of poking at private state.
func _select(index: int) -> void:
	var rows: Array = []
	_collect_rows(_menu, rows)
	if index < rows.size():
		(rows[index] as Button).emit_signal(&"pressed")


func _collect_rows(node: Node, out: Array) -> void:
	for child: Node in node.get_children():
		# The list rows are the tall cards; the Close button is short and lives
		# in the header, so height is enough to tell them apart.
		if child is Button and (child as Button).custom_minimum_size.y >= 70.0:
			out.append(child)
		_collect_rows(child, out)


func _settle() -> void:
	for i: int in 4:
		await get_tree().process_frame


func _shot(out_abs: String, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _sv.get_texture().get_image()
	var path: String = out_abs.path_join(file_name)
	image.save_png(path)
	print("wrote %s" % path)
