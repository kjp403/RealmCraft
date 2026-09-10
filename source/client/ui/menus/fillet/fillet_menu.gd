extends Control
## The Fillet panel — opened by right-clicking a Fillet Knife (see
## [FilletKnifeItem]) and reached through Hud.display_menu(&"fillet").
##
## A VIEW, NOTHING MORE. It renders whatever `fillet.list` returns and sends
## `fillet.convert`; it never computes a yield, never edits the bag, and never
## decides what counts as raw fish. Every one of those lives server-side in
## [FilletService] / [FilletTable], because the client's inventory is a mirror —
## [PlayerResource] is always null here.
##
## It also does not patch its own rows after a conversion: the convert reply
## carries a fresh list, and the panel redraws from that. Patching locally is how a
## grid ends up offering a fish the player no longer has.

## Grid columns. 1 keeps each fish on its own full-width row, which is what makes
## the icon / name / count / yield columns line up as a table.
const COLUMNS: int = 1

## Horizontal padding between a row's contents and its frame, per side.
const ROW_INSET_PX: float = 8.0

var _rows: Array = []
var _busy: bool = false

var _list: GridContainer
var _summary: Label
var _all_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_shell()


## [param _arg] is the knife's item id, which this panel does not need — the server
## re-derives the knife from the player's own bag. Accepted because display_menu
## passes it.
func open(_arg: Variant = null) -> void:
	_refresh()


# ---------------------------------------------------------------------------
# Shell
# ---------------------------------------------------------------------------

func _build_shell() -> void:
	for child: Node in get_children():
		child.queue_free()

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.7)
	# STOP, not IGNORE: the backdrop is what swallows clicks meant for the world
	# behind an open menu.
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	PixelUI.panel(card, "frame_stone", 12)
	center.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	card.add_child(column)

	var title: Label = PixelUI.text("Fillet", PixelUI.SIZE_HEADING, PixelUI.INK_GOLD)
	column.add_child(title)

	_summary = PixelUI.text("", PixelUI.SIZE_CAPTION, PixelUI.INK_DIM)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary)

	# The grid scrolls rather than growing the card: a player with a dozen species
	# in three bags would otherwise push the buttons off-screen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 240)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_list = GridContainer.new()
	_list.columns = COLUMNS
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"v_separation", 4)
	scroll.add_child(_list)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	column.add_child(actions)

	_all_button = Button.new()
	_all_button.text = "Fillet All"
	_all_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	PixelUI.button_frame(_all_button, "frame_iron")
	PixelUI.button_font(_all_button, PixelUI.SIZE_BODY, PixelUI.INK)
	_all_button.pressed.connect(_on_fillet_all)
	actions.add_child(_all_button)

	var close := Button.new()
	close.text = "Close"
	PixelUI.button_frame(close, "frame_iron")
	PixelUI.button_font(close, PixelUI.SIZE_BODY, PixelUI.INK_DIM)
	close.pressed.connect(hide)
	actions.add_child(close)


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if InstanceClient.current == null:
		return
	var result: Array = await Client.request_data_await(
		&"fillet.list", {}, InstanceClient.current.name
	)
	if result.size() < 2 or result[1] != OK:
		hide()
		return
	var payload: Dictionary = result[0] if result[0] is Dictionary else {}
	if not bool(payload.get("ok", false)):
		if str(payload.get("reason", "")) == "no_knife":
			Toaster.toast("You need a Fillet Knife.")
		hide()
		return
	_apply(payload)


func _apply(payload: Dictionary) -> void:
	_rows = payload.get("rows", []) as Array
	_render()


