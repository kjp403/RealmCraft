extends SceneTree
## Render a filmstrip of the boss telegraph language so a design change can be
## reviewed as PICTURES instead of adjectives. Draws the old CastTelegraph beside
## the new ElementalTelegraph in each of its three elements and both of its modes,
## all ticking on the same clock, and dumps one PNG per sampled frame.
##
## Must run WINDOWED (no --headless) — headless has no rasteriser, so the
## SubViewport texture comes back blank:
##   godot --path . -s tools/render_boss_telegraphs.gd
##
## Output: <scratchpad>/telegraph/frame_##.png, assembled into a GIF outside.

const OUT_DIR := "user://telegraph"
const W := 1520
const H := 300
## Wind-up length the strip plays through, and how many stills to take of it.
const WINDUP := 2.4
const FRAMES := 30

var _sv: SubViewport


func _initialize() -> void:
	call_deferred(&"_go")


func _go() -> void:
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, H)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.transparent_bg = false
	_sv.world_2d = World2D.new()
	root.add_child(_sv)

	var stage := Node2D.new()
	_sv.add_child(stage)

	# Flat dark ground so the telegraphs read the way they do over a map, not
	# over transparency.
	var bg := ColorRect.new()
	bg.size = Vector2(W, H)
	bg.color = Color(0.13, 0.13, 0.17)
	# Telegraphs draw at z_index -1 (they live UNDER characters on a real map),
	# so the stand-in ground has to sit below that or it hides every one of them.
	bg.z_index = -10
	stage.add_child(bg)

	var cam := Camera2D.new()
	cam.position = Vector2(W, H) * 0.5
	cam.make_current()
	stage.add_child(cam)

	var y: float = H * 0.55
	_label(stage, Vector2(140, 40), "BEFORE")
	_label(stage, Vector2(505, 40), "AFTER  fire / danger")
	_label(stage, Vector2(920, 40), "frost / SAFE")
	_label(stage, Vector2(1290, 40), "storm / danger")

	# BEFORE: the flat red ring every boss cast used.
	var old := CastTelegraph.new()
	old.radius = 78.0
	old.duration = WINDUP
	stage.add_child(old)
	old.position = Vector2(190, y)

	var fire: ElementalTelegraph = _spawn_elem(stage, Vector2(570, y),
		ElementalTelegraph.Element.FIRE, ElementalTelegraph.Mode.DANGER)
	_spawn_elem(stage, Vector2(960, y), ElementalTelegraph.Element.FROST,
		ElementalTelegraph.Mode.SAFE)
	_spawn_elem(stage, Vector2(1340, y), ElementalTelegraph.Element.STORM,
		ElementalTelegraph.Mode.DANGER)

	# Let the first frame settle so particles have emitted before frame 0.
	await process_frame
	await process_frame

	# Sample against the WALL CLOCK, not against a fixed sleep per frame. Saving
	# a PNG costs tens of ms, so a naive `await create_timer(windup/frames)` loop
	# runs long and the telegraphs free themselves before the last captures —
	# losing exactly the frames that matter (the ring converging on the centre).
	var t0: int = Time.get_ticks_msec()
	var step: float = WINDUP / float(FRAMES)
	var taken: int = 0
	while taken < FRAMES:
		await process_frame
		var elapsed: float = float(Time.get_ticks_msec() - t0) / 1000.0
		if elapsed < float(taken) * step:
			continue
		# Stop the moment the telegraphs free themselves, or the tail of the
		# strip is blank ground rather than the end of the wind-up.
		if not is_instance_valid(fire):
			break
		var img: Image = _sv.get_texture().get_image()
		img.save_png("%s/frame_%02d.png" % [OUT_DIR, taken])
		taken += 1
	print("RENDER_OK frames=%d dir=%s" % [taken, ProjectSettings.globalize_path(OUT_DIR)])
	quit()


func _spawn_elem(
		parent: Node, at: Vector2, element: ElementalTelegraph.Element,
		mode: ElementalTelegraph.Mode
	) -> ElementalTelegraph:
	var t := ElementalTelegraph.new()
	t.radius = 78.0
	t.duration = WINDUP
	t.element = element
	t.mode = mode
	parent.add_child(t)
	t.position = at
	return t


func _label(parent: Node, at: Vector2, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.position = at
	l.add_theme_color_override(&"font_color", Color(0.85, 0.86, 0.92))
	parent.add_child(l)
