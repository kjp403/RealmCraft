extends Node
## Screenshot the REAL QuickTravelMenu and the REAL pink Wayfarer sprite, so the
## board and the NPC can be reviewed without a running server.
##
## Runs as a SCENE and WINDOWED (headless has no rasteriser, so a capture there
## comes back blank), mirroring render_bank_previews.gd:
##   godot --path . --mode=client res://tools/render_quick_travel_previews.tscn
##
## The menu normally fills itself from a travel.quote reply. There is no server
## here, so the rig calls the menu's own _render() with quote dictionaries shaped
## exactly like the handler's — same keys, same types. That exercises the real
## layout code (rows, lock states, surge banner, affordability colours) rather
## than a mock of it.

const MENU_SCENE: String = "res://source/client/ui/menus/quick_travel/quick_travel_menu.tscn"
const WAYFARER: String = "res://source/common/gameplay/characters/npc/npcs/wayfarer.tres"
const SCHOLAR: String = "res://source/common/gameplay/characters/sprite_frames/scholar_cataloguer.tres"
const OUT_DIR: String = "res://previews"
## The project's shipping viewport — capture at the size the client renders.
const W: int = 960
const H: int = 540

var _sv: SubViewport
var _menu: Control
var _out_abs: String


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_out_abs = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out_abs)

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, H)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.transparent_bg = false
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	# Stand-in for the map behind the menu, so the shell's dim backdrop reads the
	# way it does over a real hub rather than over pure black.
	var ground: ColorRect = ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.20, 0.17, 0.22)
	_sv.add_child(ground)

	_menu = (load(MENU_SCENE) as PackedScene).instantiate() as Control
	_sv.add_child(_menu)

	await get_tree().process_frame
	await get_tree().process_frame

	# 1. Standard fares, plenty of gold, standing in the Guild Hall.
	_menu._render(_quote(1.0, 0, 120000))
	_save(await _grab(), "quick-travel-board.png")

	# 2. Surging, and short of gold for the top tiers -- the state where the
	#    board has to communicate the most.
	_menu._render(_quote(2.0, 5, 30000))
	_save(await _grab(), "quick-travel-surge.png")

	await _render_wayfarer()
	get_tree().quit(0)


## A travel.quote reply, shaped exactly like travel.quote.gd builds it.
## [param gold] drives the affordability colouring; [param surge] the banner.
func _quote(surge: float, rides: int, gold: int) -> Dictionary:
	var rows: Array = []
	var desk: QuickTravelInteraction = _desk()
	for i: int in desk.destinations.size():
		var dest: QuickTravelDestination = desk.destinations[i]
		var uncapped: int = int(ceil(float(dest.fee) * surge))
		var fee: int = mini(uncapped, QuickTravelService.FARE_CAP)
		# Row 0 is the hub we are pretending to stand in; row 4 stands in for a
		# wardstone the test character has not earned.
		var lock: String = ""
		if i == 0:
			lock = QuickTravelDesk.LOCK_HERE
		elif i == 4:
			lock = "Needs the desert wardstone."
		rows.append({
			"index": i,
			"label": dest.display_label(),
			"blurb": dest.blurb,
			"base_fee": dest.fee,
			"fee": fee,
			"capped": uncapped > fee,
			"lock": lock,
			"affordable": gold >= fee,
		})
	return {
		"ok": true,
		"gold": gold,
		"destinations": rows,
		"surge": surge,
		"rides": rides,
		"free_rides": QuickTravelService.SURGE_AFTER_TRIPS,
		"fare_cap": QuickTravelService.FARE_CAP,
		"window_s": int(QuickTravelService.WINDOW_S),
		"cools_in_s": 372,
	}


func _desk() -> QuickTravelInteraction:
	var npc_res: NPCResource = load(WAYFARER) as NPCResource
	for inter: NPCInteraction in npc_res.interactions:
		if inter is QuickTravelInteraction:
			return inter as QuickTravelInteraction
	return null


## Side-by-side of the stock Scholar and the Wayfarer's recoloured variant, drawn
## through the SHIPPING material — proof the swap happens on the GPU path the
## game uses, not just in an offline colour experiment.
func _render_wayfarer() -> void:
	var strip: SubViewport = SubViewport.new()
	strip.size = Vector2i(320, 200)
	strip.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	strip.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	strip.transparent_bg = false
	strip.disable_3d = true
	get_tree().root.add_child(strip)

	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(320, 200)
	bg.color = Color(0.12, 0.12, 0.14)
	strip.add_child(bg)

	var frames: SpriteFrames = load(SCHOLAR) as SpriteFrames
	var npc_res: NPCResource = load(WAYFARER) as NPCResource

	for i: int in 2:
		var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
		sprite.sprite_frames = frames
		sprite.animation = &"idle"
		sprite.frame = 0
		sprite.scale = Vector2(2, 2)
		sprite.position = Vector2(90 + i * 140, 120)
		if i == 1:
			sprite.material = npc_res.skin_material
		strip.add_child(sprite)

		var caption: Label = Label.new()
		caption.text = "Scholar (stock)" if i == 0 else "Wayfarer (pink)"
		caption.size = Vector2(140, 18)
		caption.position = Vector2(20 + i * 140, 18)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override(&"font_size", 12)
		caption.add_theme_color_override(
			&"font_color", Color(0.7, 0.75, 1.0) if i == 0 else Color(1.0, 0.41, 0.71)
		)
		strip.add_child(caption)

	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save(strip.get_texture().get_image(), "wayfarer-npc.png", 3)


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return _sv.get_texture().get_image()


func _save(image: Image, file_name: String, scale: int = 2) -> void:
	if scale > 1:
		image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var dest: String = _out_abs.path_join(file_name)
	image.save_png(dest)
	print("SAVED ", dest, " size=", image.get_size())
