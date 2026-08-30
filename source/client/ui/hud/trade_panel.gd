extends MenuShell
## Private two-player trade window. The server owns invitations, offers,
## confirmations, validation, exchange, and persistence; this is only a view/editor.

const SLOTS: int = 6
const SEAT_COLORS: Array[Color] = [
	Color(0.96, 0.74, 0.16),
	Color(0.45, 0.7, 1.0),
]
const READY_COLOR: Color = Color(0.5, 0.9, 0.5)
const MUTED_COLOR: Color = Color(0.6, 0.62, 0.7)
const SLOT_SIZE: Vector2 = Vector2(54, 54)

var _trade_id: int = 0
## Bumps on every open/close so stale async `_refresh` awaits can't close a
## newer trade (typing in chat + accept races were doing exactly that).
var _refresh_generation: int = 0
var _owned: Dictionary = {}
var _owned_gold: int = 0
var _my_items: Dictionary = {}
var _my_gold: int = 0
var _my_accepted: bool = false
var _locked: bool = false
var _picker_open: bool = false
var _gold_pending: bool = false
var _countdown_tween: Tween

var _you_name: Label
var _you_grid: GridContainer
var _gold_row: HBoxContainer
var _gold_spin: SpinBox
var _add_button: Button
var _you_ready: Label
var _them_name: Label
var _them_grid: GridContainer
var _them_gold: Label
var _them_ready: Label
var _picker_overlay: Control
var _picker_grid: GridContainer
var _qty_overlay: Control
var _qty_title: Label
var _qty_spin: SpinBox
var _qty_item_id: int = 0
var _qty_is_gold: bool = false
var _countdown_label: Label
var _accept_button: Button
var _cancel_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Fullscreen shell: thin outer inset so Cancel / Confirm aren't clipped against
	# the window edge (the floating 22px bottom margin was shorter than the dock).
	build_shell("Secure Trade", null, true)
	# Default MenuShell backdrop is 50% — trade content sat on StyleBoxEmpty so the
	# world bled through and the panel looked "too transparent". Use a solid card.
	if backdrop != null:
		backdrop.color = Color(0.04, 0.05, 0.08, 0.82)
	_apply_solid_trade_card()
	_build_body()
	_build_picker_overlay()
	_build_qty_overlay()
	close_requested.connect(_on_leave)
	hide()
	ClientState.viewed_trade_changed.connect(_on_viewed_changed)
	Client.subscribe(&"trade.state", _on_trade_state)
	Client.subscribe(&"trade.result", _on_trade_result)
	Client.subscribe(&"trade.closed", _on_trade_closed)


## Replace the empty fullscreen card style with an opaque panel so offers stay readable.
func _apply_solid_trade_card() -> void:
	# MenuShell tree: card → pad → root → content
	var node: Node = content
	var card: PanelContainer = null
	while node != null:
		if node is PanelContainer:
			card = node as PanelContainer
			break
		node = node.get_parent()
	if card == null:
		return
	# Carved stone, the same card every MenuShell menu now draws. The trade panel
	# is a standalone overlay rather than a shell menu, so it has to ask for the
	# frame itself instead of inheriting it.
	PixelUI.panel(card, "frame_stone", 6)


func _build_body() -> void:
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 10)
	content.add_child(body)

	var safety := Label.new()
	safety.text = "Review both offers carefully. Any change clears both confirmations."
	safety.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	safety.add_theme_color_override(&"font_color", MUTED_COLOR)
	safety.add_theme_font_size_override(&"font_size", 12)
	body.add_child(safety)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override(&"separation", 18)
	body.add_child(columns)
	columns.add_child(_build_your_column())
	columns.add_child(VSeparator.new())
	columns.add_child(_build_their_column())

	var ready_row := HBoxContainer.new()
	ready_row.add_theme_constant_override(&"separation", 18)
	body.add_child(ready_row)
	_you_ready = Label.new()
	_you_ready.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ready_row.add_child(_you_ready)
	_them_ready = Label.new()
	_them_ready.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ready_row.add_child(_them_ready)

	body.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override(&"separation", 8)
	body.add_child(footer)
	_countdown_label = Label.new()
	_countdown_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_countdown_label.add_theme_color_override(&"font_color", READY_COLOR)
	footer.add_child(_countdown_label)
	_cancel_button = _make_action("Cancel Trade", _on_leave)
	_accept_button = _make_action("Confirm Offer", _on_accept)
	_accept_button.custom_minimum_size = Vector2(130, 34)
	footer.add_child(_cancel_button)
	footer.add_child(_accept_button)


