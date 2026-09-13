extends Node
## Frame sequence for a cosmetic SHOWCASE GIF: whole outfits worn on a real body,
## one standing and one walking, so a look can be judged in motion before it is
## sold. A still cannot show a trail at all, or a halo turning behind a head.
##
## Runs as a SCENE, windowed - headless has no rasteriser:
##   godot --path . --mode=client res://tools/render_cosmetic_showcase_gif.tscn \
##       -- --name=storm --outfit=aura_aether_arcs+halo_thunderhead_crown+trail_static_wake
##   python tools/encode_vip_gif.py <GIF_FRAMES dir> previews/cosmetic-storm.gif
##
## One row per --outfit (repeatable). Slugs joined with "+" are worn together.
## Trails are only mounted on the walker - standing still they draw nothing, by
## design - and every other slot is worn by both.
##
## Frames go to user://, outside the project, so nothing half-captured can be
## committed or imported.

const ZOOM: int = 3
const ROW_H: float = 92.0
const WIDTH: float = 300.0
const GROUND: Color = Color(0.13, 0.15, 0.19)
const FPS: int = 20
const FRAME_STRIDE: int = 3
const FRAMES: int = 150
## Settle for exactly one capture window and keep the SAME clock running into the
## capture. Resetting it teleported the walker at capture start and left a
## detached chain of trail on the floor in the first second of the GIF.
const SETTLE_WINDOWS: int = 1
## Walker travel, end to end. The capture window is exactly one out-and-back,
## so the GIF loops without a jump.
const TRAVEL: float = 150.0

const PRESET_DIR: String = "res://source/common/gameplay/cosmetics/presets/%s_preset.gd"

var _walkers: Array[Node2D] = []
var _walker_bodies: Array[AnimatedSprite2D] = []
var _walker_home: Array[float] = []


func _ready() -> void:
	var outfits: Array[PackedStringArray] = []
	var set_name: String = "showcase"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--outfit="):
			outfits.append(arg.trim_prefix("--outfit=").split("+", false))
		elif arg.begins_with("--name="):
			set_name = arg.trim_prefix("--name=")
	if outfits.is_empty():
		push_error("pass at least one --outfit=slug+slug")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(int(WIDTH), int(ROW_H * outfits.size())) * ZOOM
	call_deferred(&"_go", outfits, set_name)


func _canvas() -> Vector2:
	return get_viewport().get_visible_rect().size / float(ZOOM)


func _go(outfits: Array[PackedStringArray], set_name: String) -> void:
	var canvas: Vector2 = _canvas()
	# Zoom through the CANVAS, the way the game camera does, not by scaling a
	# parent: top_level layers (trail beads, ribbons, a familiar) ignore parent
	# scale and would render at a third of their in-game size.
	get_viewport().canvas_transform = Transform2D.IDENTITY.scaled(Vector2(ZOOM, ZOOM))
	var root: Node2D = Node2D.new()
	add_child(root)
	var ground: ColorRect = ColorRect.new()
	ground.color = GROUND
	ground.size = canvas
	ground.z_as_relative = false
	ground.z_index = -10
	root.add_child(ground)

	var row_h: float = canvas.y / float(outfits.size())
	for r: int in outfits.size():
		var feet_y: float = row_h * (float(r) + 0.72)
		_wear(root, outfits[r], Vector2(44.0, feet_y), false)
		var home: float = canvas.x * 0.62
		_walker_home.append(home)
		_walkers.append(_wear(root, outfits[r], Vector2(home, feet_y), true))

	var clock: float = 0.0
	var window: float = float(FRAMES) / float(FPS)
	while clock < window * float(SETTLE_WINDOWS):
		await get_tree().process_frame
		clock += get_process_delta_time()
		_drive(clock)

	var out: String = ProjectSettings.globalize_path("user://cosmetic_gif/%s/" % set_name)
	DirAccess.make_dir_recursive_absolute(out)
	for old: String in DirAccess.get_files_at(out):
		DirAccess.remove_absolute(out.path_join(old))
	for i: int in FRAMES:
		for _s: int in FRAME_STRIDE:
			await get_tree().process_frame
			clock += get_process_delta_time()
			_drive(clock)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("f%03d.png" % i))
	print("GIF_FRAMES ", out)
	get_tree().quit()


## Walk right, STOP, walk left, STOP, at constant speed, turning the body to face
## the way it is walking. The stops matter as much as the walking: a trail has to
## be seen finishing, and the idle-reactive looks (Idle Bloom, the familiar's
## orbit) only happen when the wearer stands still.
const WALK_SHARE: float = 0.3


func _drive(clock: float) -> void:
	var window: float = float(FRAMES) / float(FPS)
	var phase: float = fposmod(clock / window, 1.0)
	var x: float
	var heading_left: bool
	if phase < WALK_SHARE:
		x = lerpf(-1.0, 1.0, phase / WALK_SHARE)
		heading_left = false
	elif phase < 0.5:
		x = 1.0
		heading_left = false
	elif phase < 0.5 + WALK_SHARE:
		x = lerpf(1.0, -1.0, (phase - 0.5) / WALK_SHARE)
		heading_left = true
	else:
		x = -1.0
		heading_left = true
	for i: int in _walkers.size():
		_walkers[i].position.x = _walker_home[i] + x * TRAVEL * 0.5
		if _walker_bodies[i] != null:
			_walker_bodies[i].animation = &"run" if x > -1.0 and x < 1.0 else &"idle"
			_walker_bodies[i].flip_h = heading_left


func _wear(root: Node2D, slugs: PackedStringArray, at: Vector2, walking: bool) -> Node2D:
	var host: Node2D = Node2D.new()
	host.position = at
	root.add_child(host)
	# Built first, added last: presets that read the wearer (Chrono Echo, Shadow
	# Twin) need the body handed over, and it has to draw over the presets.
	var body: AnimatedSprite2D = _body(walking)
	for slug: String in slugs:
		if slug.begins_with("trail_") and not walking:
			continue
		var script: GDScript = load(PRESET_DIR % slug) as GDScript
		if script == null:
			push_error("no preset script for %s" % slug)
			continue
		var preset: Node2D = script.new()
		preset.set("is_preview", true)
		if "sprite_source" in preset:
			preset.set("sprite_source", body)
		host.add_child(preset)
	if body != null:
		host.add_child(body)
	if walking:
		_walker_bodies.append(body)
	return host


func _body(walking: bool) -> AnimatedSprite2D:
	var frames: SpriteFrames = ContentRegistryHub.load_by_id(
		&"sprites", PlayerSkins.starter_skin_id()
	) as SpriteFrames
	if frames == null:
		return null
	var want: StringName = &"run" if walking else &"idle"
	if not frames.has_animation(want):
		want = frames.get_animation_names()[0]
	var body: AnimatedSprite2D = AnimatedSprite2D.new()
	body.sprite_frames = frames
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.offset = Vector2(0, -30)   # feet on the origin, as in character.tscn
	body.animation = want
	body.play()
	return body
