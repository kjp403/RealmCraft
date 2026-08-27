extends MenuShell
## The Trading Post — player-run market stalls in the Guild Hall.
##
## Three tabs behind one shell:
##   BROWSE   every active listing, searchable and sortable, each row priced
##            against what the item ACTUALLY sold for in the last day, so a buyer
##            can tell a deal from a mark-up at a glance.
##   STALLS   the open stores, plus the market-wide recent-sales feed.
##   MY STALL name / open / close, list items out of your bag, re-price a live
##            listing in place, and pull stock back (all of it or part of it).
##
## LIVE: the server broadcasts `market.changed` on every listing mutation, so an
## open board redraws the moment someone else buys — a stall with 1000 potions
## that sells 600 reads 400 for everyone, not just the buyer. Pushes are hints:
## the client always re-reads through the normal handlers, so there is one source
## of truth and a dropped push costs a stale panel, never a wrong transaction.
##
## The client never decides an outcome — every button round-trips to a market.*
## handler. Sales pay out through the MAILBOX (gold to the seller, goods to the
## buyer), which is why nothing here writes into the bag directly. See [Market].

enum Tab { BROWSE, STALLS, MINE }
## What the My Stall side panel is doing: listing something new out of the bag,
## or editing a listing that is already live.
enum SidePanel { LIST, EDIT }

## Detail pane width. Wide enough for a name, price block and sale history
## without squeezing the listing table, which is the part players scan.
const DETAIL_WIDTH: float = 336.0
const ROW_HEIGHT: float = 42.0
## Fixed browse columns. Everything left over goes to the item name — the longest
## text and the one players actually read — so these stay lean.
const COL_QTY: float = 52.0
const COL_ASK: float = 88.0
const COL_MARKET: float = 92.0
const COL_SELLER: float = 128.0
## Inset for a row's contents inside its Button / Panel. Without it the icon hugs
## the frame and a right-aligned price is clipped by the border.
const ROW_PAD: int = 8
const ICON_SIZE: float = 28.0
## Coalescing window for live refreshes. A busy minute can push several changes;
## redrawing once at the end of them keeps the panel from strobing.
const REFRESH_DEBOUNCE_S: float = 0.18

const COLOR_GOLD: Color = Color(1.00, 0.85, 0.45)
const COLOR_MUTED: Color = Color(0.58, 0.63, 0.74)
const COLOR_FAINT: Color = Color(0.45, 0.49, 0.58)
const COLOR_TITLE: Color = Color(1.00, 0.95, 0.80)
const COLOR_TEXT: Color = Color(0.88, 0.91, 0.96)
const COLOR_GOOD: Color = Color(0.51, 0.82, 0.53)
const COLOR_BAD: Color = Color(0.90, 0.47, 0.45)
const COLOR_LINE: Color = Color(1.0, 1.0, 1.0, 0.06)

var _tab: Tab = Tab.BROWSE
var _gold: int = 0
var _me: int = 0

# Board state
var _listings: Array = []
var _stores: Array = []
var _trades: Array = []
## item_id -> {"low", "avg", "high", "last", "units", "trades"} over the last day.
var _stats: Dictionary = {}
var _server_now_ms: int = 0
var _search: String = ""
var _sort_mode: int = 0
## 0 = every stall; otherwise only this store's rows (set from the Stalls tab).
var _store_filter: int = 0
var _selected_listing: int = 0

# My-stall state
var _has_store: bool = false
var _store_name: String = ""
var _store_open: bool = false
var _my_listings: Array = []
var _inventory: Dictionary = {}
var _max_listings: int = Market.MAX_LISTINGS_PER_STORE
var _selected_uid: int = -1
var _side: SidePanel = SidePanel.LIST
var _editing_listing: int = 0

# Widgets
var _tab_buttons: Dictionary = {}
var _gold_label: Label
var _page: MarginContainer
## Root of the Browse tab, kept so the search box can redraw just the table
## instead of the whole tab (a full rebuild would steal focus every keystroke).
var _browse_root: HBoxContainer
var _busy: bool = false
var _refresh_timer: SceneTreeTimer


func _ready() -> void:
	build_shell("Trading Post", null, true)
	_build_header()
	_page = MarginContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_page)
	# Someone else's buy / list / re-price landed — the board on screen is stale.
	Client.subscribe(&"market.changed", _on_market_changed)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())
	_refresh()


## Opened from the Market Stall NPC: "View Shops" passes "browse", "Open Store"
## passes "mine". Anything else lands on Browse.
func open(arg: Variant) -> void:
	var wanted: String = str(arg) if arg != null else "browse"
	_store_filter = 0
	_side = SidePanel.LIST
	_set_tab(Tab.MINE if wanted == "mine" else Tab.BROWSE)


func _build_header() -> void:
	var tabs: HBoxContainer = HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 6)
	header_center.add_child(tabs)
	for spec: Array in [[Tab.BROWSE, "Browse"], [Tab.STALLS, "Stalls"], [Tab.MINE, "My Stall"]]:
		var button: Button = Button.new()
		button.text = str(spec[1])
		button.theme_type_variation = &"HeaderTab"
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(104, 0)
		button.pressed.connect(_set_tab.bind(spec[0] as Tab))
		tabs.add_child(button)
		_tab_buttons[spec[0]] = button

	var gold_icon: TextureRect = TextureRect.new()
	gold_icon.custom_minimum_size = Vector2(20, 20)
	gold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var gold: Item = ContentRegistryHub.load_by_id(&"items", Economy.gold_id()) as Item
	if gold != null:
		gold_icon.texture = gold.item_icon
	_gold_label = Label.new()
	_gold_label.add_theme_color_override(&"font_color", COLOR_GOLD)
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_right.add_child(gold_icon)
	header_right.add_child(_gold_label)
	header_right.move_child(gold_icon, 0)
	header_right.move_child(_gold_label, 1)


func _set_tab(tab: Tab) -> void:
	_tab = tab
	for key: Variant in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = key == tab
	_selected_listing = 0
	_selected_uid = -1
	_side = SidePanel.LIST
	_refresh()


# --- Data -------------------------------------------------------------------

func _instance_name() -> String:
	return String(InstanceClient.current.name) if InstanceClient.current != null else ""


## A live change arrived. Coalesce a burst into one redraw, and hold off while the
## player is mid-edit in a field — yanking the panel out from under a half-typed
## price is worse than a beat of staleness, and their own next action refreshes.
func _on_market_changed(_payload: Dictionary) -> void:
	if not visible or not is_inside_tree():
		return
	if _refresh_timer != null:
		return
	_refresh_timer = get_tree().create_timer(REFRESH_DEBOUNCE_S)
	await _refresh_timer.timeout
	_refresh_timer = null
	if not visible or not is_inside_tree() or _busy or _is_editing():
		return
	await _refresh()


## True while a text field or spinner has keyboard focus.
func _is_editing() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is SpinBox


func _refresh() -> void:
	# The board is loaded for My Stall too: the price helpers under the lister
	# (match lowest / undercut / last sale) are the whole point of pricing here
	# rather than guessing.
	await _load_browse()
	if _tab == Tab.MINE:
		await _load_mine()
	if not is_inside_tree() or not visible:
		return
	_rebuild()