func _build_your_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)
	_you_name = _column_header(col, "Your offer")
	_you_grid = _make_grid()
	col.add_child(_you_grid)

	_gold_row = HBoxContainer.new()
	_gold_row.add_theme_constant_override(&"separation", 6)
	col.add_child(_gold_row)
	var gold_label := Label.new()
	gold_label.text = "Gold"
	gold_label.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.4))
	_gold_row.add_child(gold_label)
	_gold_spin = SpinBox.new()
	_gold_spin.min_value = 0
	_gold_spin.step = 1
	_gold_spin.rounded = true
	_gold_spin.custom_minimum_size = Vector2(110, 32)
	_gold_spin.select_all_on_focus = true
	_gold_spin.value_changed.connect(_on_gold_spin_pending)
	_gold_spin.get_line_edit().text_submitted.connect(func(_text: String) -> void:
		_on_set_gold())
	_gold_row.add_child(_gold_spin)
	_gold_row.add_child(_make_action("Set", _on_set_gold))
	var gold_x := _make_action("X", _on_gold_type_amount)
	gold_x.tooltip_text = "Type how much gold to offer"
	_gold_row.add_child(gold_x)
	var gold_all := _make_action("All", _on_gold_all)
	gold_all.tooltip_text = "Offer all of your gold"
	_gold_row.add_child(gold_all)

	_add_button = _make_action("Add gold / items", _toggle_picker)
	_add_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_add_button)
	return col


func _build_their_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)
	_them_name = _column_header(col, "Their offer")
	_them_grid = _make_grid()
	col.add_child(_them_grid)
	_them_gold = Label.new()
	_them_gold.text = "Gold offered: 0"
	_them_gold.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.4))
	_them_gold.add_theme_font_size_override(&"font_size", 16)
	col.add_child(_them_gold)
	return col


func _build_picker_overlay() -> void:
	_picker_overlay = Control.new()
	_picker_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picker_overlay.visible = false
	add_child(_picker_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.08, 0.65)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventScreenTouch and event.pressed):
			_close_picker())
	_picker_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picker_overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(390, 0)
	center.add_child(card)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	card.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	pad.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.text = "Add gold or items from your bag"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	header.add_child(title)
	header.add_child(_make_action("Done", _close_picker))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(366, 252)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_picker_grid = GridContainer.new()
	_picker_grid.columns = 5
	scroll.add_child(_picker_grid)


func _on_viewed_changed(trade_id: int) -> void:
	_refresh_generation += 1
	_trade_id = trade_id
	if trade_id <= 0:
		_close_picker()
		hide()
		return
	_gold_pending = false
	# Typing in chat holds LineEdit focus; release it so the trade overlay owns input.
	var focused: Control = get_viewport().gui_get_focus_owner() as Control
	if focused != null:
		focused.release_focus()
	show()
	move_to_front()
	_refresh()


func _refresh() -> void:
	if InstanceClient.current == null or _trade_id <= 0:
		return
	var generation: int = _refresh_generation
	var trade_id: int = _trade_id
	var inventory_result: Array = await Client.request_data_await(
		&"inventory.get",
		{},
		InstanceClient.current.name
	)
	if not is_instance_valid(self) or generation != _refresh_generation \
			or trade_id != _trade_id or not visible:
		return
	if inventory_result.size() >= 2 and inventory_result[1] == OK:
		_recompute_owned(inventory_result[0])
	var state_result: Array = await Client.request_data_await(
		&"trade.state",
		{"trade": trade_id},
		InstanceClient.current.name
	)
	if not is_instance_valid(self) or generation != _refresh_generation \
			or trade_id != _trade_id or not visible:
		return
	var state_payload: Dictionary = {}
	if state_result.size() >= 2 and state_result[1] == OK \
			and state_result[0] is Dictionary:
		state_payload = state_result[0]
	# Empty reply is usually a transient rate-limit / race — keep the panel open
	# and wait for the authoritative trade.state push instead of closing.
	if state_payload.is_empty():
		return
	_render(state_payload)


