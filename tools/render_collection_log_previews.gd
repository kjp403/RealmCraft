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
##
## It also GATES the detail-panel layout, not just photographs it. The plaque
## bugs this panel has had were all size-flag bugs — a banner that split the
## leftover space with the spacer, a title that sank to the floor — and every one
## of them compiled, ran, and looked fine to every automated check. The only
## thing that ever caught them was a person looking at the render. _assert_layout
## measures the laid-out rects instead, so the next one fails the tool.

const MENU_SCENE: String = "res://source/client/ui/menus/collection_log/collection_log_menu.tscn"
const OUT_DIR: String = "res://previews"
## The project's base viewport. Previews are captured here, so what you see is
## exactly the layout the client produces — not a roomier canvas that hides
## clipping.
const W: int = 960
const H: int = 540

## Slack allowed between the plaque's measured height and the height its content
## implies. Two pixels covers container rounding; anything past that means the
## plaque is expanding rather than hugging.
const HUG_SLACK: float = 2.0

var _sv: SubViewport
var _menu: Control
var _failures: Array[String] = []


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
	_assert_layout("partial")

	_select(1)
	await _settle()
	await _shot(out_abs, "collection-log-nearly.png")
	_assert_layout("nearly")

	# The green state is the one that matters most here: it is the only one whose
	# plaque carries a live emitter stack, so it is the only one where a clipping
	# ancestor or a starved title rect has anything to destroy.
	_select(2)
	await _settle()
	await _shot(out_abs, "collection-log-green.png")
	_assert_layout("green")

	# THE BIGGEST LOG, whichever it currently is. Not a fixed boss: the worst case
	# moves every time log_items is edited, and the panel's layout assumptions are
	# exactly what a bigger log breaks — the grid was a bare fixed block until
	# tier materials took one log to 21 items and ran it off the bottom.
	_select(_largest_index())
	await _settle()
	await _shot(out_abs, "collection-log-largest.png")
	_assert_layout("largest")

	print("")
	if _failures.is_empty():
		print("PREVIEWS_OK -> %s  (layout gate passed)" % out_abs)
		get_tree().quit(0)
		return
	for line: String in _failures:
		printerr("  FAIL: %s" % line)
	print("PREVIEWS_LAYOUT_FAIL  (%d)" % _failures.size())
	get_tree().quit(1)


## Measure the laid-out detail panel and fail on the specific breakages this
## layout has actually suffered, rather than on a generic "does it look right".
func _assert_layout(state: String) -> void:
	var host: VBoxContainer = _menu.get(&"_detail_host") as VBoxContainer
	if host == null:
		_f(state, "no _detail_host")
		return

	# One expanding child, and it must not be the plaque. Two expanders share the
	# slack and the plaque floats back into the middle of the panel.
	var expanders: Array[String] = []
	for child: Node in host.get_children():
		var c: Control = child as Control
		if c != null and (c.size_flags_vertical & Control.SIZE_EXPAND) != 0:
			expanders.append(c.get_class())
	if expanders.size() != 1:
		_f(state, "%d expanding children of _detail_host (%s), expected exactly "
			% [expanders.size(), ", ".join(expanders)]
			+ "the spacer — the plaque will not sit on the bottom margin")

	var plaque: PanelContainer = null
	for child: Node in host.get_children():
		if child is PanelContainer:
			plaque = child
	if plaque == null:
		_f(state, "no plaque in the detail panel")
		return
	if (plaque.size_flags_vertical & Control.SIZE_EXPAND) != 0:
		_f(state, "the plaque expands vertically — it must hug its content")

	# It has to actually END at the bottom of the panel, not merely be last.
	var gap: float = host.size.y - (plaque.position.y + plaque.size.y)
	if absf(gap) > HUG_SLACK:
		_f(state, "plaque bottom is %.0fpx off the panel floor" % gap)

	var title: Label = _deepest_label(plaque)
	if title == null:
		_f(state, "no title label inside the plaque")
		return

	# Nothing on the chain from the title up to the plaque may clip: the shader
	# displaces vertices and the emitters travel outside the text rect, so one
	# clipping ancestor shears the glyphs and kills the particles.
	var node: Node = title
	while node != null:
		var c: Control = node as Control
		if c != null and c.clip_contents:
			_f(state, "%s clips its contents — it will shear the title and kill "
				% c.get_class() + "the emitters")
		if node == plaque:
			break
		node = node.get_parent()

	# The emitter stack is fitted to the title's rect, so a title squeezed to its
	# glyph height gives the particles nowhere to go.
	# Read off the menu's own constant so the gate cannot drift from it. Object.get
	# does not see consts — they are not properties — so it has to come out of the
	# script's constant map.
	var consts: Dictionary = _menu.get_script().get_script_constant_map()
	var want: float = float(consts.get("PLAQUE_TITLE_HEIGHT", 0.0))
	if title.size.y + HUG_SLACK < want:
		_f(state, "title rect is %.0fpx tall, needs %.0f for the emitters"
			% [title.size.y, want])

	if title.vertical_alignment != VERTICAL_ALIGNMENT_CENTER:
		_f(state, "title is not vertically centred — it will rest on the plaque "
			+ "floor and clip against the bottom border")

	# THE CHECK THAT MATTERS. TitleVfx.apply_to_label calls reset_size(), which
	# shrinks a container-managed label to its own minimum WITHOUT the container
	# re-sorting — so a title set to expand collapses to its text width and
	# strands itself at the top-left of its slot. Every flag still reads correctly
	# afterwards, including horizontal_alignment; only the laid-out rect shows it.
	# An earlier version of this gate asserted the flags and passed a plaque whose
	# title was jammed against the left margin.
	var t: Rect2 = title.get_global_rect()
	var p: Rect2 = plaque.get_global_rect()
	var off: float = absf(t.get_center().x - p.get_center().x)
	if off > 2.0:
		_f(state, "title is %.0fpx off the plaque's horizontal centre — a "
			% off + "reset_size() has almost certainly collapsed it out of its slot")
	if t.get_center().y < p.get_center().y - 4.0:
		_f(state, "title is riding high in the plaque — it is sitting at the top "
			+ "of its slot rather than centred in it")

	# ...and the emitters must be centred on the glyphs. They are placed at
	# label.size * 0.5 at apply time, so a stale or collapsed rect leaves the
	# whole stack sitting somewhere the text is not.
	for fx_name: String in ["VipTitleFx", "TitleParticles"]:
		var fx: Node2D = title.get_node_or_null(NodePath(fx_name)) as Node2D
		if fx == null:
			continue
		if fx.position.distance_to(title.size * 0.5) > 3.0:
			_f(state, "%s sits at %s, not the title's centre %s"
				% [fx_name, fx.position, title.size * 0.5])


## The plaque's title, told apart from the caption by being the one that carries
## a shader — the caption is plain themed text.
func _deepest_label(root: Node) -> Label:
	for child: Node in root.get_children():
		var found: Label = _deepest_label(child)
		if found != null:
			return found
	var label: Label = root as Label
	if label != null and label.material is ShaderMaterial:
		return label
	return null


func _f(state: String, msg: String) -> void:
	_failures.append("[%s] %s" % [state, msg])


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


## Index of the log with the most items, in the order the list renders them.
func _largest_index() -> int:
	var logs: Array = _menu.get(&"_logs")
	var best: int = 0
	var most: int = -1
	for i: int in logs.size():
		var total: int = int((logs[i] as Dictionary).get("total", 0))
		if total > most:
			most = total
			best = i
	print("largest log: index %d, %d items" % [best, most])
	return best


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
