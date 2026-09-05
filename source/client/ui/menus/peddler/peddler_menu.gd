extends MenuShell
## The Traveling Peddler's cart. Opened by [PeddlerInteraction] with
## {"npc": node_name}; the three goods, their prices, their SOLD OUT states and
## the closing clock all come from the server's peddler.stock reply, and a row is
## bought with peddler.buy.
##
## The client holds NO stock logic. Which three goods are on sale is a function of
## the server's UTC date, and whether one is spent is a function of a ledger only
## the server has — recomputing either here would be a second source of truth that
## rots the first time the clock or the catalog moves. This file lays the reply
## out and nothing else. Its one local check (can I afford it) is a courtesy so
## the "Insufficient Gold" toast is instant; the server still refuses on its own
## authority.

const ROW_MIN_HEIGHT: float = 76.0
const SOLD_OUT_ALPHA: float = 0.45
const ICON_SIZE: Vector2 = Vector2(40, 40)
## Warn colour once the cart is nearly packed up.
const CLOSING_SOON_S: int = 5 * 60
const INK_WARN: Color = Color(1.0, 0.55, 0.35)
const INK_BAD: Color = Color(1.0, 0.45, 0.45)

var _npc: String = ""
var _gold: int = 0
var _busy: bool = false # one purchase at a time — blocks double-clicks mid-request
var _rows: VBoxContainer
var _status: Label
var _gold_label: Label
var _body: VBoxContainer


func _ready() -> void:
	# Menus live inside the HUD's Submenu (already z=100); this is its order among
	# its siblings, and the shell's backdrop still covers the world beneath it.
	z_index = 10
	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 8)
	build_shell("Traveling Peddler", _body)

	_gold_label = PixelUI.text("", PixelUI.SIZE_BODY, PixelUI.INK_COIN)
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_label.clip_text = false
	_gold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	# A Label ignores the mouse by default; the purse needs to be hoverable so
	# the exact figure in its tooltip is reachable.
	_gold_label.mouse_filter = Control.MOUSE_FILTER_STOP
	header_right.add_child(_gold_label)
	header_right.move_child(_gold_label, 0) # sit before the Close button

	_status = PixelUI.text("", PixelUI.SIZE_CAPTION, PixelUI.INK_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_status)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_rows)


func open(arg: Variant) -> void:
	var data: Dictionary = arg if arg is Dictionary else {}
	_npc = str(data.get("npc", ""))
	_busy = false
	_set_status("Looking over the cart...", PixelUI.INK_DIM)
	_clear_rows()
	_request_stock()


## Ask the server what the cart sells THIS player, on THIS date.
func _request_stock() -> void:
	if InstanceClient.current == null:
		_set_status("Not connected.", INK_BAD)
		return
	var result: Array = await Client.request_data_await(
		&"peddler.stock", {"npc": _npc}, String(InstanceClient.current.name)
	)
	# The player can close the window or walk off while this is in flight.
	if not is_inside_tree() or not visible:
		return
	if result[1] != OK or not result[0].get("ok", false):
		_set_status(_stock_error(str(result[0].get("reason", ""))), INK_BAD)
		_clear_rows()
		return
	_render(result[0])


func _stock_error(reason: String) -> String:
	match reason:
		"too_far":
			return "Step up to the cart to see the wares."
		"dead":
			return "You cannot trade while dead."
		"jailed":
			return "You are jailed and cannot trade."
		"closed":
			return "The Peddler has packed up and moved on."
		"no_player", "npc_missing", "bad_npc", "no_desk":
			return "The cart is closed."
	return "The wares are covered over right now."


func _render(stock: Dictionary) -> void:
	_gold = int(stock.get("gold", 0))
	_set_gold_display(_gold)
	_clear_rows()

	var closes_in: int = int(stock.get("closes_in_s", 0))
	_set_status(
		"Three wares today, one of each per day. The cart leaves in %s." % _clock(closes_in),
		INK_WARN if closes_in <= CLOSING_SOON_S else PixelUI.INK_DIM
	)

	var rows: Array = stock.get("stock", []) as Array
	if rows.is_empty():
		_set_status("The cart is empty today.", PixelUI.INK_DIM)
		return
	for row: Variant in rows:
		_rows.add_child(_build_row(row as Dictionary))


