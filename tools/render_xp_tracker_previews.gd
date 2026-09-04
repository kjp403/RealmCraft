extends Node
## Screenshot the REAL XpTrackerHud at a spread of fill percentages, so the
## spark's trigonometry and the casing's quarter notches can be checked against
## each other by eye rather than by argument.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_xp_tracker_previews.tscn
##
## The scene route is not a style choice: `-s` starts a bare SceneTree with no
## autoloads, and xp_tracker_hud.gd references ClientState and PixelUI — under
## `-s` it fails to COMPILE, so there is nothing to screenshot. This is the same
## reason render_bank_previews.gd runs as a scene.
##
## The orbs are driven by calling the tracker's own XP handler, not by faking
## the visuals: what gets rendered is the real dressing, the real tint lookup
## and the real spark placement. Only the arc VALUE is then pinned, because a
## tween mid-flight would screenshot at whatever fraction the frame landed on.

const TRACKER_SCENE: String = "res://source/client/ui/hud/xp_tracker/xp_tracker_hud.tscn"
const OUT_DIR: String = "res://previews"
## Cell is comfortably larger than the 48px orb so the floating numbers and the
## particle burst have somewhere to go without clipping into the next cell. The
## numbers hang to the LEFT of the orb (they have to clear the minimap in the
## real HUD — see [XpFloatingTextManager]), so the orb sits right of centre in
## its cell and the room is on that side.
const CELL: int = 132
const COLS: int = 4
const ROWS: int = 2
## Previews are captured at 1x and upscaled with NEAREST afterwards — the whole
## point is to inspect single pixels, and a filtered upscale hides exactly the
## half-pixel drift this tool exists to catch.
const ZOOM: int = 4

## job, level, fill ratio, caption.
const CASES: Array = [
	[&"mining", 42, 0.0, "Mining 0%"],
	[&"woodcutting", 31, 0.25, "Woodcutting 25%"],
	[&"smithing", 55, 0.5, "Smithing 50%"],
	[&"fletching", 27, 0.75, "Fletching 75%"],
	[&"harvesting", 18, 0.92, "Farming 92%"],
	[&"outfitting", 40, 0.33, "Crafting 33%"],
	[&"slayer", 61, 0.6, "Slayer + drops"],
	[&"prayer", 44, 0.08, "Prayer level-up"],
]