func _recompute_owned(inventory: Dictionary) -> void:
	_owned.clear()
	_owned_gold = 0
	for slot_uid: Variant in inventory:
		var data: Dictionary = inventory[slot_uid]
		var item_id: int = int(data.get("id", 0))
		var amount: int = int(data.get("a", 0))
		if item_id == Economy.gold_id():
			_owned_gold += amount
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item == null or item.is_currency or not item.can_trade:
			continue
		_owned[item_id] = int(_owned.get(item_id, 0)) + amount


func _on_trade_state(data: Dictionary) -> void:
	var state_id: int = int(data.get("id", 0))
	if state_id <= 0:
		return
	# Apply even if show() hasn't painted yet — open + broadcast can race while
	# chat focus / HUD hide is mid-flight.
	if _trade_id <= 0:
		_trade_id = state_id
	if state_id != _trade_id:
		return
	if not visible:
		show()
		move_to_front()
	_render(data)


func _render(data: Dictionary) -> void:
	var seats: Array = data.get("seats", [])
	if seats.size() != 2:
		return
	var my_index: int = _seat_index_for_local(seats)
	if my_index < 0:
		# Don't hard-close on a single mismatched frame (player_id push can lag);
		# retry once via refresh instead of vanishing the window for one peer.
		return
	_locked = bool(data.get("locked", false))
	_render_you(seats[my_index], my_index)
	_render_them(seats[1 - my_index], 1 - my_index)
	_render_footer(int(data.get("countdown", 0)))


func _seat_index_for_local(seats: Array) -> int:
	var my_id: int = int(ClientState.player_id)
	if my_id > 0:
		for i: int in seats.size():
			if int(seats[i].get("id", 0)) == my_id:
				return i
	# Fallback: peer_id carried in the seat payload (added for this race).
	var my_peer: int = multiplayer.get_unique_id() if multiplayer != null else 0
	if my_peer > 0:
		for i: int in seats.size():
			if int(seats[i].get("peer", 0)) == my_peer:
				return i
	# Last resort: match local display name so a late player_id.set can't blank the UI.
	var local_name: String = ""
	if ClientState.local_player != null:
		local_name = str(ClientState.local_player.display_name)
	if not local_name.is_empty():
		for i: int in seats.size():
			if str(seats[i].get("name", "")) == local_name:
				return i
	return -1


func _render_you(mine: Dictionary, seat_index: int) -> void:
	_you_name.text = str(mine.get("name", "You"))
	_you_name.add_theme_color_override(
		&"font_color",
		SEAT_COLORS[seat_index % SEAT_COLORS.size()]
	)
	_my_items = {}
	for item: Dictionary in mine.get("items", []):
		_my_items[int(item.get("id", 0))] = int(item.get("amount", 0))
	_my_gold = int(mine.get("gold", 0))
	_my_accepted = bool(mine.get("accepted", false))
	_fill_grid(_you_grid, _my_items, true)
	_gold_spin.max_value = maxi(0, _owned_gold)
	if not _gold_pending:
		_gold_spin.set_value_no_signal(_my_gold)
	_gold_spin.editable = not _locked
	_add_button.disabled = _locked or _my_items.size() >= SLOTS
	_set_ready_line(_you_ready, _my_accepted)
	if _locked:
		_close_picker()
	elif _picker_open:
		_rebuild_picker()


func _render_them(other: Dictionary, seat_index: int) -> void:
	_them_name.text = str(other.get("name", "Player"))
	_them_name.add_theme_color_override(
		&"font_color",
		SEAT_COLORS[seat_index % SEAT_COLORS.size()]
	)
	var their_items: Dictionary = {}
	for item: Dictionary in other.get("items", []):
		their_items[int(item.get("id", 0))] = int(item.get("amount", 0))
	_fill_grid(_them_grid, their_items, false)
	_them_gold.text = "Gold offered: %d" % int(other.get("gold", 0))
	_set_ready_line(_them_ready, bool(other.get("accepted", false)))


