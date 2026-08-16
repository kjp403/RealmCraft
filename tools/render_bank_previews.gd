extends Node
## Screenshot the REAL BankMenu (not a mock) at the shipping 960×540 client size,
## with a hand-built bag + vault so every tab, sort mode and transfer state has
## something in it.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_bank_previews.tscn
##
## The scene route is not a style choice: `-s` starts a bare SceneTree with no
## autoloads, and bank_menu.gd / bank_order.gd reference ClientState, Client and
## Toaster — under `-s` they fail to COMPILE, so there is nothing to screenshot.
## `--mode=client` keeps the Client autoload alive instead of self-freeing.
##
## The menu persists its tab/sort/order through ClientState.settings, which is
## the player's REAL settings file. This tool snapshots the whole [bank] section
## up front and puts it back before quitting, so rendering previews never
## rearranges the vault of whoever runs it.

const MENU_SCENE: String = "res://source/client/ui/menus/bank/bank_menu.tscn"
const OUT_DIR: String = "res://previews"
## The project's base viewport. Previews are captured here and upscaled after,
## so what you see is exactly the layout the client produces — not a roomier
## canvas that hides clipping.
const W: int = 960
const H: int = 540

var _sv: SubViewport
var _menu: Control
var _caption: Label
var _out_abs: String
var _saved_bank_settings: Dictionary = {}


func _ready() -> void:
	call_deferred(&"_go")


func _go() -> void:
	_out_abs = ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(_out_abs)
	_saved_bank_settings = (ClientState.settings.data.get(&"bank", {}) as Dictionary).duplicate(true)

	_sv = SubViewport.new()
	_sv.size = Vector2i(W, H)
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sv.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	_sv.transparent_bg = false
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	# Stand-in for the world behind the menu, so the shell's dim backdrop reads
	# the way it does over a real map instead of over pure black.
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
	_caption.position = Vector2(0, 0)
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

	await _render_hero_shots()
	await _render_tab_sheet()
	await _render_sort_sheet()

	_restore_settings()
	get_tree().quit(0)


# --- Fixture ----------------------------------------------------------------


func _id(slug: StringName) -> int:
	return ContentRegistryHub.id_from_slug(&"items", slug)


## A believable mid/late-game hoard: a working bag, and a vault with something in
## every category so no tab renders empty in the previews.
func _load_fixture() -> void:
	var bag: Dictionary = {}
	_stack(bag, &"gold", 8_452_310)
	_stack(bag, &"iron_ore", 137)
	_stack(bag, &"coal_ore", 84)
	_stack(bag, &"oak_log", 41)
	_stack(bag, &"cooked_lobster", 12)
	_stack(bag, &"health_potion", 6)
	_stack(bag, &"iron_bar", 23)
	_stack(bag, &"sword_runite.item", 1)
	_stack(bag, &"iron_helmet", 1)
	_stack(bag, &"pickaxe_steel", 1)
	_stack(bag, &"bone", 58)
	_stack(bag, &"healing_herb", 17)

	var vault: Dictionary = {}
	# Materials — the pile that makes an unsorted bank unusable.
	for slug: StringName in [
		&"copper_ore", &"iron_ore", &"coal_ore", &"silver_ore", &"gold_ore",
		&"mithril_ore", &"adamant_ore", &"runite_ore", &"bronze_bar", &"iron_bar",
		&"steel_bar", &"silver_bar", &"gold_bar", &"mithril_bar", &"logs",
		&"oak_log", &"willow_log", &"maple_log", &"yew_log", &"hide_forest",
		&"leather_forest", &"cloth_forest", &"healing_herb", &"frostpetal",
		&"sunwort", &"moonbloom", &"bloodcap", &"vial_of_water", &"bone",
		&"dragon_gem", &"enchanted_gem", &"phantom_gem",
	]:
		_stack(vault, slug, randi_range(120, 4800))
	# Armor — the "resources from the armor" the tabs are there to separate.
	for slug: StringName in [
		&"bronze_helmet", &"bronze_chest", &"bronze_boots", &"iron_helmet",
		&"iron_chest", &"iron_boots", &"leather_cap", &"leather_jacket",
		&"leather_boots", &"cloth_hood", &"cloth_vest", &"cloth_shoes",
		&"apprentice_hood", &"apprentice_robe", &"shadow_hood", &"shadow_vest",
		&"ring_focus_gold", &"ring_guard_silver", &"relic_cinderheart",
	]:
		_stack(vault, slug, 1)
	# Weapons + tools.
	for slug: StringName in [
		&"sword_bronze.item", &"sword_iron.item", &"sword_steel.item",
		&"sword_mithril.item", &"sword_runite.item", &"bronze_bow.item",
		&"iron_bow.item", &"steel_bow.item", &"wand_iron.item", &"wand_steel.item",
		&"axe_steel", &"pickaxe_steel", &"fishing_rod_lv20", &"sickle",
	]:
		_stack(vault, slug, 1)
	# Consumables.
	for slug: StringName in [
		&"cooked_shrimp", &"cooked_trout", &"cooked_salmon", &"cooked_lobster",
		&"cooked_tuna", &"health_potion", &"greater_health_potion", &"mana_potion",
		&"greater_mana_potion", &"focus_tonic",
	]:
		_stack(vault, slug, randi_range(8, 240))
	# Quest + misc.
	for slug: StringName in [
		&"calders_bent_sword", &"foundry_tablet", &"quench_seal", &"pale_sporecap",
	]:
		_stack(vault, slug, 1)
	for slug: StringName in [&"bronze_arrow", &"iron_arrow", &"steel_arrow", &"captain_tag"]:
		_stack(vault, slug, randi_range(50, 900))

	_menu._inventory = bag
	_menu._bank = vault
	_menu._bank_slots = 200
	_menu._tab = _menu.TAB_ALL
	_menu._set_sort(BankOrder.Sort.CATEGORY)
	_menu._clear_selection()
	_menu._rebuild_grids()