func _load_browse() -> void:
	var result: Array = await Client.request_data_await(&"market.browse", {}, _instance_name())
	if not is_inside_tree():
		return
	var data: Dictionary = result[0] if result[1] == OK else {}
	if not bool(data.get("ok", false)):
		_listings = []
		_stores = []
		_trades = []
		_stats = {}
		return
	_listings = data.get("listings", [])
	_stores = data.get("stores", [])
	_trades = data.get("trades", [])
	_stats = _normalize_stats(data.get("stats", {}))
	_server_now_ms = int(data.get("now_ms", 0))
	_me = int(data.get("me", 0))
	_set_gold(int(data.get("gold", 0)))


## JSON round-trips integer dictionary keys as strings — re-key by item id so a
## lookup by int works the way the rest of the menu expects.
func _normalize_stats(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in raw:
		out[int(str(key))] = raw[key]
	return out


func _load_mine() -> void:
	var result: Array = await Client.request_data_await(&"market.mine", {}, _instance_name())
	if not is_inside_tree():
		return
	var data: Dictionary = result[0] if result[1] == OK else {}
	if not bool(data.get("ok", false)):
		return
	_has_store = bool(data.get("has_store", false))
	_store_name = str(data.get("store_name", ""))
	if _store_name.is_empty():
		_store_name = str(data.get("default_name", ""))
	_store_open = bool(data.get("is_open", false))
	_my_listings = data.get("listings", [])
	_max_listings = int(data.get("max_listings", Market.MAX_LISTINGS_PER_STORE))
	_inventory = Inventory.normalize(data.get("inventory", {}))
	_set_gold(int(data.get("gold", 0)))


func _set_gold(amount: int) -> void:
	_gold = amount
	if _gold_label != null:
		_gold_label.text = _format(amount)


func _rebuild() -> void:
	for child: Node in _page.get_children():
		_page.remove_child(child)
		child.queue_free()
	_browse_root = null
	match _tab:
		Tab.BROWSE:
			_page.add_child(_build_browse())
		Tab.STALLS:
			_page.add_child(_build_stalls())
		Tab.MINE:
			_page.add_child(_build_mine())


# --- Browse -----------------------------------------------------------------

func _build_browse() -> Control:
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override(&"separation", 12)

	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", 8)
	split.add_child(left)

	# --- Filter bar: search + sort + the "showing one stall" escape hatch ---
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 8)
	left.add_child(bar)

	var search: LineEdit = LineEdit.new()
	search.placeholder_text = "Search items, sellers, stalls…"
	search.text = _search
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(func(text: String) -> void:
		_search = text
		_rebuild_rows())
	bar.add_child(search)

	var sort: OptionButton = OptionButton.new()
	sort.add_item("Cheapest first", 0)
	sort.add_item("Priciest first", 1)
	sort.add_item("Name A–Z", 2)
	sort.add_item("Newest", 3)
	sort.add_item("Best value", 4)
	sort.select(_sort_mode)
	sort.custom_minimum_size = Vector2(158, 0)
	sort.tooltip_text = "Best value ranks by how far below the item's 24h average the ask is."
	sort.item_selected.connect(func(index: int) -> void:
		_sort_mode = index
		_rebuild_rows())
	bar.add_child(sort)

	if _store_filter > 0:
		var clear: Button = Button.new()
		clear.text = "All stalls"
		clear.pressed.connect(func() -> void:
			_store_filter = 0
			_rebuild())
		bar.add_child(clear)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", 2)
	scroll.add_child(rows)

	var detail: PanelContainer = PanelContainer.new()
	detail.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(detail)

	split.set_meta(&"rows", rows)
	split.set_meta(&"scroll", scroll)
	split.set_meta(&"detail", detail)
	_browse_root = split
	_rebuild_rows()
	return split


## Applies search / store filter / sort and redraws just the table + detail pane,
## so typing in the search box never rebuilds the whole tab (which would steal
## focus from the field on every keystroke).
func _rebuild_rows() -> void:
	if _browse_root == null or not is_instance_valid(_browse_root):
		return
	var rows: VBoxContainer = _browse_root.get_meta(&"rows") as VBoxContainer
	var scroll: ScrollContainer = _browse_root.get_meta(&"scroll") as ScrollContainer
	for child: Node in rows.get_children():
		rows.remove_child(child)
		child.queue_free()

	var visible_rows: Array = _filtered_listings()
	if visible_rows.is_empty():
		rows.add_child(_empty_note(
			"No stalls are selling anything yet — open yours and be first."
			if _listings.is_empty()
			else "Nothing matches that search."
		))
		_show_listing_detail({})
		return

	# Resolve the selection BEFORE the rows are built, so the highlighted row and
	# the detail pane agree on the first frame. Keep it only if it survived the
	# FILTER: searching against the unfiltered feed would leave the detail pane
	# describing a row that is no longer on screen, with a live Buy button on it.
	var keep: Dictionary = {}
	for listing: Dictionary in visible_rows:
		if int(listing.get("listing_id", 0)) == _selected_listing:
			keep = listing
			break
	if keep.is_empty():
		keep = visible_rows[0]
	_selected_listing = int(keep.get("listing_id", 0))

	rows.add_child(_make_column_header())
	for listing: Dictionary in visible_rows:
		rows.add_child(_make_listing_row(listing))
	DragScroll.enable(scroll)
	_show_listing_detail(keep)


func _filtered_listings() -> Array:
	var needle: String = _search.strip_edges().to_lower()
	var out: Array = []
	for listing: Dictionary in _listings:
		if _store_filter > 0 and int(listing.get("store_id", 0)) != _store_filter:
			continue
		if not needle.is_empty():
			var name: String = _item_name(int(listing.get("item_id", 0))).to_lower()
			var seller: String = str(listing.get("seller_name", "")).to_lower()
			var stall: String = str(listing.get("store_name", "")).to_lower()
			if not (name.contains(needle) or seller.contains(needle) or stall.contains(needle)):
				continue
		out.append(listing)

	match _sort_mode:
		0:
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("unit_price", 0)) < int(b.get("unit_price", 0)))
		1:
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("unit_price", 0)) > int(b.get("unit_price", 0)))
		2:
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return _item_name(int(a.get("item_id", 0))).nocasecmp_to(_item_name(int(b.get("item_id", 0)))) < 0)
		3:
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("listing_id", 0)) > int(b.get("listing_id", 0)))
		4:
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return _value_ratio(a) < _value_ratio(b))
	return out


## Ask as a fraction of the item's 24h average — below 1.0 is a bargain. Rows with
## no trade history sort as "average" so an unpriced item never masquerades as the
## best deal on the board.
func _value_ratio(listing: Dictionary) -> float:
	var average: int = int(_stats_for(int(listing.get("item_id", 0))).get("avg", 0))
	if average <= 0:
		return 1.0
	return float(int(listing.get("unit_price", 0))) / float(average)