func _render_footer(countdown: int) -> void:
	_accept_button.disabled = _locked
	_accept_button.text = "Undo Confirmation" if _my_accepted else "Confirm Offer"
	if countdown > 0:
		_run_countdown(countdown)
	else:
		_stop_countdown()


func _fill_grid(grid: GridContainer, items: Dictionary, mine: bool) -> void:
	for child: Node in grid.get_children():
		child.queue_free()
	var count: int = 0
	for item_id: int in items:
		grid.add_child(_make_slot(item_id, int(items[item_id]), mine))
		count += 1
	for _index: int in maxi(0, SLOTS - count):
		grid.add_child(_make_empty_slot(mine))


func _make_slot(item_id: int, amount: int, mine: bool) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.clip_contents = true
	slot.focus_mode = Control.FOCUS_NONE
	# Keep mouse events so tooltips work on their offer / locked slots too.
	# Only wire remove-on-click while the offer is still editable.
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null:
		PixelIcon.mount(slot, item.item_icon)
		slot.tooltip_text = ItemTooltip.hover_text(item)
	slot.add_child(_count_badge(amount))
	if mine and not _locked:
		slot.pressed.connect(_remove_from_offer.bind(item_id))
	return slot


func _make_empty_slot(mine: bool) -> Button:
	var slot := Button.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.focus_mode = Control.FOCUS_NONE
	slot.modulate = Color(1, 1, 1, 0.4)
	if mine and not _locked:
		slot.pressed.connect(_open_picker)
	else:
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return slot


func _count_badge(amount: int) -> Label:
	var badge := Label.new()
	badge.text = "x%d" % amount
	badge.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
	badge.add_theme_constant_override(&"outline_size", 4)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	return badge


func _add_to_offer(item_id: int, amount: int = 1) -> void:
	if _locked:
		return
	var owned: int = int(_owned.get(item_id, 0))
	if owned <= 0:
		return
	var add: int = clampi(amount, 1, owned)
	if _my_items.has(item_id):
		_my_items[item_id] = mini(int(_my_items[item_id]) + add, owned)
	elif _my_items.size() < SLOTS:
		_my_items[item_id] = add
	else:
		Toaster.toast("Your offer is full (%d item types maximum)." % SLOTS)
		return
	_send_offer()


func _set_offer_amount(item_id: int, amount: int) -> void:
	if _locked:
		return
	var owned: int = int(_owned.get(item_id, 0))
	amount = clampi(amount, 0, owned)
	if amount <= 0:
		_my_items.erase(item_id)
	elif _my_items.has(item_id) or _my_items.size() < SLOTS:
		_my_items[item_id] = amount
	else:
		Toaster.toast("Your offer is full (%d item types maximum)." % SLOTS)
		return
	_send_offer()


func _remove_from_offer(item_id: int) -> void:
	if _locked:
		return
	var amount: int = int(_my_items.get(item_id, 0)) - 1
	if amount > 0:
		_my_items[item_id] = amount
	else:
		_my_items.erase(item_id)
	_send_offer()


func _send_offer() -> void:
	if InstanceClient.current == null or _trade_id <= 0:
		return
	Client.request_data(
		&"trade.offer",
		_on_offer_result,
		{"trade": _trade_id, "items": _my_items, "gold": _my_gold},
		InstanceClient.current.name
	)


func _on_offer_result(payload: Dictionary) -> void:
	if bool(payload.get("ok", false)):
		return
	match str(payload.get("reason", "")):
		"untradeable": Toaster.toast("That item cannot be traded.")
		"items": Toaster.toast("You no longer have all offered items.")
		"gold": Toaster.toast("You no longer have that much gold.")
		"locked": Toaster.toast("The offer is locked for final confirmation.")
		_: Toaster.toast("The offer could not be updated.")
	_refresh()


func _on_set_gold() -> void:
	if _locked:
		return
	_gold_spin.apply()
	_my_gold = mini(int(_gold_spin.value), _owned_gold)
	_gold_spin.get_line_edit().release_focus()
	_gold_pending = false
	_send_offer()


func _on_gold_all() -> void:
	if _locked:
		return
	_gold_spin.set_value_no_signal(_owned_gold)
	_my_gold = _owned_gold
	_gold_pending = false
	_send_offer()


