extends Node
## Screenshot proof of the ten green-log boss titles, over BOTH a dark and a
## bright backdrop.
##
##   godot --path . --mode=client res://tools/render_green_log_titles.tscn
##
## Runs as a SCENE and windowed — headless has no rasteriser and these are
## shaders and particles. Same shape as tools/render_vip_titles.gd, and for the
## same reason: each title appears on BOTH grounds, because the failure worth
## catching is not "looks dull", it is Dunecrowned's desert gold or Orcsbane's
## near-white polish going unreadable over pale sand. A dark-only capture would
## show all ten looking excellent and prove nothing about the case that matters.
##
## Titles are drawn through TitleVfx.apply_to_label — the real nameplate entry
## point — so what is captured is what ships. It also proves the whole resolution
## chain works: title string -> TitleCatalog.spec -> CollectionLogTitles ->
## vip_tier -> VipTierProfile -> shader uniforms + emitter stack.
##
## No Camera2D on purpose: VipTitleEffect treats "no camera" as close, so every
## title renders its full layer set rather than the LOD-thinned version.

const OUT: String = "res://previews/green-log-titles.png"
const ZOOM: int = 2
const VIEW: Vector2i = Vector2i(560, 640)

## Near the worst case for a bright title: pale, warm, high-value ground.
const BRIGHT_GROUND: Color = Color(0.86, 0.83, 0.74)
const DARK_GROUND: Color = Color(0.11, 0.12, 0.16)

## Emitters on multi-second cycles (Sporebound's drift, Bloodbrand's mist) do not
## look like themselves on frame one.
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

	# Read off the log resources, so the capture cannot drift from the content.
	var titles: PackedStringArray = PackedStringArray()
	for path: String in FileUtils.get_all_file_at(
			"res://source/common/gameplay/collection_log/logs/", "*.tres"):
		var boss_log: BossCollectionLog = ResourceLoader.load(path) as BossCollectionLog
		if boss_log != null and not boss_log.green_log_title_text.is_empty():
			titles.append(boss_log.green_log_title_text)
	titles.sort()

	# Two columns per band so ten titles fit without shrinking the type.
	_ground(root, Rect2(Vector2.ZERO, Vector2(canvas.x, canvas.y * 0.5)), DARK_GROUND)
	_ground(root, Rect2(Vector2(0.0, canvas.y * 0.5),
		Vector2(canvas.x, canvas.y * 0.5)), BRIGHT_GROUND)

	var rows: int = int(ceil(titles.size() / 2.0))
	for band: int in 2:
		var band_top: float = canvas.y * 0.5 * float(band)
		for i: int in titles.size():
			var col: int = i / rows
			var row: int = i % rows
			var x: float = canvas.x * (0.25 + 0.5 * float(col))
			var y: float = band_top + canvas.y * 0.5 * (float(row) + 0.6) / float(rows + 0.2)
			_title(root, titles[i], Vector2(x, y))

	var elapsed: float = 0.0
	while elapsed < SETTLE_S:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("wrote %s  titles=%d" % [OUT, titles.size()])
	get_tree().quit()


func _ground(root: Node2D, rect: Rect2, color: Color) -> void:
	var ground: ColorRect = ColorRect.new()
	ground.color = color
	ground.position = rect.position
	ground.size = rect.size
	# Title particles sit at absolute z 5, so the backdrop must go well below it
	# or it paints straight over them.
	ground.z_as_relative = false
	ground.z_index = -10
	root.add_child(ground)


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
