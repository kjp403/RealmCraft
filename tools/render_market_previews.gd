extends Node
## Screenshot the REAL MarketMenu (Trading Post) at the shipping 960x540 client
## size, with a hand-built board so every tab has believable content.
##
## Runs as a SCENE, not a `-s` tool, and windowed (headless has no rasteriser):
##   godot --path . --mode=client res://tools/render_market_previews.tscn
##
## The scene route is not a style choice: `-s` starts a bare SceneTree with no
## autoloads, and market_menu.gd references Client / ClientState / Toaster — under
## `-s` it fails to COMPILE, so there is nothing to screenshot.
##
## The fixture is pushed straight into the menu's state and rendered with
## _rebuild(), bypassing the market.* round trip — there is no world server in a
## preview run, so the live path would just hang on its first await.

const MENU_SCENE: String = "res://source/client/ui/menus/market/market_menu.tscn"
const OUT_DIR: String = "res://previews"
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
	_sv.disable_3d = true
	get_tree().root.add_child(_sv)

	# Stand-in for the Guild Hall floor behind the menu, so the shell's dim
	# backdrop reads the way it does over a real map instead of over pure black.
	var ground: ColorRect = ColorRect.new()
	ground.size = Vector2(W, H)
	ground.color = Color(0.30, 0.24, 0.16)
	_sv.add_child(ground)

	var scene: PackedScene = load(MENU_SCENE) as PackedScene
	if scene == null:
		push_error("Could not load %s" % MENU_SCENE)
		get_tree().quit(1)
		return
	_menu = scene.instantiate() as Control
	_sv.add_child(_menu)

	await get_tree().process_frame
	await get_tree().process_frame
	_load_fixture()

	await _shot(_menu.Tab.BROWSE, "market-browse.png")
	_menu._search = "bar"
	await _shot(_menu.Tab.BROWSE, "market-search.png")
	_menu._search = ""
	await _shot(_menu.Tab.STALLS, "market-stalls.png")
	await _shot(_menu.Tab.MINE, "market-my-stall.png")
	# The edit pane only exists while one of your own listings is selected.
	_menu._editing_listing = 90
	_menu._side = _menu.SidePanel.EDIT
	await _shot(_menu.Tab.MINE, "market-edit-listing.png")

	get_tree().quit(0)


func _id(slug: StringName) -> int:
	return ContentRegistryHub.id_from_slug(&"items", slug)


