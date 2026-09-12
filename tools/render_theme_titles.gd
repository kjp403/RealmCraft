extends Node
## Screenshot proof of the eight colour-matched shop titles, over BOTH a dark and
## a bright backdrop.
##
## Runs as a SCENE, not a `-s` tool, and windowed - headless has no rasteriser and
## these are shaders and particles:
##   godot --path . --mode=client res://tools/render_theme_titles.tscn
##
## EACH TITLE APPEARS TWICE, once on each ground, for the same reason the ladder's
## proof does it: the failure worth catching is not "looks dull", it is Glacial
## Sovereign's ice-white or Alchemical Exarch's gold becoming unreadable over pale
## desert sand, and a capture on dark ground alone would show all eight looking
## excellent and prove nothing about the case that matters.
##
## THE LIST COMES FROM THE CATALOG, not from a copy here - a theme added later
## appears in the proof by itself rather than being quietly left out of it.

const OUT: String = "res://previews/theme-titles.png"
## The second sheet: the same eight WALKING, so their movement trails are on.
const OUT_TRAILS: String = "res://previews/theme-title-trails.png"
const ZOOM: int = 2
## Rows are laid out against the real viewport, not this - see _canvas().
const VIEW: Vector2i = Vector2i(460, 520)

## Deliberately near the worst case for a bright title: a pale, warm, high-value
## ground, like sand or snow in daylight.
const BRIGHT_GROUND: Color = Color(0.86, 0.83, 0.74)
const DARK_GROUND: Color = Color(0.11, 0.12, 0.16)

## Seconds to let the shaders and emitters reach a representative frame. The Storm
## title's strike and the Exarch's sunburst are on multi-second cycles and their
## first frame is not what they look like.
const SETTLE_S: float = 3.0

## How far a walking title travels each way, and how fast, on the trail sheet.
##
## The speed has to clear VipTitleEffect.MOVE_EPSILON per MOVE_INTERVAL tick by a
## comfortable margin or the movement gate never opens - which is the whole thing
## this pass is proving, so a capture that quietly failed the test and showed no
## trail would be worse than no capture at all.
const WALK_PX: float = 120.0
const WALK_SPEED: float = 70.0

## Titles walked on the trail sheet, so their layers can be driven.
var _walkers: Array[Label] = []
var _home: Array[float] = []


func _ready() -> void:
	get_window().size = VIEW * ZOOM
	call_deferred(&"_go")


func _canvas() -> Vector2:
	return get_viewport().get_visible_rect().size / float(ZOOM)


func _go() -> void:
	await _still_pass()
	await _walk_pass()
	get_tree().quit()


## THE TRAIL SHEET. Every title walking, mounted the way a NAMEPLATE mounts it -
## preview false - so the movement gate is the real one rather than the shelf's
## always-on override. If a trail is missing here it is missing in the world.
##
## Deliberately the CROWD case as well: eight bought titles on screen is past
## VipTitleEffect.CROWD_RICH_LIMIT, so the ambient `detail` layers are thinned
## exactly as they would be in a bank. The trails are not detail and must still be
## there - that is the other half of what this capture is for.
func _walk_pass() -> void:
	var canvas: Vector2 = _canvas()
	var root: Node2D = Node2D.new()
	root.scale = Vector2(ZOOM, ZOOM)
	add_child(root)
	_ground(root, Rect2(Vector2.ZERO, canvas), DARK_GROUND)

	var titles: PackedStringArray = _titles()
	for i: int in titles.size():
		var y: float = canvas.y * (float(i) + 0.5) / float(titles.size())
		var label: Label = _title(root, titles[i], Vector2(canvas.x * 0.5, y), false)
		_walkers.append(label)
		_home.append(label.position.x)

	var elapsed: float = 0.0
	while elapsed < SETTLE_S:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		_walk(elapsed)

	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT_TRAILS))
	print("wrote ", OUT_TRAILS, " titles=", titles.size())
	root.queue_free()
	await get_tree().process_frame


## Back and forth, so a trail is laid down, walked away from and walked back
## across - which is the only way one capture shows both the wake and the wearer.
func _walk(elapsed: float) -> void:
	for i: int in _walkers.size():
		var label: Label = _walkers[i]
		if not is_instance_valid(label):
			continue
		# Phase-shifted per row so the eight are not all at the same point of the
		# same stride, which would make the sheet read as one effect repeated.
		var phase: float = elapsed * WALK_SPEED / WALK_PX + float(i) * 0.21
		label.position.x = _home[i] + sin(phase * PI) * WALK_PX * 0.5


func _titles() -> PackedStringArray:
	var titles: PackedStringArray = PackedStringArray()
	for key: StringName in CosmeticThemes.keys():
		var slug: String = CosmeticThemes.title_slug(key)
		titles.append(str(TitleCatalog.premium_entry(slug).get("name", "")))
	return titles


func _still_pass() -> void:
	var canvas: Vector2 = _canvas()
	var root: Node2D = Node2D.new()
	root.scale = Vector2(ZOOM, ZOOM)
	add_child(root)

	var titles: PackedStringArray = _titles()

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
	print("wrote ", OUT, " titles=", titles.size())
	root.queue_free()
	await get_tree().process_frame


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
## [param preview] is the shelf's always-on override. TRUE on the still sheet,
## where nothing walks anywhere and the movement-gated layers would otherwise
## never emit; FALSE on the trail sheet, where the point is to exercise the real
## gate. See TitleVfx.apply_to_label.
func _title(root: Node2D, title: String, at: Vector2, preview: bool = true) -> Label:
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
	TitleVfx.apply_to_label(label, title, preview)
	return label