func _stats_for(item_id: int) -> Dictionary:
	var entry: Variant = _stats.get(item_id, null)
	return entry if entry is Dictionary else {}


func _make_column_header() -> Control:
	# Same inset as a row, so the headings sit over their own columns.
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", ROW_PAD + 6)
	margin.add_theme_constant_override(&"margin_right", ROW_PAD + 6)
	margin.add_theme_constant_override(&"margin_bottom", 2)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	margin.add_child(row)
	row.add_child(_column_label("Item", Control.SIZE_EXPAND_FILL, 0))
	row.add_child(_column_label("Stock", Control.SIZE_FILL, COL_QTY, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_column_label("Ask", Control.SIZE_FILL, COL_ASK, HORIZONTAL_ALIGNMENT_RIGHT))
	var market: Label = _column_label("24h avg", Control.SIZE_FILL, COL_MARKET, HORIZONTAL_ALIGNMENT_RIGHT)
	market.tooltip_text = "Unit-weighted average of everything that actually sold in the last day."
	market.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(market)
	row.add_child(_column_label("Seller", Control.SIZE_FILL, COL_SELLER))
	return margin


func _column_label(
	text: String,
	flags: int,
	width: float,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = flags
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = align
	label.add_theme_color_override(&"font_color", COLOR_FAINT)
	label.add_theme_font_size_override(&"font_size", 11)
	return label


func _make_listing_row(listing: Dictionary) -> Button:
	var listing_id: int = int(listing.get("listing_id", 0))
	var item_id: int = int(listing.get("item_id", 0))
	var item: Item = _item(item_id)
	var unit_price: int = int(listing.get("unit_price", 0))
	var average: int = int(_stats_for(item_id).get("avg", 0))

	var row: Button = Button.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.toggle_mode = true
	row.button_pressed = listing_id == _selected_listing
	row.tooltip_text = ItemTooltip.hover_text(item)
	if row.button_pressed:
		# The theme's toggled-on state is nearly identical to the resting one, and
		# the detail pane's Buy button spends real gold — which row it belongs to
		# has to be unmistakable, so the selection gets its own gold edge.
		for state: StringName in [&"normal", &"pressed", &"hover"]:
			row.add_theme_stylebox_override(state, _selected_row_style())
	row.pressed.connect(func() -> void:
		_selected_listing = listing_id
		_rebuild_rows())

	var line: HBoxContainer = _row_line(row, true)
	line.add_child(_icon_cell(item))
	line.add_child(_cell(_item_name(item_id), Control.SIZE_EXPAND_FILL, 0, COLOR_TEXT))
	line.add_child(_cell(_format(int(listing.get("amount", 0))), Control.SIZE_FILL, COL_QTY, COLOR_MUTED, HORIZONTAL_ALIGNMENT_RIGHT))

	# Ask is colour-coded against the MARKET, not against the wallet: green means
	# "cheaper than this normally goes for", which is the judgement a buyer needs.
	# Affordability is already obvious from the Buy button.
	var ask_color: Color = COLOR_GOLD
	if average > 0:
		ask_color = COLOR_GOOD if unit_price < average else (COLOR_BAD if unit_price > average else COLOR_GOLD)
	line.add_child(_cell(_format(unit_price), Control.SIZE_FILL, COL_ASK, ask_color, HORIZONTAL_ALIGNMENT_RIGHT))
	line.add_child(_cell(
		_format(average) if average > 0 else "—",
		Control.SIZE_FILL, COL_MARKET, COLOR_FAINT, HORIZONTAL_ALIGNMENT_RIGHT
	))
	line.add_child(_cell(str(listing.get("seller_name", "")), Control.SIZE_FILL, COL_SELLER, COLOR_MUTED))
	return row


## Right-hand pane for the selected listing: what it is, who is selling it, what
## the item has been going for, how many to take, and the running total.
func _show_listing_detail(listing: Dictionary) -> void:
	if _browse_root == null or not is_instance_valid(_browse_root):
		return
	var detail: PanelContainer = _browse_root.get_meta(&"detail") as PanelContainer
	for child: Node in detail.get_children():
		detail.remove_child(child)
		child.queue_free()

	var column: VBoxContainer = _padded_column(detail)

	if listing.is_empty():
		column.add_child(_empty_note("Pick a listing to buy."))
		return

	_selected_listing = int(listing.get("listing_id", 0))
	var item_id: int = int(listing.get("item_id", 0))
	var item: Item = _item(item_id)
	var unit_price: int = int(listing.get("unit_price", 0))
	var stock: int = int(listing.get("amount", 0))
	var mine: bool = int(listing.get("seller_id", 0)) == _me

	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	column.add_child(head)
	head.add_child(_icon_cell(item, 34.0))
	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override(&"separation", 0)
	head.add_child(titles)

	var name_label: Label = Label.new()
	name_label.text = _item_name(item_id)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_color_override(&"font_color", COLOR_TITLE)
	name_label.add_theme_font_size_override(&"font_size", 17)
	titles.add_child(name_label)

	var seller: Label = Label.new()
	seller.text = "%s · %s" % [str(listing.get("store_name", "")), str(listing.get("seller_name", ""))]
	seller.add_theme_color_override(&"font_color", COLOR_MUTED)
	seller.add_theme_font_size_override(&"font_size", 11)
	seller.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(seller)

	column.add_child(_rule())

	# --- Scrolling middle: market prices, item stats, recent sales ---
	var body: ScrollContainer = ScrollContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(body)
	var body_column: VBoxContainer = VBoxContainer.new()
	body_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_column.add_theme_constant_override(&"separation", 8)
	body.add_child(body_column)

	body_column.add_child(_price_block(item_id, unit_price))
	# History sits above the item's own stat text: what the thing sold for is the
	# decision the buyer is actually making here.
	body_column.add_child(_sales_block(item_id))

	var info: RichTextLabel = RichTextLabel.new()
	info.bbcode_enabled = true
	info.fit_content = true
	info.scroll_active = false
	info.focus_mode = Control.FOCUS_NONE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.text = ItemTooltip.body(item) if item != null else "[color=#9aa0b0]Unknown item.[/color]"
	body_column.add_child(info)
	DragScroll.enable(body)

	column.add_child(_rule())

	# --- Pinned buy controls ---
	var qty: SpinBox = _spin(1, maxi(1, stock), 1)
	var affordable: int = 0 if unit_price <= 0 else int(_gold / unit_price)
	column.add_child(_quantity_row(
		qty,
		[1, 10, 100],
		stock,
		mini(stock, affordable),
		"All"
	))

	var total_label: Label = Label.new()
	total_label.add_theme_font_size_override(&"font_size", 15)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(total_label)

	var buy: Button = Button.new()
	buy.custom_minimum_size = Vector2(0, 38)
	column.add_child(buy)

	var sync: Callable = func() -> void:
		var count: int = int(qty.value)
		var total: int = unit_price * count
		var can_pay: bool = total <= _gold
		total_label.text = "%s gold  ·  %s each" % [_format(total), _format(unit_price)]
		total_label.add_theme_color_override(&"font_color", COLOR_GOLD if can_pay else COLOR_BAD)
		if mine:
			buy.text = "Your own stall"
			buy.disabled = true
		elif not can_pay:
			buy.text = "Not enough gold"
			buy.disabled = true
		else:
			buy.text = "Buy %s" % _stack_label(item_id, count)
			buy.disabled = _busy
	qty.value_changed.connect(func(_v: float) -> void: sync.call())
	sync.call()
	buy.pressed.connect(func() -> void: _buy(int(listing.get("listing_id", 0)), int(qty.value)))

	column.add_child(_footnote("Purchases arrive in your Mailbox."))


## Ask vs. what the item actually trades for. The single most useful thing on the
## panel: without it a price is just a number the seller made up.
func _price_block(item_id: int, unit_price: int) -> Control:
	var stats: Dictionary = _stats_for(item_id)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _inset_style())

	var pad: MarginContainer = MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right"]:
		pad.add_theme_constant_override(side, 10)
	for side: StringName in [&"margin_top", &"margin_bottom"]:
		pad.add_theme_constant_override(side, 8)
	panel.add_child(pad)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	pad.add_child(column)

	# Stock is not repeated here: the table column and the Qty cap both state it,
	# and this block is short on purpose so the sale history clears the fold.
	column.add_child(_stat_line("Asking", "%s g" % _format(unit_price), COLOR_GOLD, 14))

	if stats.is_empty():
		column.add_child(_footnote("No recorded sales yet — this ask sets the price."))
		return panel

	# Three lines, not six: this block sits above the sale history, and every row
	# it takes is a sale the buyer has to scroll for. Each line answers one
	# question — what it goes for, how the ask compares, how solid the number is.
	var average: int = int(stats.get("avg", 0))
	var delta_text: String = ""
	var delta_color: Color = COLOR_TEXT
	if average > 0 and unit_price != average:
		var delta: int = int(round((float(unit_price) / float(average) - 1.0) * 100.0))
		var under: bool = delta < 0
		delta_text = "   (ask %s%d%%)" % ["" if under else "+", delta]
		delta_color = COLOR_GOOD if under else COLOR_BAD
	column.add_child(_stat_line(
		"24h average", "%s g%s" % [_format(average), delta_text], delta_color
	))

	var trade_count: int = int(stats.get("trades", 0))
	column.add_child(_stat_line(
		"24h range",
		"%s – %s g  ·  %d sale%s" % [
			_format(int(stats.get("low", 0))), _format(int(stats.get("high", 0))),
			trade_count, "" if trade_count == 1 else "s",
		],
		COLOR_MUTED
	))
	return panel


## Recent completed sales of this item — the raw ticker behind the averages.
func _sales_block(item_id: int) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 3)
	column.add_child(_section_label("Recent sales"))

	var shown: int = 0
	for trade: Dictionary in _trades:
		if int(trade.get("item_id", 0)) != item_id:
			continue
		column.add_child(_trade_line(trade, false))
		shown += 1
		if shown >= 6:
			break
	if shown == 0:
		column.add_child(_footnote("Nothing has changed hands yet."))
	return column