## A believable board: four stalls, the same items priced differently across
## them (the whole point of the Browse tab), plus a bag worth listing.
func _load_fixture() -> void:
	var stalls: Array = [
		[1, "Ash's Emporium", 4001],
		[2, "The Iron Cellar", 4002],
		[3, "Moonbloom Apothecary", 4003],
		[4, "Runite & Co.", 4004],
	]
	var stock: Array = [
		[1, &"iron_bar", 40, 210],
		[1, &"coal_ore", 500, 38],
		[1, &"health_potion", 24, 320],
		[2, &"iron_bar", 120, 185],
		[2, &"steel_bar", 60, 460],
		[2, &"iron_ore", 300, 44],
		[3, &"healing_herb", 90, 75],
		[3, &"greater_health_potion", 12, 1450],
		[3, &"moonbloom", 30, 260],
		[4, &"sword_runite.item", 1, 4_250_000],
		[4, &"mithril_bar", 45, 1_900],
		[4, &"runite_ore", 8, 12_500],
	]

	var listings: Array = []
	var counts: Dictionary = {}
	var cheapest: Dictionary = {}
	var listing_id: int = 100
	for row: Array in stock:
		var store_id: int = int(row[0])
		var item_id: int = _id(row[1] as StringName)
		if item_id <= 0:
			push_warning("preview fixture: no item for slug %s" % row[1])
			continue
		var stall: Array = stalls[store_id - 1]
		listing_id += 1
		listings.append({
			"listing_id": listing_id,
			"store_id": store_id,
			"store_name": str(stall[1]),
			"seller_id": int(stall[2]),
			"seller_name": str(stall[1]).get_slice("'", 0).get_slice(" ", 0),
			"item_id": item_id,
			"amount": int(row[2]),
			"unit_price": int(row[3]),
		})
		counts[store_id] = int(counts.get(store_id, 0)) + 1
		var price: int = int(row[3])
		if not cheapest.has(store_id) or price < int(cheapest[store_id]):
			cheapest[store_id] = price

	var stores: Array = []
	for stall: Array in stalls:
		var store_id: int = int(stall[0])
		stores.append({
			"store_id": store_id,
			"store_name": str(stall[1]),
			"owner_id": int(stall[2]),
			"listing_count": int(counts.get(store_id, 0)),
			"cheapest": int(cheapest.get(store_id, 0)),
		})

	var bag: Dictionary = {}
	for entry: Array in [
		[&"gold", 862_400], [&"iron_ore", 137], [&"coal_ore", 84],
		[&"oak_log", 41], [&"cooked_lobster", 12], [&"iron_bar", 23],
		[&"sword_runite.item", 1], [&"healing_herb", 17],
	]:
		var item_id: int = _id(entry[0] as StringName)
		if item_id > 0:
			bag[Inventory.next_uid(bag)] = {"id": item_id, "a": int(entry[1]), "bag": 0}

	# Sale history: the price signal every panel is annotated with. Prices around
	# but not equal to the asks, so the "vs. market" deltas render both ways.
	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var sales: Array = [
		[&"iron_bar", 40, 196, "Ash", "Corvin", 3],
		[&"iron_bar", 120, 188, "Bram", "Nell", 22],
		[&"coal_ore", 500, 41, "Ash", "Nell", 47],
		[&"iron_ore", 250, 46, "Bram", "Corvin", 96],
		[&"health_potion", 10, 335, "Ash", "Maela", 140],
		[&"healing_herb", 200, 71, "Moon", "Corvin", 260],
		[&"steel_bar", 25, 505, "Bram", "Maela", 420],
		[&"mithril_bar", 12, 2_050, "Runite", "Nell", 900],
		[&"iron_bar", 60, 205, "Ash", "Maela", 1_500],
		[&"coal_ore", 900, 36, "Bram", "Corvin", 2_600],
	]
	var trades: Array = []
	var totals: Dictionary = {}
	for sale: Array in sales:
		var trade_item: int = _id(sale[0] as StringName)
		if trade_item <= 0:
			continue
		var units: int = int(sale[1])
		var price: int = int(sale[2])
		trades.append({
			"item_id": trade_item,
			"amount": units,
			"unit_price": price,
			"total": units * price,
			"seller_name": str(sale[3]),
			"buyer_name": str(sale[4]),
			"sold_at_ms": now_ms - int(sale[5]) * 60_000,
		})
		var bucket: Dictionary = totals.get(trade_item, {
			"low": price, "high": price, "gold": 0, "units": 0, "trades": 0, "last": price,
		})
		bucket["low"] = mini(int(bucket["low"]), price)
		bucket["high"] = maxi(int(bucket["high"]), price)
		bucket["gold"] = int(bucket["gold"]) + units * price
		bucket["units"] = int(bucket["units"]) + units
		bucket["trades"] = int(bucket["trades"]) + 1
		totals[trade_item] = bucket
	var stats: Dictionary = {}
	for trade_item: int in totals:
		var bucket: Dictionary = totals[trade_item]
		stats[trade_item] = {
			"low": bucket["low"],
			"high": bucket["high"],
			"avg": int(round(float(bucket["gold"]) / float(maxi(1, int(bucket["units"]))))),
			"units": bucket["units"],
			"trades": bucket["trades"],
			"last": bucket["last"],
		}

	_menu._trades = trades
	_menu._stats = stats
	_menu._server_now_ms = now_ms
	_menu._listings = listings
	_menu._stores = stores
	_menu._me = 4009
	_menu._set_gold(862_400)
	_menu._has_store = true
	_menu._store_name = "Kayla's Curios"
	_menu._store_open = true
	_menu._inventory = bag
	_menu._my_listings = [
		{"listing_id": 90, "item_id": _id(&"iron_bar"), "amount": 15, "unit_price": 195},
		{"listing_id": 91, "item_id": _id(&"oak_log"), "amount": 120, "unit_price": 26},
		{"listing_id": 92, "item_id": _id(&"cooked_lobster"), "amount": 9, "unit_price": 310},
	]


func _shot(tab: int, file_name: String) -> void:
	_menu._tab = tab
	for key: Variant in _menu._tab_buttons:
		(_menu._tab_buttons[key] as Button).button_pressed = key == tab
	_menu._rebuild()
	for _i: int in 10:
		await get_tree().process_frame
	var image: Image = _sv.get_texture().get_image()
	image.resize(image.get_width() * 2, image.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var dest: String = _out_abs.path_join(file_name)
	image.save_png(dest)
	print("SAVED ", dest, " size=", image.get_size())
