extends Node
## Screenshot the REAL InventoryMenu bag tabs at the shipping 960x540 client
## size, across the ownership states players will actually see.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_inventory_bag_previews.tscn
##
## Same reason as render_bank_previews.gd: `-s` starts a bare SceneTree with no
## autoloads, and inventory_menu.gd references ClientState / Client / Toaster,
## so under `-s` it fails to COMPILE and there is nothing to screenshot.

const MENU_SCENE: String = "res://source/client/ui/menus/inventory/inventory_menu.tscn"
const OUT_DIR: String = "res://previews"
const W: int = 960
const H: int = 540

var _sv: SubViewport
var _menu: Control
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
	ground.color = Color(0.24, 0.30, 0.22)
	_sv.add_child(ground)

	var scene: PackedScene = load(MENU_SCENE) as PackedScene
	if scene == null:
		push_error("Could not load %s" % MENU_SCENE)
		get_tree().quit(1)
		return
	_menu = scene.instantiate() as Control
	_sv.add_child(_menu)

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
	_load_fixture()

	await _render_states()
	get_tree().quit(0)


# --- Fixture ----------------------------------------------------------------


func _id(slug: StringName) -> int:
	return ContentRegistryHub.id_from_slug(&"items", slug)


func _stack(store: Dictionary, slug: StringName, amount: int, bag: int) -> void:
	var item_id: int = _id(slug)
	if item_id <= 0:
		push_warning("preview fixture: no item for slug %s" % slug)
		return
	store[Inventory.next_uid(store)] = {"id": item_id, "a": amount, "bag": bag}


## Bag 1 loaded like a working bag; bags 2 and 3 hold overflow, so switching
## tabs visibly changes the grid instead of showing the same items.
func _load_fixture() -> void:
	var bag: Dictionary = {}
	_stack(bag, &"gold", 1_482_310, 0)
	_stack(bag, &"sword_runite.item", 1, 0)
	_stack(bag, &"iron_bow.item", 1, 0)
	_stack(bag, &"iron_helmet", 1, 0)
	_stack(bag, &"iron_chest", 1, 0)
	_stack(bag, &"health_potion", 6, 0)
	_stack(bag, &"cooked_lobster", 12, 0)
	_stack(bag, &"iron_ore", 137, 0)
	_stack(bag, &"coal_ore", 84, 0)
	_stack(bag, &"oak_log", 41, 0)
	_stack(bag, &"bone", 58, 0)
	_stack(bag, &"pickaxe_steel", 1, 0)

	_stack(bag, &"sword_mithril.item", 1, 1)
	_stack(bag, &"steel_bar", 23, 1)
	_stack(bag, &"mithril_ore", 210, 1)
	_stack(bag, &"yew_log", 66, 1)
	_stack(bag, &"greater_health_potion", 9, 1)
	_stack(bag, &"leather_boots", 1, 1)

	_stack(bag, &"runite_ore", 88, 2)
	_stack(bag, &"dragon_gem", 3, 2)
	_stack(bag, &"mana_potion", 14, 2)

	_menu._inventory = bag
	_menu._tab_filter = Item.InventoryTab.WEAPON


func _apply(bags: int, active: int, pending: int) -> void:
	_menu._bag_count = bags
	_menu._active_bag = active
	_menu._pending_bag_purchase = pending
	_menu._update_bag_tabs()
	_menu._rebuild_grid()


# --- Capture ----------------------------------------------------------------


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
		[1, 0, -1, "NEW PLAYER - 1 BAG, BAG 2 BUYABLE, BAG 3 LOCKED"],
		[1, 0, 1, "BAG 2 PURCHASE ARMED - CLICK AGAIN TO CONFIRM"],
		[2, 1, -1, "BAG 2 OWNED AND ACTIVE - BAG 3 BUYABLE"],
		[3, 2, -1, "ALL THREE BAGS OWNED - BAG 3 ACTIVE"],
	]:
		_apply(int(entry[0]), int(entry[1]), int(entry[2]))
		_caption.text = String(entry[3])
		_caption.visible = true
		cells.append(await _grab())
	_caption.visible = false
	_save(_montage(cells), "inventory-bags.png", 1)

	_apply(1, 0, -1)
	_save(await _grab(), "inventory-bags-hero.png")


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
