extends Node
## Screenshot proof of the four VIP donation tiers, over BOTH a dark and a bright
## backdrop.
##
## Runs as a SCENE, not a `-s` tool, and windowed - headless has no rasteriser
## and these are shaders and particles:
##   godot --path . --mode=client res://tools/render_vip_titles.tscn
##
## EACH TIER APPEARS TWICE, once on each ground, rather than four split across
## the two. The failure this tool exists to catch is not "looks dull" - it is a
## white-gold or diamond-white title becoming unreadable over pale desert sand,
## and a capture on dark ground alone would show all four looking excellent and
## prove nothing about the case that matters. Four titles is few enough to afford
## the honest version.

const OUT: String = "res://previews/vip-titles.png"
const ZOOM: int = 2
## Rows are laid out against the real viewport, not this - see _canvas().
const VIEW: Vector2i = Vector2i(420, 430)

## Deliberately near the worst case for a bright title: a pale, warm, high-value
## ground, like sand or snow in daylight.
const BRIGHT_GROUND: Color = Color(0.86, 0.83, 0.74)
const DARK_GROUND: Color = Color(0.11, 0.12, 0.16)

## Seconds to let the shaders and emitters reach a representative frame. Silver's
## fog and Golden's leaf drift are on multi-second cycles and their first frame
## is not what they look like.
const SETTLE_S: float = 2.8


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

	var titles: PackedStringArray = PackedStringArray()
	for slug: String in TitleCatalog.vip_tier_slugs():
		titles.append(str((TitleCatalog.PREMIUM[slug] as Dictionary).get("name", "")))

	_ground(root, Rect2(Vector2.ZERO, Vector2(canvas.x, canvas.y * 0.5)), DARK_GROUND)
	_ground(
		root,
		Rect2(Vector2(0.0, canvas.y * 0.5), Vector2(canvas.x, canvas.y * 0.5)),
		BRIGHT_GROUND
	)

	for band: int in 2:
		var band_top: float = canvas.y * 0.5 * float(band)
		for i: int in titles.size():
			var y: float = band_top + canvas.y * 0.5 * (float(i) + 0.5) / float(titles.size())
			_title(root, titles[i], Vector2(canvas.x * 0.5, y))

	var elapsed: float = 0.0
	while elapsed < SETTLE_S:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote ", OUT, " tiers=", titles.size())
	get_tree().quit()


func _ground(root: Node2D, rect: Rect2, color: Color) -> void:
	var ground: ColorRect = ColorRect.new()
	ground.color = color
	ground.position = rect.position
	ground.size = rect.size
	# Title particles sit at absolute z 5 (VipTitleEffect.NAMEPLATE_Z), so the
	# backdrop has to go well below that or it paints straight over them.
	ground.z_as_relative = false
	ground.z_index = -10
	root.add_child(ground)


## One title, built the same way the nameplate builds it - same Label, same
## TitleVfx entry point - so what is captured is what ships rather than a
## reimplementation that could drift from it.
##
## There is no Camera2D in this scene, and that is deliberate: VipTitleEffect
## treats "no camera" as close, so every tier renders its FULL layer set here
## instead of the reduced one a distant player would get. A proof that captured
## the LOD-thinned version would understate what a donor actually sees.
func _title(root: Node2D, title: String, at: Vector2) -> void:
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
