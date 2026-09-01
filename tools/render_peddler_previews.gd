extends Node
## Screenshot the REAL PeddlerMenu and the REAL Peddler NPC, so the cart can be
## reviewed without waiting four hours for a window to open.
##
## Runs as a SCENE and WINDOWED (headless has no rasteriser, so a capture there
## comes back blank), mirroring render_quick_travel_previews.gd:
##   godot --path . --mode=client res://tools/render_peddler_previews.tscn
##
## The menu normally fills itself from a peddler.stock reply. There is no server
## here, so the rig calls the menu's own _render() with dictionaries shaped
## exactly like the handler's — same keys, same types. That exercises the real
## layout code (tier accents, SOLD OUT states, affordability colours, the closing
## clock) rather than a mock of it.

const MENU_SCENE: String = "res://source/client/ui/menus/peddler/peddler_menu.tscn"
const PEDDLER_NPC: String = "res://source/common/gameplay/characters/npc/npcs/traveling_peddler.tres"
const VAULT_SCENE: String = "res://source/common/gameplay/peddler/peddler_vault_chest.tscn"
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
	# way it does over real ground rather than over pure black.
	var ground: ColorRect = ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.18, 0.20, 0.16)
	_sv.add_child(ground)

	_menu = (load(MENU_SCENE) as PackedScene).instantiate() as Control
	_sv.add_child(_menu)

	await get_tree().process_frame
	await get_tree().process_frame

	# 1. A rich player, nothing bought yet — the cart at its most ordinary.
	_menu._render(_stock(900000, [], 22 * 60))
	_save(await _grab(), "peddler-cart.png")

	# 2. The state the window has to communicate the most: the S-tier already
	#    bought today, the A-tier out of reach, and the cart nearly packed up.
	_menu._render(_stock(58000, [_today_id(PeddlerItemData.TIER_S)], 3 * 60 + 41))
	_save(await _grab(), "peddler-sold-out.png")

	# 3. A day whose stock includes a brokered PvM chest. Today's roll may not
	#    have one, and the chest rows are the thing that most needs eyeballing:
	#    they carry the item's REAL art rather than a generated tier chip, so
	#    this is where a wrong slug would be visible as the wrong chest.
	var chest_date: String = _first_brokered_date()
	if chest_date.is_empty():
		push_warning("no upcoming date rolls a brokered chest — skipping that preview")
	else:
		_menu._render(_stock_on(chest_date, 900000, [], 18 * 60))
		_save(await _grab(), "peddler-chest-day.png")

	await _render_cart()
	get_tree().quit(0)


## The nearest date (from today) whose roll includes a brokered row, or "".
## Searched rather than hardcoded so this preview keeps working when the pools
## change and that date stops being a chest day.
func _first_brokered_date() -> String:
	var at_s: int = PeddlerSchedule.now_s()
	for _day: int in 60:
		var date: String = PeddlerSchedule.utc_date(at_s)
		for row: PeddlerItemData in PeddlerStock.for_date(date):
			if row.brokered:
				return date
		at_s += PeddlerSchedule.DAY_S
	return ""


## A peddler.stock reply, shaped exactly like peddler.stock.gd builds it.
## [param gold] drives the affordability colouring; [param spent] the SOLD OUT
## rows; [param closes_in] the header clock.
func _stock(gold: int, spent: Array, closes_in: int) -> Dictionary:
	return _stock_on(PeddlerSchedule.utc_date(), gold, spent, closes_in)


## The same reply, for an arbitrary date — so a preview can show a day that is
## not today.
func _stock_on(date: String, gold: int, spent: Array, closes_in: int) -> Dictionary:
	var rows: Array = []
	for row: PeddlerItemData in PeddlerStock.for_date(date):
		var sold_out: bool = spent.has(row.id)
		rows.append({
			"id": row.id,
			"item_name": row.item_name,
			"description": row.description,
			"tier": row.tier,
			"price": row.price_gold,
			"item_id": ContentRegistryHub.id_from_slug(&"items", StringName(row.id)),
			"lock": PeddlerDesk.LOCK_SOLD_OUT if sold_out else "",
			"sold_out": sold_out,
			"affordable": gold >= row.price_gold,
		})
	return {
		"ok": true,
		"gold": gold,
		"date": date,
		"stock": rows,
		"closes_in_s": closes_in,
	}


func _today_id(tier: String) -> String:
	for row: PeddlerItemData in PeddlerStock.today():
		if row.tier == tier:
			return row.id
	return ""


## The cart as it stands in the world: the Peddler beside their Vault Chest, at
## the offset PeddlerSites places them at — so the chest's click box and the
## NPC's are reviewed at their real spacing rather than at a guess.
func _render_cart() -> void:
	var strip: SubViewport = SubViewport.new()
	strip.size = Vector2i(260, 180)
	strip.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	strip.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	strip.transparent_bg = false
	strip.disable_3d = true
	get_tree().root.add_child(strip)

	var bg: ColorRect = ColorRect.new()
	bg.size = Vector2(260, 180)
	bg.color = Color(0.14, 0.16, 0.13)
	strip.add_child(bg)

	var npc_res: NPCResource = load(PEDDLER_NPC) as NPCResource
	var anchor: Vector2 = Vector2(96, 118)

	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	sprite.sprite_frames = npc_res.skin
	sprite.animation = &"idle"
	sprite.frame = 0
	sprite.scale = Vector2(2, 2)
	sprite.position = anchor
	strip.add_child(sprite)

	var vault: Node2D = (load(VAULT_SCENE) as PackedScene).instantiate() as Node2D
	vault.position = anchor + PeddlerSites.VAULT_OFFSET * 2.0
	vault.scale = Vector2(2, 2)
	strip.add_child(vault)

	var caption: Label = Label.new()
	caption.text = "%s + Vault" % npc_res.npc_name
	caption.size = Vector2(260, 18)
	caption.position = Vector2(0, 14)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override(&"font_size", 12)
	caption.add_theme_color_override(&"font_color", PeddlerItemData.tier_color(
		PeddlerItemData.TIER_S
	))
	strip.add_child(caption)

	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save(strip.get_texture().get_image(), "peddler-cart-npc.png", 3)


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