func _trade_line(trade: Dictionary, with_item_name: bool) -> Control:
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 8)

	var left: String = (
		"%s x%s" % [_item_name(int(trade.get("item_id", 0))), _format(int(trade.get("amount", 0)))]
		if with_item_name
		else "x%s" % _format(int(trade.get("amount", 0)))
	)
	line.add_child(_cell(left, Control.SIZE_EXPAND_FILL, 0, COLOR_MUTED, HORIZONTAL_ALIGNMENT_LEFT, 12))
	line.add_child(_cell(
		"%s g" % _format(int(trade.get("unit_price", 0))),
		Control.SIZE_FILL, 78, COLOR_GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 12
	))
	line.add_child(_cell(
		_ago(int(trade.get("sold_at_ms", 0))),
		Control.SIZE_FILL, 44, COLOR_FAINT, HORIZONTAL_ALIGNMENT_RIGHT, 12
	))
	return line


func _buy(listing_id: int, amount: int) -> void:
	if _busy:
		return
	_busy = true
	var result: Array = await Client.request_data_await(
		&"market.buy", {"listing_id": listing_id, "amount": amount}, _instance_name()
	)
	_busy = false
	if not is_inside_tree():
		return
	var data: Dictionary = result[0] if result[1] == OK else {}
	if not bool(data.get("ok", false)):
		Toaster.toast(_buy_error(data))
		await _refresh() # the board moved under us — re-read it
		return
	_set_gold(int(data.get("gold", _gold)))
	# Apply the authoritative stock the server just reported BEFORE the re-read
	# lands, so the row ticks down on the same frame as the click.
	_patch_stock(listing_id, int(data.get("stock_left", 0)))
	_rebuild_rows()
	ClientState.inventory_changed.emit({"quiet": true})
	Toaster.toast_group(
		"Bought!",
		PackedStringArray([
			"%s from %s" % [
				_stack_label(int(data.get("item_id", 0)), int(data.get("amount", 1))),
				str(data.get("seller_name", "")),
			],
			"Paid %s gold — collect it in your Mailbox." % _format(int(data.get("total", 0))),
		]),
		4.0
	)
	await _refresh()


## Writes a known-good stock level into the cached board, dropping the row when it
## sells out. Only ever fed from a server response.
func _patch_stock(listing_id: int, stock_left: int) -> void:
	for i: int in _listings.size():
		var listing: Dictionary = _listings[i]
		if int(listing.get("listing_id", 0)) != listing_id:
			continue
		if stock_left <= 0:
			_listings.remove_at(i)
			_selected_listing = 0
		else:
			listing["amount"] = stock_left
		return


func _buy_error(data: Dictionary) -> String:
	match str(data.get("reason", "")):
		"gone", "not_enough_stock":
			return "Someone beat you to it — that stock is gone."
		"closed":
			return "That stall just closed."
		"own_store":
			return "You can't buy from your own stall."
		"cant_afford":
			return "Not enough gold (need %s)." % _format(int(data.get("total", 0)))
		"dead":
			return "Not while you're down."
		_:
			return "That purchase didn't go through — nothing was charged."


# --- Stalls -----------------------------------------------------------------

func _build_stalls() -> Control:
	var split: HBoxContainer = HBoxContainer.new()
	split.add_theme_constant_override(&"separation", 12)

	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", 6)
	split.add_child(left)

	left.add_child(_section_label(
		"%d stall%s open" % [_stores.size(), "" if _stores.size() == 1 else "s"]
	))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)

	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 4)
	scroll.add_child(column)

	if _stores.is_empty():
		column.add_child(_empty_note("No stalls are open right now. Open yours from My Stall."))
	else:
		for store: Dictionary in _stores:
			column.add_child(_make_store_card(store))
		DragScroll.enable(scroll)

	split.add_child(_build_ticker())
	return split


## Market-wide sale feed: everything that has actually changed hands lately, in
## one place — the reference players argue about prices with.
func _build_ticker() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column: VBoxContainer = _padded_column(panel)

	column.add_child(_section_label("Recent sales across the market"))
	column.add_child(_rule())

	if _trades.is_empty():
		column.add_child(_empty_note("Nothing has sold yet."))
		return panel

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", 3)
	scroll.add_child(rows)
	for trade: Dictionary in _trades:
		rows.add_child(_trade_line(trade, true))
	DragScroll.enable(scroll)
	return panel


