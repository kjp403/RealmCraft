extends Node
## Frame sequence for the VIP title showcase GIF. Writes numbered PNGs into
## user://vip_gif/ and prints the absolute directory; an encoder turns them into
## a GIF afterwards.
##
## Runs as a SCENE, windowed - headless has no rasteriser:
##   godot --path . --mode=client res://tools/render_vip_titles_gif.tscn
##
## PNG SEQUENCE, NOT A GIF, on purpose. Godot cannot write GIFs, and the pieces
## that matter here - the polish sweep and the particle motion - are the two
## things a single frame cannot show at all. Handing off a sequence keeps the
## palette quantisation and the frame timing in the encoder where they belong.
##
## THE BOTTOM ROW IS THE POINT. The four static rows show the metal and the
## emitters; the moving pair shows what a wearer actually looks like walking
## through a bank. CPUParticles2D emits in GLOBAL space, so particles stay where
## they were born while the nameplate moves on - the trail is not simulated
## anywhere, it falls out of the emitter being carried.

const DIR: String = "user://vip_gif/"
const ZOOM: int = 2
const VIEW: Vector2i = Vector2i(440, 316)
const GROUND: Color = Color(0.085, 0.09, 0.115)

## Real seconds captured, and the playback rate the encoder is told to use.
## FRAME_STRIDE is how many engine frames pass between captures - at 60 fps a
## stride of 3 lands 20 captures per second, so the GIF runs at wall-clock speed
## rather than in slow motion.
const FPS: int = 20
const FRAME_STRIDE: int = 3
const FRAMES: int = 64

## Let the emitters fill in before the first capture. Every layer starts empty,
## and a GIF that opens on four bare titles wastes its first half second on the
## one state the effect never actually sits in.
const SETTLE_S: float = 2.2

## The moving pair's travel, in canvas units either side of centre.
const TRAVEL: float = 104.0

## Full back-and-forth cycles per second, chosen so the pair completes EXACTLY
## one cycle over the captured window (FRAMES / FPS seconds). That is what makes
## the GIF loop without a jump: the last frame's positions are the first frame's.
const TRAVEL_CYCLES: float = 1.0

var _movers: Array[Label] = []
var _mover_home: Array[Vector2] = []


func _ready() -> void:
	get_window().size = VIEW * ZOOM
	call_deferred(&"_go")


func _canvas() -> Vector2:
	return get_viewport().get_visible_rect().size / float(ZOOM)


func _go() -> void:
	var canvas: Vector2 = _canvas()
	var root: Node2D = Node2D.new()
	root.scale = Vector2(ZOOM, ZOOM)
	add_child(root)

	var ground: ColorRect = ColorRect.new()
	ground.color = GROUND
	ground.size = canvas
	ground.z_as_relative = false
	ground.z_index = -10
	root.add_child(ground)

	_caption(root, Vector2(12.0, 8.0), "VIP TITLE VFX", Color(0.78, 0.80, 0.86))
	var y: float = 42.0
	for slug: String in TitleCatalog.vip_tier_slugs():
		var name: String = str((TitleCatalog.PREMIUM[slug] as Dictionary).get("name", ""))
		_title(root, name, Vector2(canvas.x * 0.5, y), false)
		y += 46.0

	var rule: ColorRect = ColorRect.new()
	rule.color = Color(1.0, 1.0, 1.0, 0.07)
	rule.position = Vector2(12.0, y - 12.0)
	rule.size = Vector2(canvas.x - 24.0, 1.0)
	root.add_child(rule)
	_caption(root, Vector2(12.0, y - 6.0), "IN MOTION - EMITTERS TRAIL", Color(0.55, 0.57, 0.64))

	# One of each family, so the moving row also shows the mastery gradient now
	# that it is reading label space rather than the font atlas.
	_title(root, "Diamond Donator", Vector2(canvas.x * 0.5, y + 26.0), true)
	_title(root, "Slayer Master", Vector2(canvas.x * 0.5, y + 66.0), true)

	var settled: float = 0.0
	while settled < SETTLE_S:
		await get_tree().process_frame
		settled += get_process_delta_time()
		_drive(settled)

	var out: String = ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(out)
	# The motion clock RESTARTS at the first captured frame, so the sine that
	# drives the moving pair begins and ends at the same phase across the window
	# and the GIF loops cleanly. The settle pass above deliberately runs on the
	# same clock so the emitters are already mid-flight when capture opens.
	var clock: float = 0.0
	for i: int in FRAMES:
		for _s: int in FRAME_STRIDE:
			await get_tree().process_frame
			clock += get_process_delta_time()
			_drive(clock)
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		image.save_png(out.path_join("f%03d.png" % i))
	print("GIF_FRAMES ", out)
	print("GIF_FPS ", FPS)
	get_tree().quit()


## Slide the moving pair in opposite directions. Driven off an explicit clock
## rather than each label's own _process, so the capture loop and the motion
## cannot drift apart while the loop is awaiting a frame_post_draw.
func _drive(clock: float) -> void:
	var window: float = float(FRAMES) / float(FPS)
	for i: int in _movers.size():
		var dir: float = 1.0 if i % 2 == 0 else -1.0
		var offset: float = sin(clock / window * TRAVEL_CYCLES * TAU) * TRAVEL * dir
		_movers[i].position.x = _mover_home[i].x + offset


func _title(root: Node2D, title: String, at: Vector2, moving: bool) -> void:
	var label: Label = Label.new()
	label.text = "« %s »" % title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 17)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_as_relative = false
	label.z_index = VipTitleEffect.NAMEPLATE_Z
	root.add_child(label)
	label.reset_size()
	label.position = at - label.size * 0.5
	TitleVfx.apply_to_label(label, title)
	if moving:
		_movers.append(label)
		_mover_home.append(label.position)


func _caption(root: Node2D, at: Vector2, text: String, color: Color) -> void:
	var l: Label = Label.new()
	l.text = text
	l.position = at
	l.add_theme_font_size_override(&"font_size", 9)
	l.add_theme_color_override(&"font_color", color)
	root.add_child(l)