func _on_gold_type_amount() -> void:
	if _locked or _owned_gold <= 0:
		return
	_open_qty(0, true)


func _on_gold_spin_pending(_value: float) -> void:
	_gold_pending = true


func _open_picker() -> void:
	if _locked:
		return
	_picker_open = true
	_picker_overlay.visible = true
	_rebuild_picker()


func _toggle_picker() -> void:
	if _picker_open:
		_close_picker()
	else:
		_open_picker()


func _close_picker() -> void:
	_picker_open = false
	if _picker_overlay != null:
		_picker_overlay.visible = false
	_close_qty()


func _rebuild_picker() -> void:
	for child: Node in _picker_grid.get_children():
		child.queue_free()
	var any: bool = false
	if _owned_gold > 0:
		any = true
		_picker_grid.add_child(_make_picker_gold_button())
	for item_id: int in _owned:
		if int(_owned[item_id]) <= 0:
			continue
		any = true
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		var button := Button.new()
		button.custom_minimum_size = SLOT_SIZE
		button.clip_contents = true
		button.focus_mode = Control.FOCUS_NONE
		var owned: int = int(_owned[item_id])
		if item != null:
			PixelIcon.mount(button, item.item_icon)
			button.tooltip_text = "%s\n(have %d — click to offer an amount)" % [
				ItemTooltip.hover_text(item),
				owned,
			]
			button.add_child(_count_badge(owned))
		if owned > 1:
			button.pressed.connect(_open_qty.bind(item_id, false))
		else:
			button.pressed.connect(_add_to_offer.bind(item_id, 1))
		_picker_grid.add_child(button)
	if not any:
		var empty := Label.new()
		empty.text = "You have no tradeable bag items."
		empty.add_theme_color_override(&"font_color", MUTED_COLOR)
		_picker_grid.add_child(empty)


func _make_picker_gold_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.clip_contents = true
	button.focus_mode = Control.FOCUS_NONE
	var gold_item: Item = ContentRegistryHub.load_by_id(&"items", Economy.gold_id()) as Item
	if gold_item != null:
		PixelIcon.mount(button, gold_item.item_icon)
	button.tooltip_text = "Gold\n(have %d — click to offer an amount)" % _owned_gold
	button.add_child(_count_badge(_owned_gold))
	button.pressed.connect(_open_qty.bind(0, true))
	return button


func _build_qty_overlay() -> void:
	_qty_overlay = Control.new()
	_qty_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_qty_overlay.visible = false
	_qty_overlay.z_index = 8
	add_child(_qty_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.05, 0.08, 0.7)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if (event is InputEventMouseButton and event.pressed) \
				or (event is InputEventScreenTouch and event.pressed):
			_close_qty())
	_qty_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty_overlay.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(280, 0)
	center.add_child(card)
	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	card.add_child(pad)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	pad.add_child(box)
	_qty_title = Label.new()
	_qty_title.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.5))
	box.add_child(_qty_title)
	_qty_spin = SpinBox.new()
	_qty_spin.min_value = 1
	_qty_spin.step = 1
	_qty_spin.rounded = true
	_qty_spin.select_all_on_focus = true
	_qty_spin.custom_minimum_size = Vector2(120, 32)
	_qty_spin.get_line_edit().text_submitted.connect(func(_text: String) -> void:
		_confirm_qty())
	box.add_child(_qty_spin)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override(&"separation", 6)
	box.add_child(btns)
	btns.add_child(_make_action("1", func() -> void: _qty_spin.value = 1))
	var x_btn := _make_action("X", func() -> void:
		_qty_spin.get_line_edit().grab_focus()
		_qty_spin.get_line_edit().select_all())
	x_btn.tooltip_text = "Type a custom amount"
	btns.add_child(x_btn)
	btns.add_child(_make_action("All", func() -> void:
		_qty_spin.value = _qty_spin.max_value))
	btns.add_child(_make_action("Offer", _confirm_qty))


