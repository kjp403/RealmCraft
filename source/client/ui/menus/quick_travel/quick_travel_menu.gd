extends MenuShell
## The Wayfarer's quick-travel board. Opened by [QuickTravelInteraction] with
## {"npc": node_name}; every price and gate on screen comes from the server's
## travel.quote reply, and picking a row books it with travel.quick.
##
## The client deliberately holds NO pricing logic. Fares move with the player's
## surge state and the gates depend on wardstones, so computing anything here
## would only create a second, drifting source of truth. This file lays the
## reply out and nothing more — the one local check it makes (can I afford it)
## is a courtesy so the "Insufficient Gold" toast is instant; the server still
## refuses the ride on its own authority.

const ACCENT: Color = Color(1.0, 0.41, 0.71)      # hot pink, the Wayfarer's colour
const ACCENT_DEEP: Color = Color(1.0, 0.08, 0.58) # deep pink, for the surge banner
const LOCKED_ALPHA: float = 0.45
const ROW_MIN_HEIGHT: float = 58.0
const DEPARTURE: GDScript = preload(
	"res://source/common/gameplay/quick_travel/quick_travel_departure.gd"
)

var _npc: String = ""
## True when the board was opened by a Biome Recall Scroll instead of by walking
## up to the Wayfarer. Sent with every request so the server resolves the same
## way twice; never used to decide a price, which is the server's alone.
var _scroll: bool = false
var _gold: int = 0
var _busy: bool = false # one ride at a time — blocks double-clicks mid-request
var _rows: VBoxContainer
var _status: Label
var _gold_label: Label
var _body: VBoxContainer


func _ready() -> void:
	# Menus live inside the HUD's Submenu (already z=100). The request asks quick
	# travel to sit above the map at z=10; that is its order among its siblings
	# here, and the shell's own backdrop still covers the world beneath it.
	z_index = 10
	_body = VBoxContainer.new()
	_body.add_theme_constant_override(&"separation", 8)
	build_shell("Quick Travel", _body)

	_gold_label = PixelUI.text("", PixelUI.SIZE_BODY, PixelUI.INK_COIN)
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
	_scroll = bool(data.get("scroll", false))
	_busy = false
	_set_status("Reading the board...", PixelUI.INK_DIM)
	_clear_rows()
	_request_quote()


## Ask the server what this desk sells THIS player, at THIS moment.
func _request_quote() -> void:
	if InstanceClient.current == null:
		_set_status("Not connected.", Color(1.0, 0.45, 0.45))
		return
	var result: Array = await Client.request_data_await(
		&"travel.quote", {"npc": _npc, "scroll": _scroll}, String(InstanceClient.current.name)
	)
	# The player can close the window or walk off while this is in flight.
	if not is_inside_tree() or not visible:
		return
	if result[1] != OK or not result[0].get("ok", false):
		_set_status(_quote_error(str(result[0].get("reason", ""))), Color(1.0, 0.45, 0.45))
		return
	# Trust the reply, not the arg we sent: if the server resolved this as a desk
	# rather than a scroll, the rows must not draw as free.
	_scroll = bool(result[0].get("scroll", false))
	_render(result[0])


func _quote_error(reason: String) -> String:
	match reason:
		"too_far":
			return "Step up to the Wayfarer to read the board."
		"dead":
			return "You cannot travel while dead."
		"jailed":
			return "You are jailed and cannot leave this area."
		"no_player", "npc_missing", "bad_npc", "no_desk":
			return "This desk is closed."
	return "The board is unreadable right now."


func _render(quote: Dictionary) -> void:
	_gold = int(quote.get("gold", 0))
	_gold_label.text = "%s G" % _commas(_gold)
	_clear_rows()

	var surge: float = float(quote.get("surge", 1.0))
	var rides: int = int(quote.get("rides", 0))
	var free_rides: int = int(quote.get("free_rides", 3))
	if surge > 1.0:
		_set_status(
			"Frequency surge %.1fx — %d rides in the last %d minutes. Fares ease in %s." % [
				surge, rides, int(quote.get("window_s", 600)) / 60,
				_clock(int(quote.get("cools_in_s", 0))),
			],
			ACCENT_DEEP
		)
	else:
		var left: int = maxi(0, free_rides - rides)
		_set_status(
			"Standard fares — %d more %s before the frequency surge applies." % [
				left, "ride" if left == 1 else "rides",
			],
			PixelUI.INK_DIM
		)

	for row: Variant in quote.get("destinations", []):
		_rows.add_child(_build_row(row as Dictionary))