func _stack(store: Dictionary, slug: StringName, amount: int) -> void:
	var item_id: int = _id(slug)
	if item_id <= 0:
		push_warning("preview fixture: no item for slug %s" % slug)
		return
	store[Inventory.next_uid(store)] = {"id": item_id, "a": amount}


## Find the vault/bag uid holding an item, so a preview can select a real stack.
func _uid_of(store: Dictionary, slug: StringName) -> int:
	var item_id: int = _id(slug)
	for uid: Variant in store.keys():
		if int(store[uid].get("id", 0)) == item_id:
			return int(uid)
	return -1


# --- Capture ----------------------------------------------------------------


func _settle() -> void:
	for _i: int in 8:
		await get_tree().process_frame


func _grab() -> Image:
	await _settle()
	return _sv.get_texture().get_image()


## Hero shots go out at 2× NEAREST: the client renders this UI at 960×540 and
## the window stretch scales it up, so a doubled capture is what a 1080p player
## actually looks at — and every pixel of clipping stays visible.
func _save(image: Image, file_name: String, scale: int = 2) -> void:
	if scale > 1:
		image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
	var dest: String = _out_abs.path_join(file_name)
	image.save_png(dest)
	print("SAVED ", dest, " size=", image.get_size())


func _render_hero_shots() -> void:
	# 1. The vault as you find it: every tab populated, Category sort, nothing picked.
	_menu._tab = _menu.TAB_ALL
	_menu._set_sort(BankOrder.Sort.CATEGORY)
	_menu._clear_selection()
	_menu._rebuild_grids()
	_save(await _grab(), "bank-overview.png")

	# 2. Deposit with a typed amount — the half that used to be missing.
	var bag_uid: int = _uid_of(_menu._inventory, &"iron_ore")
	_menu._select_stack(bag_uid, true)
	_menu._amount_spin.value = 75
	_save(await _grab(), "bank-deposit-amount.png")

	# 3. Withdraw All off the same row of controls, to show both directions
	#    driving one shared amount box.
	_menu._tab = Item.InventoryTab.MATERIAL
	_menu._rebuild_grids()
	var vault_uid: int = _uid_of(_menu._bank, &"coal_ore")
	_menu._select_stack(vault_uid, false)
	_menu._on_chip_pressed(-1)
	_save(await _grab(), "bank-withdraw-all.png")

	# 4. Search across both panes at once.
	_menu._tab = _menu.TAB_ALL
	_menu._clear_selection()
	_menu._search_field.text = "bar"
	_menu._rebuild_grids()
	_save(await _grab(), "bank-search.png")
	_menu._search_field.text = ""
	_menu._rebuild_grids()


func _render_tab_sheet() -> void:
	var cells: Array = []
	for entry: Array in [
		[Item.InventoryTab.WEAPON, "WEAPONS TAB"],
		[Item.InventoryTab.ARMOR, "ARMOR TAB"],
		[Item.InventoryTab.CONSUMABLE, "CONSUMABLES TAB"],
		[Item.InventoryTab.MATERIAL, "MATERIALS TAB"],
	]:
		_menu._tab = int(entry[0])
		_menu._clear_selection()
		_menu._rebuild_grids()
		_caption.text = String(entry[1])
		_caption.visible = true
		cells.append(await _grab())
	_caption.visible = false
	_save(_montage(cells), "bank-tabs.png", 1)
	_menu._tab = _menu.TAB_ALL
	_menu._rebuild_grids()


func _render_sort_sheet() -> void:
	var cells: Array = []
	for mode: BankOrder.Sort in [
		BankOrder.Sort.NAME_ASC,
		BankOrder.Sort.QUANTITY,
		BankOrder.Sort.VALUE,
		BankOrder.Sort.TIER,
	]:
		_menu._tab = _menu.TAB_ALL
		_menu._set_sort(mode)
		_menu._clear_selection()
		_menu._rebuild_grids()
		_caption.text = "SORT: %s" % String(BankOrder.SORT_LABELS[mode]).to_upper()
		_caption.visible = true
		cells.append(await _grab())
	_caption.visible = false
	_save(_montage(cells), "bank-sorts.png", 1)


## 2×2 contact sheet with a hairline gutter, so four states fit one image.
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
		var at := Vector2i(
			(i % 2) * (W + gutter),
			(i / 2) * (H + gutter)
		)
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), at)
	return sheet


func _restore_settings() -> void:
	ClientState.settings.data[&"bank"] = _saved_bank_settings
	ClientState.settings.save()
	print("restored [bank] settings section")
