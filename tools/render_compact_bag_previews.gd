extends Node
## Screenshot the REAL compact (dock) inventory panel with its new bag tabs, at
## the shipping 960x540 client size.
##
## Scene, not `-s`, and windowed — see render_bank_previews.gd for why.
##   godot --path . --mode=client res://tools/render_compact_bag_previews.tscn

const PANEL_SCENE: String = "res://source/client/ui/compact_menus/compact_menu_host.tscn"
const HOST_SCRIPT: String = "res://source/client/ui/compact_menus/compact_menu_host.gd"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540

var _sv: SubViewport
var _panel: Control
var _caption: Label
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

	var ground := ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.35, 0.22, 0.14)
	_sv.add_child(ground)

	# The panel places itself relative to its parent Control (the HUD), so it
	# needs a full-size stand-in or it renders in the corner.
	var hud := Control.new()
	hud.size = Vector2(W, H)
	_sv.add_child(hud)

	var scene: PackedScene = load(PANEL_SCENE) as PackedScene
	if scene == null:
		push_error("Could not load %s" % PANEL_SCENE)
		get_tree().quit(1)
		return
	_panel = scene.instantiate() as Control
	# compact_menu_host.tscn ships the EQUIPMENT script; hud.tscn overrides it
	# with compact_menu_host.gd per instance, so the rig must do the same or it
	# screenshots the wrong panel.
	_panel.set_script(load(HOST_SCRIPT))
	hud.add_child(_panel)

	_caption = Label.new()
	_caption.size = Vector2(W, 20)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override(&"font_size", 13)
	_caption.add_theme_color_override(&"font_color", Color(1, 0.85, 0.5))
	_caption.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.95))
	_caption.add_theme_constant_override(&"outline_size", 5)
	_caption.visible = false
	_sv.add_child(_caption)

	await get_tree().process_frame
	await get_tree().process_frame
	_panel.show()
	await get_tree().process_frame

	await _render_states()
	get_tree().quit(0)


## A full bag of REAL items, so previews prove icons and stack counts are
## legible at the shipping slot size instead of showing empty squares.
func _fill_fixture() -> void:
	var slugs: Array[StringName] = [
		&"iron_ore", &"coal_ore", &"mithril_ore", &"adamant_ore", &"runite_ore",
		&"oak_log", &"willow_log", &"maple_log", &"yew_log", &"logs",
		&"cooked_shrimp", &"cooked_trout", &"cooked_salmon", &"cooked_lobster",
		&"health_potion", &"greater_health_potion", &"mana_potion", &"bone",
		&"iron_bar", &"steel_bar", &"mithril_bar", &"healing_herb", &"frostpetal",
		&"sunwort", &"moonbloom", &"bloodcap", &"vial_of_water", &"bronze_arrow",
		&"sword_runite.item", &"iron_helmet",
	]
	var entries: Array[Dictionary] = []
	var uid: int = 1
	for slug: StringName in slugs:
		var item_id: int = ContentRegistryHub.id_from_slug(&"items", slug)
		if item_id <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item == null:
			continue
		var amount: int = [1, 7, 10, 42, 128, 999][uid % 6]
		entries.append({
			"uid": uid,
			"data": {"id": item_id, "a": amount, "bag": 0},
			"item": item,
		})
		uid += 1
	_panel._build_empty_grid(Inventory.MAX_SLOTS)
	_panel._display_entries(entries, BagOrder.sync_with_entries(entries))


func _apply(bags: int, active: int, pending: int) -> void:
	_panel.bag_count = bags
	_panel.active_bag = active
	_panel.pending_bag_purchase = pending
	_panel._update_bag_tabs()


func _settle() -> void:
	for _i: int in 8:
		await get_tree().process_frame


func _grab() -> Image:
	await _settle()
	return _sv.get_texture().get_image()


func _save(image: Image, file_name: String, scale: int = 2) -> void:
	if scale > 1:
		image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var dest: String = _out_abs.path_join(file_name)
	image.save_png(dest)
	print("SAVED ", dest, " size=", image.get_size())


func _render_states() -> void:
	var cells: Array = []
	for entry: Array in [
		[1, 0, -1, "1 BAG - BAG 2 BUYABLE (+), BAG 3 LOCKED"],
		[1, 0, 1, "BAG 2 ARMED - TAP AGAIN TO BUY"],
		[2, 1, -1, "BAG 2 OWNED AND OPEN"],
		[3, 2, -1, "ALL THREE OWNED - BAG 3 OPEN"],
	]:
		_apply(int(entry[0]), int(entry[1]), int(entry[2]))
		_fill_fixture()
		_caption.text = String(entry[3])
		_caption.visible = true
		cells.append(await _grab())
	_caption.visible = false
	_save(_montage(cells), "compact-bags.png", 1)


func _montage(cells: Array) -> Image:
	var gutter: int = 4
	var sheet: Image = Image.create_empty(
		W * 2 + gutter, H * 2 + gutter, false, Image.FORMAT_RGBA8
	)
	sheet.fill(Color(0.03, 0.035, 0.05))
	for i: int in cells.size():
		var cell: Image = cells[i]
		if cell.get_format() != sheet.get_format():
			cell.convert(sheet.get_format())
		var at := Vector2i((i % 2) * (W + gutter), (i / 2) * (H + gutter))
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), at)
	return sheet