func _make_store_card(store: Dictionary) -> Button:
	var store_id: int = int(store.get("store_id", 0))
	var card: Button = Button.new()
	card.custom_minimum_size = Vector2(0, 50)
	card.tooltip_text = "Show only this stall's listings"
	card.pressed.connect(func() -> void:
		_store_filter = store_id
		_set_tab(Tab.BROWSE))

	var line: HBoxContainer = _row_line(card, true)
	var count: int = int(store.get("listing_count", 0))

	var name_label: Label = _cell(str(store.get("store_name", "Stall")), Control.SIZE_EXPAND_FILL, 0, COLOR_TITLE)
	name_label.add_theme_font_size_override(&"font_size", 15)
	line.add_child(name_label)
	line.add_child(_cell(
		"%d listing%s" % [count, "" if count == 1 else "s"],
		Control.SIZE_FILL, 108, COLOR_MUTED, HORIZONTAL_ALIGNMENT_RIGHT
	))
	line.add_child(_cell(
		"from %s g" % _format(int(store.get("cheapest", 0))),
		Control.SIZE_FILL, 124, COLOR_GOLD, HORIZONTAL_ALIGNMENT_RIGHT
	))
	return card


# --- My stall ---------------------------------------------------------------

func _build_mine() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)

	# --- Stall header: name, open/closed, one-press toggle ---
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override(&"separation", 8)
	column.add_child(bar)

	var name_field: LineEdit = LineEdit.new()
	name_field.text = _store_name
	name_field.max_length = Market.MAX_STORE_NAME_LENGTH
	name_field.placeholder_text = "Name your stall"
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(name_field)

	var save: Button = Button.new()
	save.text = "Save name"
	save.pressed.connect(func() -> void: _set_store(name_field.text, _store_open))
	bar.add_child(save)

	# State reads as a chip rather than a sentence: the explanation belongs on the
	# button's tooltip, and every row of prose here is a row the editor panel
	# below loses.
	var live: bool = _store_open and _has_store
	var status: Label = Label.new()
	status.text = "● Open" if live else "● Closed"
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_theme_color_override(&"font_color", COLOR_GOOD if live else COLOR_MUTED)
	status.add_theme_font_size_override(&"font_size", 12)
	bar.add_child(status)

	var toggle: Button = Button.new()
	toggle.custom_minimum_size = Vector2(140, 0)
	toggle.text = "Close stall" if _store_open else "Open Store"
	toggle.tooltip_text = (
		"Open: anyone at the Trading Post can buy from your stall.\nChange prices and stock any time — you never need to close it."
		if live
		else "Closed: your listings are safe and still yours, but nobody can buy until you open."
	)
	toggle.add_theme_color_override(&"font_color", COLOR_BAD if _store_open else COLOR_GOOD)
	toggle.pressed.connect(func() -> void: _set_store(name_field.text, not _store_open))
	bar.add_child(toggle)

	var split: HBoxContainer = HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override(&"separation", 12)
	column.add_child(split)
	split.add_child(_build_my_listings())
	split.add_child(_build_lister() if _side == SidePanel.LIST else _build_editor())
	return column


func _build_my_listings() -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 6)

	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	column.add_child(head)
	var title: Label = _section_label("On sale  %d / %d" % [_my_listings.size(), _max_listings])
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if not _my_listings.is_empty():
		var pull_all: Button = Button.new()
		pull_all.text = "Pull everything"
		pull_all.tooltip_text = "Take all stock off sale. It comes back through your Mailbox."
		pull_all.pressed.connect(func() -> void: _unlist(0, 0, true))
		head.add_child(pull_all)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var rows: VBoxContainer = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override(&"separation", 2)
	scroll.add_child(rows)

	if _my_listings.is_empty():
		rows.add_child(_empty_note("Nothing listed yet. Pick something from your bag on the right."))
		return column

	rows.add_child(_my_column_header())
	for listing: Dictionary in _my_listings:
		rows.add_child(_make_my_listing_row(listing))
	DragScroll.enable(scroll)
	return column