func _render() -> void:
	if _list == null:
		return
	for child: Node in _list.get_children():
		child.queue_free()

	var total_bait: int = 0
	var total_fish: int = 0
	for row: Dictionary in _rows:
		total_bait += int(row.get("bait", 0))
		# Fish, not ROWS. _rows.size() is the number of species, so a bag of 24
		# tuna and 11 lobster read as "2 fish" — which is both wrong and the
		# opposite of reassuring right before you press Fillet All.
		total_fish += int(row.get("held", 0))

	if _rows.is_empty():
		_summary.text = "No raw fish in your bags."
		_all_button.disabled = true
	else:
		_summary.text = "%d fish → %d bait" % [total_fish, total_bait]
		_all_button.disabled = _busy

	for row: Dictionary in _rows:
		_list.add_child(_build_row(row))


## One tappable fish row: icon, name, held count, and what it cuts into.
func _build_row(row: Dictionary) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 40)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.disabled = _busy
	PixelUI.button_frame(button, "frame_iron", 6)
	button.pressed.connect(_on_fillet_one.bind(int(row.get("id", 0))))

	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Inset from the frame. PRESET_FULL_RECT zeroes the offsets, and the button's
	# own content margins do not apply to an anchored child — so without this the
	# bait figure on the widest row is drawn under the border and clipped.
	line.offset_left = ROW_INSET_PX
	line.offset_right = -ROW_INSET_PX
	line.add_theme_constant_override(&"separation", 8)
	# IGNORE so the layout never eats the click meant for the button under it.
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(line)

	# The icon host is a bare Control, NOT a Container: a Container collapses a
	# mounted PixelIcon to 0x0 and the slot renders empty, silently.
	var icon_host := Control.new()
	icon_host.custom_minimum_size = Vector2(28, 28)
	icon_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(icon_host)
	var item: Item = ContentRegistryHub.load_by_id(
		&"items", int(row.get("id", 0))
	) as Item
	if item != null:
		PixelIcon.mount(icon_host, item.item_icon)

	var name_label: Label = PixelUI.text(
		str(row.get("name", "")), PixelUI.SIZE_BODY, PixelUI.INK
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(name_label)

	var count_label: Label = PixelUI.text(
		"x%d" % int(row.get("held", 0)), PixelUI.SIZE_BODY, PixelUI.INK_DIM
	)
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(count_label)

	var bait_label: Label = PixelUI.text(
		"→ %d" % int(row.get("bait", 0)), PixelUI.SIZE_BODY, PixelUI.INK_GOLD
	)
	bait_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(bait_label)

	return button


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_fillet_one(item_id: int) -> void:
	# amount 0 means "all of this fish" — clicking a row fillets the stack, which
	# is the only thing anyone ever wants from a bag full of tuna.
	await _convert({"id": item_id, "amount": 0})


func _on_fillet_all() -> void:
	await _convert({"all": true})


## Send one conversion and redraw from the reply. `_busy` gates re-entry: without
## it a double-click sends two converts, and the second acts on a bag the first
## already emptied.
func _convert(args: Dictionary) -> void:
	if _busy or InstanceClient.current == null:
		return
	_busy = true
	_render()
	var result: Array = await Client.request_data_await(
		&"fillet.convert", args, InstanceClient.current.name
	)
	_busy = false

	if result.size() < 2 or result[1] != OK:
		Toaster.toast("Filleting failed.")
		_render()
		return

	var payload: Dictionary = result[0] if result[0] is Dictionary else {}
	if not bool(payload.get("ok", false)):
		Toaster.toast({
			"no_knife": "You need a Fillet Knife.",
			"not_fish": "That can't be filleted.",
			"none_held": "You don't have any of those.",
			"no_fish": "No raw fish in your bags.",
			"inventory_full": "Your bag is full. Bank some items first.",
			"no_bait_item": "Bait is unavailable. Try again after a server update.",
		}.get(str(payload.get("reason", "")), "Nothing to fillet."))
		# Re-list anyway: a refusal usually means this panel's picture of the bag
		# is already stale.
		await _refresh()
		return

	Toaster.toast("Filleted %d fish into %d bait." % [
		int(payload.get("converted", 0)), int(payload.get("bait", 0)),
	])
	if bool(payload.get("partial", false)):
		Toaster.toast("Your bag filled up — some fish are still there.")
	_apply(payload)
