extends Node
## Screenshot proof of the eleven level-99 title looks, over BOTH a dark and a
## bright backdrop.
##
## Runs as a SCENE, not a `-s` tool, and windowed — headless has no rasteriser
## and these are shaders and particles:
##   godot --path . --mode=client res://tools/render_skill_master_titles.tscn
##
## The two backdrops are the whole point of this tool. Every one of these titles
## is bright by design, and the failure mode they were built to avoid is not
## "looks dull" — it is a white-gold title becoming unreadable over pale desert
## sand. A capture on a dark background alone would show all eleven looking
## excellent and prove nothing about the case that actually matters, so the same
## row is rendered twice and the dark contrast outline is judged on the light one.

const OUT: String = "res://previews/skill-master-titles.png"
const ZOOM: int = 2
## Rows are laid out against the real viewport, not this — see _canvas().
const VIEW: Vector2i = Vector2i(400, 470)

## Deliberately near the worst case for a bright title: a pale, warm, high-value
## ground, like sand or snow in daylight.
const BRIGHT_GROUND: Color = Color(0.86, 0.83, 0.74)
const DARK_GROUND: Color = Color(0.11, 0.12, 0.16)

## Seconds to let the shaders and emitters reach a representative frame. The
## slower looks (the miner's ore seam, the priest's ray fan) are on multi-second
## cycles and their first frame is not what they look like.
const SETTLE_S: float = 2.6


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

	var titles: Array = SkillMasterTitles.roster()
	# One title per ROW rather than side by side. These are three-word names with
	# a particle halo around them, and packing several across a line overlaps them
	# into an unreadable smear - which tells you nothing about any of them.
	var half: int = int(ceil(float(titles.size()) / 2.0))

	# Top half of the frame dark, bottom half bright, with the same eleven titles
	# split across both so every look is seen against one of them and the pair is
	# directly comparable.
	_ground(root, Rect2(Vector2.ZERO, Vector2(canvas.x, canvas.y * 0.5)), DARK_GROUND)
	_ground(root, Rect2(Vector2(0.0, canvas.y * 0.5), Vector2(canvas.x, canvas.y * 0.5)), BRIGHT_GROUND)

	for i: int in titles.size():
		var row: Dictionary = titles[i]
		var dark: bool = i < half
		var index: int = i if dark else i - half
		var rows_here: int = half if dark else titles.size() - half
		var band_top: float = 0.0 if dark else canvas.y * 0.5
		var y: float = band_top + canvas.y * 0.5 * (float(index) + 0.5) / float(rows_here)
		_title(root, str(row.get("name", "")), Vector2(canvas.x * 0.5, y))

	var elapsed: float = 0.0
	while elapsed < SETTLE_S:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT)
	get_tree().quit()


func _ground(root: Node2D, rect: Rect2, color: Color) -> void:
	var ground: ColorRect = ColorRect.new()
	ground.color = color
	ground.position = rect.position
	ground.size = rect.size
	# Title particles sit at absolute z 5 (TitleParticles.NAMEPLATE_Z), so the
	# backdrop has to go well below that or it paints straight over them.
	ground.z_as_relative = false
	ground.z_index = -10
	root.add_child(ground)


## One title, built the same way the nameplate builds it — same Label, same
## TitleVfx entry point — so what is captured is what ships rather than a
## reimplementation that could drift from it.
func _title(root: Node2D, name: String, at: Vector2) -> void:
	var label: Label = Label.new()
	label.text = "« %s »" % name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 17)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_as_relative = false
	label.z_index = TitleParticles.NAMEPLATE_Z
	root.add_child(label)
	label.reset_size()
	label.position = at - label.size * 0.5
	TitleVfx.apply_to_label(label, name)