var _sv: SubViewport


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var out_abs: String = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(out_abs)

	_sv = SubViewport.new()
	_sv.size = Vector2i(CELL * COLS, CELL * ROWS)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.transparent_bg = false
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	# Stand-in for the map behind the HUD, so the casing's contrast is judged
	# against grass rather than against pure black.
	var ground := ColorRect.new()
	ground.size = Vector2(_sv.size)
	ground.color = Color(0.20, 0.26, 0.19)
	_sv.add_child(ground)

	var scene: PackedScene = load(TRACKER_SCENE) as PackedScene
	if scene == null:
		push_error("Could not load %s" % TRACKER_SCENE)
		get_tree().quit(1)
		return

	var trackers: Array[Control] = []
	for i: int in range(CASES.size()):
		var case: Array = CASES[i]
		var tracker: Control = scene.instantiate() as Control
		# Right of centre in its cell, so the numbers hanging off the orb's left
		# edge have room instead of spilling into the previous cell.
		tracker.position = Vector2(
			float((i % COLS) * CELL + (CELL - 48) / 2 + 26),
			float((i / COLS) * CELL + (CELL - 48) / 2 + 12),
		)
		_sv.add_child(tracker)
		trackers.append(tracker)
		_label(case[3], (i % COLS) * CELL, (i / COLS) * CELL + CELL - 16)

	await get_tree().process_frame
	await get_tree().process_frame

	for i: int in range(CASES.size()):
		_drive(trackers[i], CASES[i])

	# One cell shows a burst of rapid ticks accumulating into a single number.
	_spam_drops(trackers[6], &"slayer")
	# One cell is caught on the level-up frame: the arc has just wrapped, the
	# icon is still flashing and the particles are in the air.
	trackers[7].call(&"_on_wrap_peak", XpTrackerHud.tint_for(&"prayer"))

	# Long enough for the fade-in and the flash to be underway, short enough that
	# the burst particles have not left the cell.
	await get_tree().create_timer(0.18).timeout
	for i: int in range(CASES.size()):
		_pin_fill(trackers[i], float(CASES[i][2]))
	await get_tree().process_frame
	await get_tree().process_frame

	var dest: String = out_abs.path_join("xp-tracker-states.png")
	var image: Image = _sv.get_texture().get_image()
	image.resize(image.get_width() * ZOOM, image.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	image.save_png(dest)
	print("wrote ", dest)

	await _render_cards(out_abs)
	get_tree().quit(0)


## The hover card, in the three states whose copy differs: mid-level, a skill
## whose slug is not its name (harvesting DISPLAYS as Farming), and level 99,
## where "x / 0 XP" would otherwise be printed.
func _render_cards(out_abs: String) -> void:
	for child: Node in _sv.get_children():
		child.queue_free()
	await get_tree().process_frame

	var ground := ColorRect.new()
	ground.size = Vector2(_sv.size)
	ground.color = Color(0.20, 0.26, 0.19)
	_sv.add_child(ground)

	var scene: PackedScene = load(
		"res://source/client/ui/hud/xp_tracker/xp_tracker_tooltip.tscn"
	) as PackedScene
	var cases: Array = [
		[&"fletching", 27, 0.95],
		[&"harvesting", 18, 0.4],
		[&"mining", 99, 0.0],
	]
	var y: float = 12.0
	for case: Array in cases:
		var card: XpTrackerTooltip = scene.instantiate() as XpTrackerTooltip
		_sv.add_child(card)
		var level: int = case[1]
		var to_next: int = SkillXp.xp_to_next(level)
		card.fill(
			case[0], level, int(round(float(case[2]) * float(to_next))), to_next,
			XpTrackerHud.tint_for(case[0]),
		)
		card.reset_size()
		card.position = Vector2(12.0, y)
		y += card.size.y + 10.0

	await get_tree().process_frame
	await get_tree().process_frame
	var dest: String = out_abs.path_join("xp-tracker-card.png")
	var image: Image = _sv.get_texture().get_image()
	image.resize(image.get_width() * ZOOM, image.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	image.save_png(dest)
	print("wrote ", dest)


## Feed the tracker through its real signal handler so it dresses itself from
## JobRegistry and SKILL_TINTS exactly as it would in game.
func _drive(tracker: Control, case: Array) -> void:
	var job: StringName = case[0]
	var level: int = case[1]
	var ratio: float = case[2]
	var to_next: int = SkillXp.xp_to_next(level)
	# leveled_up false for every cell: the level-up CELL is posed separately by
	# calling the wrap's peak directly, because driving it for real would put the
	# burst 0.22s away and the capture would miss it.
	tracker.call(
		&"_on_skill_xp_gained", job, 120, int(round(ratio * float(to_next))), level, false
	)
	tracker.modulate.a = 1.0


## Pin the arc where the case wants it. Done after the tweens have started so
## this overrides them rather than racing them.
func _pin_fill(tracker: Control, ratio: float) -> void:
	var arc: TextureProgressBar = tracker.get_node("Gauge/Arc") as TextureProgressBar
	arc.value = ratio * arc.max_value
	# _process places the spark from the pinned value on the next frame.


## Hammer one tracker with rapid ticks, the fletching-arrows case: the
## accumulator should leave ONE label reading the sum, not six overlapping ones.
func _spam_drops(tracker: Control, job: StringName) -> void:
	var drops: Node = tracker.get_node("Drops")
	for amount: int in [45, 45, 45, 60, 60, 45]:
		drops.call(&"push", job, amount, XpTrackerHud.tint_for(job))


func _label(text: String, x: int, y: int) -> void:
	var label: Label = PixelUI.text(text, 10, Color(1, 0.88, 0.55))
	label.position = Vector2(float(x), float(y))
	label.size = Vector2(float(CELL), 14.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override(&"outline_size", 4)
	_sv.add_child(label)