func _open_qty(item_id: int, is_gold: bool) -> void:
	if _locked or _qty_overlay == null:
		return
	_qty_item_id = item_id
	_qty_is_gold = is_gold
	var owned: int = _owned_gold if is_gold else int(_owned.get(item_id, 0))
	if owned <= 0:
		return
	if is_gold:
		_qty_title.text = "Offer gold (have %d)" % owned
		_qty_spin.min_value = 0
	else:
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		var name: String = String(item.item_name) if item != null else "item"
		_qty_title.text = "Offer %s (have %d)" % [name, owned]
		_qty_spin.min_value = 1
	_qty_spin.max_value = owned
	var current: int = _my_gold if is_gold else int(_my_items.get(item_id, 0))
	# Default to 1 (or the current offer), never the full stack. Typing into a
	# FOCUS_NONE overlay used to leave this at "all owned" when Offer was clicked.
	_qty_spin.set_value_no_signal(current if current > 0 else 1)
	_qty_overlay.visible = true
	_qty_spin.get_line_edit().grab_focus()
	_qty_spin.get_line_edit().select_all()


func _close_qty() -> void:
	if _qty_overlay != null:
		_qty_overlay.visible = false
	_qty_item_id = 0
	_qty_is_gold = false


func _confirm_qty() -> void:
	_qty_spin.apply()
	var amount: int = int(_qty_spin.value)
	if _qty_is_gold:
		_gold_spin.set_value_no_signal(mini(amount, _owned_gold))
		_my_gold = mini(amount, _owned_gold)
		_gold_pending = false
		_send_offer()
	else:
		_set_offer_amount(_qty_item_id, amount)
	_close_qty()


func _on_accept() -> void:
	if InstanceClient.current == null or _trade_id <= 0 or _locked:
		return
	Client.request_data(
		&"trade.accept",
		Callable(),
		{"trade": _trade_id, "accepted": not _my_accepted},
		InstanceClient.current.name
	)


func _on_leave() -> void:
	var leaving_trade: int = _trade_id
	if leaving_trade <= 0:
		return
	ClientState.set_viewed_trade(0)
	if InstanceClient.current != null:
		Client.request_data(
			&"trade.leave",
			Callable(),
			{"trade": leaving_trade},
			InstanceClient.current.name
		)


func _on_trade_result(data: Dictionary) -> void:
	if _trade_id <= 0 or int(data.get("trade", 0)) != _trade_id:
		return
	if bool(data.get("ok", false)):
		Toaster.toast(_received_summary(data.get("received", {})))
	else:
		Toaster.toast("Trade failed. No items or gold were exchanged.")
	ClientState.set_viewed_trade(0)


func _on_trade_closed(data: Dictionary) -> void:
	if int(data.get("trade", 0)) != _trade_id:
		return
	var reason: String = str(data.get("reason", "Trade cancelled."))
	ClientState.set_viewed_trade(0)
	if not reason.is_empty():
		Toaster.toast(reason)


func _received_summary(received: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item: Dictionary in received.get("items", []):
		parts.append("%dx %s" % [
			int(item.get("amount", 1)),
			str(item.get("name", "?")),
		])
	var gold: int = int(received.get("gold", 0))
	if gold > 0:
		parts.append("%d gold" % gold)
	return "Trade complete." if parts.is_empty() \
		else "Trade complete — received %s." % ", ".join(parts)


func _run_countdown(seconds: int) -> void:
	_stop_countdown()
	_countdown_tween = create_tween()
	_countdown_tween.tween_method(
		_set_countdown_text,
		float(seconds),
		0.0,
		float(seconds)
	)


func _set_countdown_text(value: float) -> void:
	_countdown_label.text = "Offers locked — completing in %d…" % maxi(
		1,
		ceili(value)
	)


func _stop_countdown() -> void:
	if _countdown_tween != null and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown_tween = null
	if _countdown_label != null:
		_countdown_label.text = ""


func _column_header(col: VBoxContainer, caption: String) -> Label:
	var row := HBoxContainer.new()
	col.add_child(row)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_color_override(&"font_color", MUTED_COLOR)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cap)
	var name_label := Label.new()
	name_label.add_theme_font_size_override(&"font_size", 14)
	row.add_child(name_label)
	return name_label


func _make_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	return grid


func _make_action(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button


func _set_ready_line(label: Label, accepted: bool) -> void:
	label.text = "Confirmed" if accepted else "Reviewing offer"
	label.add_theme_color_override(
		&"font_color",
		READY_COLOR if accepted else MUTED_COLOR
	)
