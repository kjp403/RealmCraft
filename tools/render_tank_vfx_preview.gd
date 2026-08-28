extends Node
## Screenshot proof of the two DRAWN tank visuals — Spectral Ward's orbiting
## shields ([ShieldWard]) and the Paladin's Might ground circle
## ([SanctuaryRing]) — at all three ranks, over a floor and a stand-in body so the
## translucency is judged against something rather than against black.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_tank_vfx_preview.tscn
##
## Each ward column is frozen at a DIFFERENT point in its orbit, so one still
## frame shows the front-of-body and behind-body reads that the animation cycles
## through — a single shared phase would make the depth fade look like a bug.

const OUT: String = "res://previews/tank-vfx.png"
const ZOOM: int = 3
const VIEW: Vector2i = Vector2i(320, 180)

## Rank tunings, mirrored from the spectral_ward*.tres shield_count / colours.
const WARD_RANKS: Array = [
	{"n": 1, "col": Color(0.55, 0.78, 1.0), "phase": 0.35},
	{"n": 2, "col": Color(0.62, 0.84, 1.0), "phase": 1.10},
	{"n": 3, "col": Color(0.72, 0.92, 1.0), "phase": 1.85},
]


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	var root: Node2D = Node2D.new()
	root.scale = Vector2(ZOOM, ZOOM)
	add_child(root)

	var ground: ColorRect = ColorRect.new()
	ground.color = Color(0.13, 0.15, 0.19)
	ground.size = Vector2(VIEW)
	# Both visuals sit at z_index -1 (they are floor / under-body art), so the
	# backdrop has to go BELOW that or it paints straight over them.
	ground.z_index = -10
	root.add_child(ground)

	# Paladin's Might first (z below), one circle at the small and large ranks.
	_barrier(root, Vector2(78.0, 128.0), 34.0, Color(1.0, 0.88, 0.55), 1.5)
	_barrier(root, Vector2(215.0, 128.0), 48.0, Color(1.0, 0.94, 0.72), 4.0)
	_label(root, Vector2(46.0, 166.0), "Paladin's Might  ·  rank 1 / rank 3")

	var x: float = 60.0
	for rank: Dictionary in WARD_RANKS:
		_body(root, Vector2(x, 56.0))
		_ward(root, Vector2(x, 56.0), rank)
		_label(root, Vector2(x - 22.0, 78.0), "Spectral Ward %d" % int(rank["n"]))
		x += 100.0

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	get_tree().quit()


## A stand-in for the tank: the ward has to read as going AROUND a body, so a
## bare origin would prove nothing about the depth fade.
func _body(root: Node2D, at: Vector2) -> void:
	var torso: ColorRect = ColorRect.new()
	torso.color = Color(0.72, 0.66, 0.55)
	torso.size = Vector2(10.0, 18.0)
	torso.position = at + Vector2(-5.0, -18.0)
	root.add_child(torso)


## Drops a [ShieldWard] and hand-advances it to [code]phase[/code] seconds, so the
## screenshot catches a chosen point of the orbit instead of frame zero.
func _ward(root: Node2D, at: Vector2, rank: Dictionary) -> void:
	var ward: ShieldWard = ShieldWard.new()
	ward.duration = 60.0 # long enough that the fade-out never touches the shot
	ward.shield_count = int(rank["n"])
	ward.color = rank["col"]
	ward.position = at
	root.add_child(ward)
	ward._process(float(rank["phase"]))


func _barrier(root: Node2D, at: Vector2, radius: float, color: Color, phase: float) -> void:
	var ring: SanctuaryRing = SanctuaryRing.new()
	ring.duration = 60.0
	ring.radius = radius
	ring.color = color
	ring.position = at
	root.add_child(ring)
	ring._process(phase)


func _label(root: Node2D, at: Vector2, text: String) -> void:
	var lab: Label = Label.new()
	lab.text = text
	lab.add_theme_font_size_override(&"font_size", 7)
	lab.add_theme_color_override(&"font_color", Color(0.75, 0.78, 0.85))
	lab.position = at
	root.add_child(lab)