func _my_column_header() -> Control:
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override(&"margin_left", ROW_PAD + 6)
	margin.add_theme_constant_override(&"margin_right", ROW_PAD + 6)
	margin.add_theme_constant_override(&"margin_bottom", 2)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	margin.add_child(row)
	row.add_child(_column_label("Item", Control.SIZE_EXPAND_FILL, 0))
	row.add_child(_column_label("Stock", Control.SIZE_FILL, COL_QTY, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_column_label("Your ask", Control.SIZE_FILL, COL_ASK, HORIZONTAL_ALIGNMENT_RIGHT))
	row.add_child(_column_label("24h avg", Control.SIZE_FILL, COL_MARKET, HORIZONTAL_ALIGNMENT_RIGHT))
	return margin


func _make_my_listing_row(listing: Dictionary) -> Button:
	var listing_id: int = int(listing.get("listing_id", 0))
	var item_id: int = int(listing.get("item_id", 0))
	var item: Item = _item(item_id)
	var unit_price: int = int(listing.get("unit_price", 0))
	var average: int = int(_stats_for(item_id).get("avg", 0))

	var row: Button = Button.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.toggle_mode = true
	row.button_pressed = listing_id == _editing_listing and _side == SidePanel.EDIT
	row.tooltip_text = "Edit price or pull stock"
	if row.button_pressed:
		for state: StringName in [&"normal", &"pressed", &"hover"]:
			row.add_theme_stylebox_override(state, _selected_row_style())
	row.pressed.connect(func() -> void:
		_editing_listing = listing_id
		_side = SidePanel.EDIT
		_rebuild())

	var line: HBoxContainer = _row_line(row, true)
	line.add_child(_icon_cell(item))
	line.add_child(_cell(_item_name(item_id), Control.SIZE_EXPAND_FILL, 0, COLOR_TEXT))
	line.add_child(_cell(_format(int(listing.get("amount", 0))), Control.SIZE_FILL, COL_QTY, COLOR_MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	line.add_child(_cell(_format(unit_price), Control.SIZE_FILL, COL_ASK, COLOR_GOLD, HORIZONTAL_ALIGNMENT_RIGHT))
	line.add_child(_cell(
		_format(average) if average > 0 else "—",
		Control.SIZE_FILL, COL_MARKET, COLOR_FAINT, HORIZONTAL_ALIGNMENT_RIGHT
	))
	return row


## Right pane of My Stall, mode LIST: everything listable in the bag, then
## quantity + price for whatever is picked. Quest items and gold are filtered out
## here AND rejected server-side, so the two can never disagree.
func _build_lister() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column: VBoxContainer = _padded_column(panel)

	column.add_child(_section_label("List an item"))
	column.add_child(_rule())

	var listable: Array = _listable_slots()
	if listable.is_empty():
		column.add_child(_empty_note(
			"Nothing in your bag can be listed. Quest items stay bound to you, and gold is what buyers pay with."
		))
		return panel

	var body: VBoxContainer = _scroll_body(column)

	var picker: OptionButton = OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry: Dictionary in listable:
		picker.add_item("%s  (%s)" % [
			_item_name(int(entry.get("id", 0))), _format(int(entry.get("a", 0)))
		])
	body.add_child(picker)

	var qty: SpinBox = _spin(1, 1, 1)
	var qty_row: HBoxContainer = _quantity_row(qty, [1, 10, 100], 1, 0, "All")
	body.add_child(qty_row)

	var price: SpinBox = _spin(1, Market.MAX_UNIT_PRICE, 1)
	body.add_child(_labelled_row("Price each", price))

	var price_chips: HBoxContainer = HBoxContainer.new()
	price_chips.add_theme_constant_override(&"separation", 4)
	price_chips.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(price_chips)

	var market_note: Label = Label.new()
	market_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	market_note.add_theme_color_override(&"font_color", COLOR_MUTED)
	market_note.add_theme_font_size_override(&"font_size", 11)
	body.add_child(market_note)

	var takeaway: Label = Label.new()
	takeaway.add_theme_color_override(&"font_color", COLOR_GOLD)
	takeaway.add_theme_font_size_override(&"font_size", 15)
	takeaway.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(takeaway)

	var submit: Button = Button.new()
	submit.text = "Put on sale"
	submit.custom_minimum_size = Vector2(0, 38)
	column.add_child(submit)
	column.add_child(_footnote("Listed stock leaves your bag. Sales pay out to your Mailbox."))

	var sync: Callable = func() -> void:
		var index: int = picker.selected
		if index < 0 or index >= listable.size():
			return
		var entry: Dictionary = listable[index]
		var item_id: int = int(entry.get("id", 0))
		var item: Item = _item(item_id)
		var held: int = int(entry.get("a", 0))
		_selected_uid = int(entry.get("uid", -1))
		qty.max_value = maxi(1, held)
		qty.value = mini(int(qty.value), int(qty.max_value))
		_retarget_quantity_row(qty_row, held, 0, "All")
		var floor_price: int = maxi(1, item.market_minimum_price if item != null else 1)
		price.min_value = floor_price
		if int(price.value) < floor_price:
			price.value = floor_price
		takeaway.text = "You receive %s gold" % _format(int(price.value) * int(qty.value))
		_fill_price_chips(price_chips, price, item_id, floor_price)
		market_note.text = _market_note(item_id, item)
		submit.disabled = _busy or _selected_uid < 0

	picker.item_selected.connect(func(_i: int) -> void: sync.call())
	qty.value_changed.connect(func(_v: float) -> void: sync.call())
	price.value_changed.connect(func(_v: float) -> void: sync.call())
	sync.call()
	submit.pressed.connect(func() -> void: _list_item(_selected_uid, int(qty.value), int(price.value)))
	return panel


## Right pane of My Stall, mode EDIT: change a live listing's ask, or take some of
## its stock back — both without the stall ever closing.
func _build_editor() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(DETAIL_WIDTH, 0)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column: VBoxContainer = _padded_column(panel)

	var listing: Dictionary = {}
	for row: Dictionary in _my_listings:
		if int(row.get("listing_id", 0)) == _editing_listing:
			listing = row
			break
	if listing.is_empty():
		column.add_child(_empty_note("That listing is no longer on your stall."))
		column.add_child(_back_button())
		return panel

	var item_id: int = int(listing.get("item_id", 0))
	var item: Item = _item(item_id)
	var stock: int = int(listing.get("amount", 0))

	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	column.add_child(head)
	head.add_child(_icon_cell(item, 30.0))
	var title: Label = _cell(_item_name(item_id), Control.SIZE_EXPAND_FILL, 0, COLOR_TITLE)
	title.add_theme_font_size_override(&"font_size", 16)
	head.add_child(title)
	# Compact by design: re-pricing and pulling are BOTH primary actions here, and
	# a panel that hides one behind a scroll makes the other look like the only
	# option. Everything fits, so nothing here scrolls.
	column.add_theme_constant_override(&"separation", 6)
	var body: VBoxContainer = column

	# --- Price ---
	var price: SpinBox = _spin(
		maxi(1, item.market_minimum_price if item != null else 1),
		Market.MAX_UNIT_PRICE,
		int(listing.get("unit_price", 1))
	)
	body.add_child(_labelled_row("Gold each", price))

	var price_chips: HBoxContainer = HBoxContainer.new()
	price_chips.add_theme_constant_override(&"separation", 4)
	price_chips.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(price_chips)
	_fill_price_chips(price_chips, price, item_id, int(price.min_value))

	var note: Label = Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override(&"font_color", COLOR_MUTED)
	note.add_theme_font_size_override(&"font_size", 11)
	note.text = _market_note(item_id, item)
	body.add_child(note)

	var actions: VBoxContainer = VBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 6)

	var apply: Button = Button.new()
	apply.custom_minimum_size = Vector2(0, 32)
	actions.add_child(apply)
	var sync: Callable = func() -> void:
		var changed: bool = int(price.value) != int(listing.get("unit_price", 0))
		apply.text = "Update price to %s g" % _format(int(price.value)) if changed else "Price unchanged"
		apply.disabled = _busy or not changed
	price.value_changed.connect(func(_v: float) -> void: sync.call())
	sync.call()
	apply.pressed.connect(func() -> void: _reprice(_editing_listing, int(price.value)))

	# --- Stock ---
	actions.add_child(_rule())
	actions.add_child(_section_label("Stock on sale: %s" % _format(stock)))
	var qty: SpinBox = _spin(1, maxi(1, stock), 1)
	actions.add_child(_quantity_row(qty, [1, 10, 100], stock, 0, "All"))

	var pull: Button = Button.new()
	pull.custom_minimum_size = Vector2(0, 32)
	actions.add_child(pull)
	var pull_sync: Callable = func() -> void:
		var count: int = int(qty.value)
		pull.text = (
			"Pull all %s to Mailbox" % _format(count)
			if count >= stock
			else "Pull %s to Mailbox" % _format(count)
		)
		pull.tooltip_text = (
			"Takes this stock off sale and mails it back to you. Anything you leave behind keeps selling."
		)
		pull.disabled = _busy
	qty.value_changed.connect(func(_v: float) -> void: pull_sync.call())
	pull_sync.call()
	pull.pressed.connect(func() -> void: _unlist(_editing_listing, int(qty.value), false))

	column.add_child(actions)
	column.add_child(_back_button())
	return panel


func _back_button() -> Button:
	var back: Button = Button.new()
	back.text = "List something else"
	back.pressed.connect(func() -> void:
		_side = SidePanel.LIST
		_editing_listing = 0
		_rebuild())
	return back


## One-tap price anchors, built from the live board and the sale history. This is
## how a seller re-prices in two clicks instead of leaving and coming back.
func _fill_price_chips(host: HBoxContainer, price: SpinBox, item_id: int, floor_price: int) -> void:
	for child: Node in host.get_children():
		host.remove_child(child)
		child.queue_free()
	var stats: Dictionary = _stats_for(item_id)
	var lowest: int = _cheapest_price(item_id)
	var options: Array = []
	if lowest > 0:
		options.append(["Match %s" % _format(lowest), lowest])
		options.append(["Undercut", maxi(floor_price, lowest - maxi(1, int(lowest * 0.01)))])
	if stats.has("avg"):
		options.append(["Avg %s" % _format(int(stats["avg"])), int(stats["avg"])])
	elif stats.has("last"):
		options.append(["Last %s" % _format(int(stats["last"])), int(stats["last"])])
	if options.is_empty():
		return
	for option: Array in options:
		var chip: Button = Button.new()
		chip.text = str(option[0])
		chip.add_theme_font_size_override(&"font_size", 11)
		chip.custom_minimum_size = Vector2(0, 24)
		chip.pressed.connect(func() -> void: price.value = maxi(floor_price, int(option[1])))
		host.add_child(chip)


## One line telling a seller where their ask sits: what the board is asking, and
## what the item has actually been going for.
func _market_note(item_id: int, item: Item) -> String:
	var stats: Dictionary = _stats_for(item_id)
	var lowest: int = _cheapest_price(item_id)
	var parts: PackedStringArray = PackedStringArray()
	if lowest > 0:
		parts.append("Cheapest ask %s g" % _format(lowest))
	if stats.has("avg"):
		var trade_count: int = int(stats.get("trades", 0))
		parts.append("24h avg %s g over %d sale%s" % [
			_format(int(stats["avg"])), trade_count, "" if trade_count == 1 else "s",
		])
	if parts.is_empty():
		if item != null and item.vendor_value > 0:
			return "Nobody else is selling this. Vendors pay %s g each." % _format(item.vendor_value)
		return "Nobody else is selling this — you set the price."
	return "  ·  ".join(parts)


## Bag slots that can go on a stall. Gold and quest items are excluded by
## [method Market.is_listable]; everything else in the game is fair game.
func _listable_slots() -> Array:
	var out: Array = []
	for uid: Variant in _inventory:
		var slot: Dictionary = _inventory[uid]
		var item: Item = _item(int(slot.get("id", 0)))
		if not Market.is_listable(item):
			continue
		out.append({"uid": int(uid), "id": int(slot.get("id", 0)), "a": int(slot.get("a", 0))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _item_name(int(a.get("id", 0))).nocasecmp_to(_item_name(int(b.get("id", 0)))) < 0)
	return out


## Cheapest active ask for [param item_id] across every open stall, or 0 when
## nobody is selling it.
func _cheapest_price(item_id: int) -> int:
	var best: int = 0
	for listing: Dictionary in _listings:
		if int(listing.get("item_id", 0)) != item_id:
			continue
		var price: int = int(listing.get("unit_price", 0))
		if best == 0 or price < best:
			best = price
	return best


# --- Actions ----------------------------------------------------------------

func _set_store(store_name: String, is_open: bool) -> void:
	if _busy:
		return
	_busy = true
	var result: Array = await Client.request_data_await(
		&"market.set_store", {"name": store_name, "open": is_open}, _instance_name()
	)
	_busy = false
	if not is_inside_tree():
		return
	var data: Dictionary = result[0] if result[1] == OK else {}
	if not bool(data.get("ok", false)):
		Toaster.toast("Couldn't update your stall.")
		return
	Toaster.toast("Stall %s." % ("opened" if bool(data.get("is_open", false)) else "closed"))
	await _refresh()


func _list_item(uid: int, amount: int, unit_price: int) -> void:
	if _busy or uid < 0:
		return
	_busy = true
	var result: Array = await Client.request_data_await(
		&"market.list", {"uid": uid, "amount": amount, "unit_price": unit_price}, _instance_name()
	)
	_busy = false
	if not is_inside_tree():
		return
	var data: Dictionary = result[0] if result[1] == OK else {}
	if not bool(data.get("ok", false)):
		Toaster.toast(_list_error(data))
		await _refresh()
		return
	ClientState.inventory_changed.emit({"quiet": true})
	Toaster.toast("Listed %s at %s gold each." % [
		_stack_label(int(data.get("item_id", 0)), int(data.get("amount", 1))),
		_format(int(data.get("unit_price", 0))),
	])
	await _refresh()


func _list_error(data: Dictionary) -> String:
	match str(data.get("reason", "")):
		"not_listable":
			return str(data.get("message", "That item can't be listed."))
		"store_full":
			return "Your stall is full (%d listings). Pull one first." % int(data.get("max_listings", _max_listings))
		"min_price":
			return "That item can't sell for less than %s gold." % _format(int(data.get("min_price", 1)))
		"max_price":
			return "Price is capped at %s gold." % _format(int(data.get("max_price", Market.MAX_UNIT_PRICE)))
		"bad_amount", "missing":
			return "That stack moved — check your bag and try again."
		"dead":
			return "Not while you're down."
		_:
			return "Couldn't list that — nothing left your bag."


func _reprice(listing_id: int, unit_price: int) -> void:
	if _busy:
		return
	_busy = true
	var result: Array = await Client.request_data_await(
		&"market.reprice", {"listing_id": listing_id, "unit_price": unit_price}, _instance_name()
	)
	_busy = false
	if not is_inside_tree():
		return
	var data: Dictionary = result[0] if result[1] == OK else {}
	if not bool(data.get("ok", false)):
		var bounded: bool = data.has("min_price") or data.has("max_price")
		Toaster.toast(
			_list_error(data) if bounded else "Couldn't change that price — the listing may have sold."
		)
		await _refresh()
		return
	Toaster.toast("Now asking %s gold each." % _format(int(data.get("unit_price", unit_price))))
	await _refresh()


func _unlist(listing_id: int, amount: int, all: bool) -> void:
	if _busy:
		return
	_busy = true
	var args: Dictionary = {"all": true} if all else {"listing_id": listing_id, "amount": amount}
	var result: Array = await Client.request_data_await(&"market.unlist", args, _instance_name())
	_busy = false
	if not is_inside_tree():
		return
	var data: Dictionary = result[0] if result[1] == OK else {}
	if not bool(data.get("ok", false)):
		Toaster.toast("Couldn't pull that stock — it may have just sold.")
		await _refresh()
		return
	var units: int = 0
	for entry: Dictionary in (data.get("pulled", []) as Array):
		units += int(entry.get("amount", 0))
	Toaster.toast("Pulled %s — waiting in your Mailbox." % _format(units))
	# Whatever was being edited may be gone now; drop back to the lister.
	_side = SidePanel.LIST
	_editing_listing = 0
	await _refresh()


# --- Building blocks --------------------------------------------------------

func _spin(minimum: int, maximum: int, value: int) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maxi(minimum, maximum)
	spin.value = clampi(value, minimum, maxi(minimum, maximum))
	spin.step = 1
	spin.select_all_on_focus = true
	spin.custom_minimum_size = Vector2(108, 0)
	return spin


## A quantity spinner with one-tap presets. Bulk trades are the norm here — a
## player buying 600 potions should not hold an arrow down, and a seller listing
## a full stack should not have to type its size.
func _quantity_row(
	spin: SpinBox,
	presets: Array,
	maximum: int,
	affordable: int,
	max_label: String
) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)

	var label: Label = Label.new()
	label.text = "Qty"
	label.add_theme_color_override(&"font_color", COLOR_MUTED)
	row.add_child(label)
	row.add_child(spin)

	var chips: HBoxContainer = HBoxContainer.new()
	chips.name = "Chips"
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.alignment = BoxContainer.ALIGNMENT_END
	chips.add_theme_constant_override(&"separation", 3)
	row.add_child(chips)
	row.set_meta(&"spin", spin)
	row.set_meta(&"presets", presets)
	_retarget_quantity_row(row, maximum, affordable, max_label)
	return row


## Rebuilds a quantity row's preset chips for a new maximum — the lister's cap
## changes every time the player picks a different bag stack.
func _retarget_quantity_row(row: HBoxContainer, maximum: int, affordable: int, max_label: String) -> void:
	var chips: HBoxContainer = row.get_node_or_null(^"Chips") as HBoxContainer
	var spin: SpinBox = row.get_meta(&"spin") as SpinBox
	if chips == null or spin == null:
		return
	for child: Node in chips.get_children():
		chips.remove_child(child)
		child.queue_free()
	for preset: Variant in (row.get_meta(&"presets") as Array):
		var value: int = int(preset)
		if value >= maximum:
			break # a preset at or past the cap is just the All chip with extra steps
		chips.add_child(_chip(str(value), func() -> void: spin.value = value))
	if affordable > 0 and affordable < maximum:
		chips.add_child(_chip("Max", func() -> void: spin.value = affordable))
	chips.add_child(_chip(max_label, func() -> void: spin.value = maximum))


func _chip(text: String, action: Callable) -> Button:
	var chip: Button = Button.new()
	chip.text = text
	chip.add_theme_font_size_override(&"font_size", 11)
	chip.custom_minimum_size = Vector2(32, 24)
	chip.pressed.connect(action)
	return chip


func _labelled_row(text: String, field: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override(&"font_color", COLOR_MUTED)
	row.add_child(label)
	row.add_child(field)
	return row


func _stat_line(label_text: String, value_text: String, color: Color, size: int = 12) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label: Label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override(&"font_color", COLOR_FAINT)
	label.add_theme_font_size_override(&"font_size", size)
	row.add_child(label)
	var value: Label = Label.new()
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.add_theme_color_override(&"font_color", color)
	value.add_theme_font_size_override(&"font_size", size)
	row.add_child(value)
	return row


func _section_label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", COLOR_TITLE)
	label.add_theme_font_size_override(&"font_size", 13)
	return label


func _footnote(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", COLOR_FAINT)
	label.add_theme_font_size_override(&"font_size", 11)
	return label


func _empty_note(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", COLOR_MUTED)
	label.add_theme_font_size_override(&"font_size", 12)
	return label


## Hairline divider. A full HSeparator draws heavier than this UI wants.
func _rule() -> Control:
	var line: ColorRect = ColorRect.new()
	line.color = COLOR_LINE
	line.custom_minimum_size = Vector2(0, 1)
	return line


## Scrolling middle for a side panel, so its primary action stays pinned at the
## bottom and nothing is ever cut off the frame on a short window. Returns the
## column to fill; the caller keeps adding pinned rows to [param column] after it.
func _scroll_body(column: VBoxContainer) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var inner: VBoxContainer = VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override(&"separation", 8)
	scroll.add_child(inner)
	return inner


func _padded_column(host: Control) -> VBoxContainer:
	var pad: MarginContainer = MarginContainer.new()
	for side: StringName in [&"margin_left", &"margin_right", &"margin_top", &"margin_bottom"]:
		pad.add_theme_constant_override(side, 12)
	host.add_child(pad)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	pad.add_child(column)
	return column


func _cell(
	text: String,
	flags: int,
	width: float,
	color: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	size: int = 0
) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.size_flags_horizontal = flags
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = align
	# Ellipsis, not a hard clip: a name cut mid-glyph reads as a different item
	# ("Healing Herb" -> "Healing Herk"), which is worse than an obvious ellipsis.
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override(&"font_color", color)
	if size > 0:
		label.add_theme_font_size_override(&"font_size", size)
	return label


## A row's contents, inset from its own frame. [param overlay] is for hosts that
## do not lay their children out (a Button), where the body has to be anchored
## over the whole rect; a PanelContainer already sizes its child.
func _row_line(host: Control, overlay: bool) -> HBoxContainer:
	var margin: MarginContainer = MarginContainer.new()
	if overlay:
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", ROW_PAD)
	margin.add_theme_constant_override(&"margin_right", ROW_PAD)
	host.add_child(margin)

	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(line)
	return line


## Item icon in a fixed square.
##
## A plain TextureRect rather than PixelIcon.mount: mount positions its child by
## GLOBAL coordinates on a deferred callback, which is stale for a row that is
## built, re-parented into a MarginContainer and then scrolled — the icons ended
## up drawn offset from their own cell, bleeding over the item name. Aspect-fit
## in NEAREST keeps them crisp and needs no layout callback at all.
func _icon_cell(item: Item, size: float = ICON_SIZE) -> Control:
	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = Vector2(size, size)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = item.item_icon if item != null else null
	return icon


## Backing for a selected row: a gold left edge and a lifted fill.
func _selected_row_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.12, 0.09, 1.0)
	style.border_color = COLOR_GOLD
	style.border_width_left = 3
	style.set_corner_radius_all(3)
	return style


## Recessed panel behind a stat block — separates data from chrome without adding
## another hard border.
func _inset_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.22)
	style.set_corner_radius_all(4)
	return style


# --- Formatting -------------------------------------------------------------

func _item(item_id: int) -> Item:
	return ContentRegistryHub.load_by_id(&"items", item_id) as Item


func _item_name(item_id: int) -> String:
	var item: Item = _item(item_id)
	return String(item.item_name) if item != null else "Item #%d" % item_id


func _stack_label(item_id: int, amount: int) -> String:
	return _item_name(item_id) if amount <= 1 else "%s x %s" % [_format(amount), _item_name(item_id)]


## 1234567 -> "1,234,567". Prices are compared at a glance here; raw digit runs
## are exactly where a 10x misread happens.
func _format(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	var count: int = 0
	for i: int in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if amount < 0 else "") + out


## Compact "how long ago", measured against the SERVER's clock (shipped with the
## board) so a skewed local clock cannot make a fresh sale read as days old.
func _ago(at_ms: int) -> String:
	if at_ms <= 0 or _server_now_ms <= 0:
		return ""
	var seconds: int = int((_server_now_ms - at_ms) / 1000)
	if seconds < 60:
		return "now"
	if seconds < 3600:
		@warning_ignore("integer_division")
		return "%dm" % int(seconds / 60)
	if seconds < 86400:
		@warning_ignore("integer_division")
		return "%dh" % int(seconds / 3600)
	@warning_ignore("integer_division")
	return "%dd" % int(seconds / 86400)