func _build_row(row: Dictionary) -> Control:
	var lock: String = str(row.get("lock", ""))
	var fee: int = int(row.get("fee", 0))
	var base_fee: int = int(row.get("base_fee", fee))
	var locked: bool = not lock.is_empty()
	var affordable: bool = bool(row.get("affordable", false))

	var card: PanelContainer = PanelContainer.new()
	PixelUI.panel(card, "frame_iron", 8)
	card.custom_minimum_size = Vector2(0, ROW_MIN_HEIGHT)
	if locked:
		card.modulate = Color(1.0, 1.0, 1.0, LOCKED_ALPHA)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 10)
	pad.add_theme_constant_override(&"margin_right", 10)
	pad.add_theme_constant_override(&"margin_top", 6)
	pad.add_theme_constant_override(&"margin_bottom", 6)
	card.add_child(pad)

	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 10)
	pad.add_child(line)

	var texts: VBoxContainer = VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override(&"separation", 1)
	line.add_child(texts)

	texts.add_child(PixelUI.text(str(row.get("label", "?")), PixelUI.SIZE_BODY, ACCENT))
	# The lock reason REPLACES the flavour line: when a row cannot be taken, why
	# it cannot be taken is the only thing worth the pixels.
	var sub: String = lock if locked else str(row.get("blurb", ""))
	if not sub.is_empty():
		var sub_label: Label = PixelUI.text(
			sub,
			PixelUI.SIZE_TINY,
			Color(1.0, 0.62, 0.62) if locked else PixelUI.INK_DIM
		)
		sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(sub_label)

	var price: VBoxContainer = VBoxContainer.new()
	price.alignment = BoxContainer.ALIGNMENT_CENTER
	price.add_theme_constant_override(&"separation", 0)
	line.add_child(price)

	# A scroll ride is free, and saying "0 G" reads like a bug rather than a perk.
	var fee_label: Label = PixelUI.text(
		"Free" if _scroll else "%s G" % _commas(fee),
		PixelUI.SIZE_BODY,
		PixelUI.INK_COIN if affordable else Color(1.0, 0.45, 0.45)
	)
	fee_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.add_child(fee_label)
	# Say WHY the number is what it is. A fare the surge pushed into the price
	# ceiling is flat no matter how much more the player travels, so calling that
	# out matters more than showing a rise: without it a capped Sewers hop and a
	# never-surging Fire Forge hop both just read as "50,000" for no stated reason.
	var note: String = ""
	if bool(row.get("capped", false)):
		note = "fare cap"
	elif fee > base_fee:
		note = "was %s G" % _commas(base_fee)
	if not note.is_empty():
		var note_label: Label = PixelUI.text(note, PixelUI.SIZE_TINY, PixelUI.INK_DIM)
		note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price.add_child(note_label)

	var go: Button = Button.new()
	go.text = "Travel"
	go.custom_minimum_size = Vector2(84, 32)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.focus_mode = Control.FOCUS_NONE
	PixelUI.button_frame(go, "frame_iron", 6)
	PixelUI.button_font(go, PixelUI.SIZE_CAPTION, PixelUI.INK)
	go.disabled = locked
	go.tooltip_text = lock if locked else "Travel to %s" % str(row.get("label", ""))
	if not locked:
		go.pressed.connect(_on_travel_pressed.bind(int(row.get("index", -1)), fee))
	line.add_child(go)
	return card


func _on_travel_pressed(index: int, fee: int) -> void:
	if _busy or index < 0:
		return
	# Local courtesy check for instant feedback. The server re-checks and is the
	# one that actually refuses — this only saves a round trip and a blank stare.
	if fee > _gold:
		Toaster.toast("Insufficient Gold")
		return
	_busy = true
	_book(index)


func _book(index: int) -> void:
	if InstanceClient.current == null:
		_busy = false
		return
	var result: Array = await Client.request_data_await(
		&"travel.quick",
		{"npc": _npc, "index": index, "scroll": _scroll},
		String(InstanceClient.current.name)
	)
	var data: Dictionary = result[0] if result[1] == OK else {}
	if data.get("ok", false):
		# Paid, and the switch is under way. The bag changed, so nudge anything
		# showing a gold balance.
		if data.has("inventory"):
			ClientState.inventory_changed.emit({"quiet": true})
		_play_departure()
		return

	_busy = false
	match str(data.get("reason", "")):
		"gold":
			# Outspent between the quote and the click (another purchase, or the
			# surge ticked up). Re-quote so the board tells the truth again.
			Toaster.toast("Insufficient Gold")
			_gold = int(data.get("gold", _gold))
			_request_quote()
		"locked":
			# The server pushed the specific reason to chat; re-quote so the board
			# stops offering a row that is no longer available.
			_request_quote()
		"too_far":
			Toaster.toast("Too far from the Wayfarer.")
			hide()
		"jailed":
			hide() # the server already pushed a system line
		_:
			Toaster.toast("Cannot travel right now.")


## Subtle departure: the card drops away while a pink implosion plays on the
## traveller. Both are cosmetic — the instance switch is already under way and
## will tear this scene down mid-tween, which is fine.
func _play_departure() -> void:
	var lp: Node2D = ClientState.local_player
	if lp != null and is_instance_valid(lp) and lp.get_parent() != null:
		var burst: Node2D = DEPARTURE.new()
		lp.get_parent().add_child(burst)
		burst.global_position = lp.global_position

	var fade: Tween = create_tween()
	fade.set_parallel(true)
	fade.tween_property(self, ^"modulate:a", 0.0, 0.22)
	fade.tween_property(self, ^"scale", Vector2(0.96, 0.96), 0.22)
	fade.chain().tween_callback(_reset_after_departure)


## display_menu only calls show(), so a card left faded out would come back
## invisible next time the board is opened. Put it back.
func _reset_after_departure() -> void:
	hide()
	modulate.a = 1.0
	scale = Vector2.ONE


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override(&"font_color", color)


func _clear_rows() -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()


## 12345 -> "12,345".
func _commas(amount: int) -> String:
	var digits: String = str(absi(amount))
	var out: String = ""
	var i: int = digits.length()
	while i > 0:
		var start: int = maxi(0, i - 3)
		if not out.is_empty():
			out = "," + out
		out = digits.substr(start, i - start) + out
		i = start
	return ("-" + out) if amount < 0 else out


## Seconds -> "M:SS".
func _clock(seconds: int) -> String:
	return "%d:%02d" % [seconds / 60, seconds % 60]
