extends Node
## Screenshot proof of the scripted cosmetic presets (see [CosmeticPresetLibrary])
## over a floor and stand-in bodies, so the layers are judged against something
## rather than against black.
##
## Runs as a SCENE, not a `-s` tool, and windowed - headless has no rasteriser and
## these are shaders and particles:
##   godot --path . --mode=client res://tools/render_cosmetic_presets.tscn
##
## The trails are DRIVEN: each one is walked back and forth across its cell for a
## few seconds before the capture, because a trail preset samples real movement
## and renders nothing at all standing still. That is the whole point of the
## rework, and it is also why a static screenshot of one would prove nothing.
##
## Two passes, two files: auras settle in place, trails need room to run.

const OUT_AURAS: String = "res://previews/cosmetic-auras.png"
const OUT_TRAILS: String = "res://previews/cosmetic-trails.png"
const ZOOM: int = 3
const VIEW: Vector2i = Vector2i(400, 150)

const AURAS: Array[String] = [
	"aura_toxic", "aura_verdant", "aura_blood",
	"aura_emberfrost", "aura_galaxy", "aura_gold",
]
const TRAILS: Array[String] = [
	"trail_toxic", "trail_blood", "trail_galaxy", "trail_gold", "trail_storm",
]

const PRESET_DIR: String = "res://source/common/gameplay/cosmetics/presets/%s_preset.gd"

## Seconds of real time each pass is allowed to run before the capture. Long
## enough for the slow layers (vines sprouting, glints firing, a pool bubbling)
## to have reached a representative frame rather than their first one.
const SETTLE_S: float = 3.4
## How far a trail walks each way across its cell, and how fast.
const WALK_PX: float = 30.0
const WALK_SPEED: float = 62.0

var _walkers: Array[Node2D] = []


func _ready() -> void:
	get_window().size = VIEW * ZOOM
	call_deferred(&"_go")


## The project's own stretch settings decide the viewport size, which is NOT the
## window size we just asked for - laying out against VIEW leaves a dead margin
## down two sides of every capture. Measure instead.
func _canvas() -> Vector2:
	return get_viewport().get_visible_rect().size / float(ZOOM)


func _go() -> void:
	await _pass(AURAS, OUT_AURAS, false)
	await _pass(TRAILS, OUT_TRAILS, true)
	get_tree().quit()


func _pass(slugs: Array[String], out: String, walking: bool) -> void:
	var root: Node2D = Node2D.new()
	root.scale = Vector2(ZOOM, ZOOM)
	add_child(root)
	_walkers.clear()

	var canvas: Vector2 = _canvas()
	var ground: ColorRect = ColorRect.new()
	ground.color = Color(0.13, 0.15, 0.19)
	ground.size = canvas
	# Every preset layer sits at z -1 (floor art), so the backdrop has to go below
	# that or it paints straight over them.
	ground.z_index = -10
	root.add_child(ground)

	var cell: float = canvas.x / float(slugs.size())
	for i: int in slugs.size():
		var at: Vector2 = Vector2(cell * (float(i) + 0.5), canvas.y * 0.62)
		if not walking:
			_body(root, at)
		_mount(root, slugs[i], at, walking)
		_label(root, at + Vector2(-cell * 0.5 + 3.0, canvas.y * 0.26), slugs[i])

	# Real time has to pass: particles, shaders and the walk all need it.
	var elapsed: float = 0.0
	while elapsed < SETTLE_S:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		_walk(elapsed)

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(out))
	print("wrote ", out)
	root.queue_free()
	await get_tree().process_frame


func _mount(root: Node2D, slug: String, at: Vector2, walking: bool) -> void:
	var script: GDScript = load(PRESET_DIR % slug) as GDScript
	if script == null:
		push_error("no preset script for %s" % slug)
		return
	var host: Node2D = Node2D.new()
	host.position = at
	root.add_child(host)
	host.add_child(script.new())
	if walking:
		_walkers.append(host)


## Walk every trail host back and forth. A triangle wave, not a sine: constant
## speed with a hard turn is what a player actually does, and the turn is the
## interesting case (it is where a mirrored strip trail used to point the wrong
## way).
func _walk(elapsed: float) -> void:
	var cell: float = _canvas().x / float(TRAILS.size())
	var period: float = 2.0 * WALK_PX / WALK_SPEED
	for i: int in _walkers.size():
		var phase: float = fposmod(elapsed + float(i) * 0.3, period) / period
		# Triangle wave in -1..1: out at constant speed, hard turn, back.
		var swing: float = (phase * 2.0 if phase < 0.5 else 2.0 - phase * 2.0) * 2.0 - 1.0
		_walkers[i].position.x = cell * (float(i) + 0.5) + swing * WALK_PX


## A stand-in body: an aura has to read as pooling AROUND someone, and a bare
## origin proves nothing about that.
func _body(root: Node2D, at: Vector2) -> void:
	var torso: ColorRect = ColorRect.new()
	torso.color = Color(0.72, 0.66, 0.55)
	torso.size = Vector2(10.0, 20.0)
	torso.position = at + Vector2(-5.0, -20.0)
	root.add_child(torso)
	var head: ColorRect = ColorRect.new()
	head.color = Color(0.84, 0.76, 0.64)
	head.size = Vector2(8.0, 8.0)
	head.position = at + Vector2(-4.0, -28.0)
	root.add_child(head)


func _label(root: Node2D, at: Vector2, text: String) -> void:
	var label: Label = Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override(&"font_size", 7)
	label.add_theme_color_override(&"font_color", Color(0.78, 0.80, 0.86))
	root.add_child(label)