func _build_row(row: Dictionary) -> Control:
	var tier: String = str(row.get("tier", PeddlerItemData.TIER_B))
	var accent: Color = PeddlerItemData.tier_color(tier)
	var price: int = int(row.get("price", 0))
	var sold_out: bool = bool(row.get("sold_out", false))
	var lock: String = str(row.get("lock", ""))
	var locked: bool = not lock.is_empty()
	var affordable: bool = bool(row.get("affordable", false))

	var card: PanelContainer = PanelContainer.new()
	PixelUI.panel(card, "frame_iron", 8)
	card.custom_minimum_size = Vector2(0, ROW_MIN_HEIGHT)
	if locked:
		card.modulate = Color(1.0, 1.0, 1.0, SOLD_OUT_ALPHA)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 10)
	pad.add_theme_constant_override(&"margin_right", 10)
	pad.add_theme_constant_override(&"margin_top", 6)
	pad.add_theme_constant_override(&"margin_bottom", 6)
	card.add_child(pad)

	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	pad.add_child(line)
	line.add_child(_icon_for(row, tier))

	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override(&"separation", 1)
	line.add_child(texts)

	var title: HBoxContainer = HBoxContainer.new()
	title.add_theme_constant_override(&"separation", 6)
	texts.add_child(title)
	title.add_child(PixelUI.text(str(row.get("item_name", "?")), PixelUI.SIZE_BODY, accent))
	title.add_child(PixelUI.text("%s-tier" % tier, PixelUI.SIZE_TINY, accent))

	# The lock reason REPLACES the flavour text: when a row cannot be bought, why
	# is the only thing worth the pixels.
	var sub: String = lock if locked else str(row.get("description", ""))
	if not sub.is_empty():
		var sub_label: Label = PixelUI.text(
			sub, PixelUI.SIZE_TINY, INK_BAD if locked else PixelUI.INK_DIM
		)
		sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(sub_label)

	var right: VBoxContainer = VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override(&"separation", 4)
	line.add_child(right)

	var price_label: Label = PixelUI.text(
		"%s G" % _commas(price),
		PixelUI.SIZE_BODY,
		PixelUI.INK_COIN if affordable else INK_BAD
	)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(price_label)

	var buy: Button = Button.new()
	buy.text = "SOLD OUT" if sold_out else "Buy"
	buy.custom_minimum_size = Vector2(92, 32)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.focus_mode = Control.FOCUS_NONE
	PixelUI.button_frame(buy, "frame_iron", 6)
	PixelUI.button_font(buy, PixelUI.SIZE_CAPTION, PixelUI.INK)
	buy.disabled = locked
	buy.tooltip_text = lock if locked else "Buy %s" % str(row.get("item_name", ""))
	if not locked:
		buy.pressed.connect(_on_buy_pressed.bind(str(row.get("id", "")), price))
	right.add_child(buy)
	return card


## The row's art. Falls back to the tier swatch PeddlerItemData generates, so an
## unfinished good shows a coloured chip rather than an empty square.
func _icon_for(row: Dictionary, tier: String) -> TextureRect:
	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var item_id: int = int(row.get("item_id", 0))
	var item: Item = (
		ContentRegistryHub.load_by_id(&"items", item_id) as Item if item_id > 0 else null
	)
	icon.texture = item.item_icon if item != null else PeddlerItemData.fallback_icon(tier)
	return icon


func _on_buy_pressed(stock_id: String, price: int) -> void:
	if _busy or stock_id.is_empty():
		return
	# Local courtesy check for instant feedback. The server re-checks and is the
	# one that actually refuses — this only saves a round trip and a blank stare.
	if price > _gold:
		Toaster.toast("Insufficient Gold")
		return
	_busy = true
	_buy(stock_id)


func _buy(stock_id: String) -> void:
	if InstanceClient.current == null:
		_busy = false
		return
	var result: Array = await Client.request_data_await(
		&"peddler.buy", {"npc": _npc, "id": stock_id}, String(InstanceClient.current.name)
	)
	_busy = false
	if not is_inside_tree() or not visible:
		return
	var data: Dictionary = result[0] if result[1] == OK else {}
	if data.get("ok", false):
		Toaster.toast("Bought %s." % str(data.get("item_name", "it")))
		ClientState.inventory_changed.emit({"quiet": true})
		# Re-read rather than flipping the row locally: the purchase moved gold as
		# well as the allowance, and the server's numbers are the ones that count.
		_request_stock()
		return

	match str(data.get("reason", "")):
		"cant_afford":
			Toaster.toast("Insufficient Gold")
			_request_stock()
		"sold_out":
			Toaster.toast("You have already bought that today.")
			_request_stock()
		"inventory_full":
			Toaster.toast("Your bag is full.")
		"too_far":
			Toaster.toast("Too far from the cart.")
			hide()
		"closed":
			Toaster.toast("The Peddler has moved on.")
			hide()
		"jailed":
			hide() # the server already pushed a system line
		_:
			Toaster.toast("The Peddler will not sell you that.")
			_request_stock()


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)


func _clear_rows() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()


## Paints the purse chip. [member _gold] keeps the RAW total the price checks
## read; only this readout abbreviates, and the exact figure stays on the
## label's tooltip so the player can see the last coin before paying.
func _set_gold_display(gold: int) -> void:
	if _gold_label == null:
		return
	var purse: Dictionary = NumberFormat.format_stack_size(gold)
	var purse_color: Color = purse["color"]
	_gold_label.text = "%s G" % purse["text"]
	_gold_label.add_theme_color_override(&"font_color", purse_color)
	_gold_label.tooltip_text = "%s gold" % purse["exact_text"]


## 12345 -> "12,345".
func _commas(amount: int) -> String:
	return NumberFormat.with_commas(amount)


## Seconds -> "M:SS".
func _clock(seconds: int) -> String:
	@warning_ignore("integer_division")
	var minutes: int = maxi(0, seconds) / 60
	return "%d:%02d" % [minutes, maxi(0, seconds) % 60]
