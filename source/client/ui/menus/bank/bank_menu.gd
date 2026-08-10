extends MenuShell
## Personal bank vault. Left = bag, right = bank. Vault (and bag) stacks can be
## drag-rearranged like inventory. Bag left-click deposits only a single item;
## stacks of 2+ select into the amount row (X / Max / Deposit). Gold stays in
## the currency pouch — never banked as a stack.


const GRID_COLUMNS: int = 6
const SLOT_SIZE: Vector2 = Vector2(54, 54)
const MUTED: Color = Color(0.62, 0.64, 0.7)

var _inventory: Dictionary = {}
var _bank: Dictionary = {}
var _busy: bool = false

var _bag_grid: GridContainer
var _bank_grid: GridContainer
var _bag_count: Label
var _bank_count: Label
var _amount_spin: SpinBox
var _transfer_button: Button
var _deposit_all_button: Button
var _selection_label: Label

var _selected_uid: int = -1
var _selected_from_bag: bool = true
var _selected_have: int = 0
var _selected_name: String = ""
var _selected_item_id: int = 0


func _ready() -> void:
	build_shell("Bank", null, true)
	# Match Secure Trade: fullscreen MenuShell defaults to a 50% dim + empty card,
	# which left the vault unreadable over bright outdoor scenes.
	if backdrop != null:
		backdrop.color = Color(0.04, 0.05, 0.08, 0.82)
	_apply_solid_bank_card()
	_build_body()
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())
	_refresh.call_deferred()


func open(_arg: Variant = null) -> void:
	_refresh()


func _apply_solid_bank_card() -> void:
	var node: Node = content
	var card: PanelContainer = null
	while node != null:
		if node is PanelContainer:
			card = node as PanelContainer
			break
		node = node.get_parent()
	if card == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.14, 0.96)
	style.set_corner_radius_all(10)
	style.set_border_width_all(1)
	style.border_color = Color(0.28, 0.3, 0.38, 0.9)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 2
	style.content_margin_bottom = 4
	card.add_theme_stylebox_override(&"panel", style)


func _build_body() -> void:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override(&"separation", 10)
	content.add_child(root)

	var sides := HBoxContainer.new()
	sides.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sides.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sides.add_theme_constant_override(&"separation", 16)
	root.add_child(sides)

	sides.add_child(_build_side("Your bag", true))
	sides.add_child(VSeparator.new())
	sides.add_child(_build_side("Bank vault", false))

	root.add_child(HSeparator.new())
	root.add_child(_build_transfer_row())


func _build_side(title: String, is_bag: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	col.add_child(header)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.55))
	label.add_theme_font_size_override(&"font_size", 16)
	header.add_child(label)
	var count := Label.new()
	count.add_theme_color_override(&"font_color", MUTED)
	header.add_child(count)
	if is_bag:
		_deposit_all_button = Button.new()
		_deposit_all_button.text = "Deposit All"
		_deposit_all_button.focus_mode = Control.FOCUS_NONE
		_deposit_all_button.tooltip_text = "Move every bag item into the vault (gold stays in your pouch)."
		_deposit_all_button.pressed.connect(_on_deposit_all_pressed)
		header.add_child(_deposit_all_button)

	var hint := Label.new()
	hint.text = (
		"Qty 1: left-click deposits. Qty 2+: set amount (X/Max). Drag to rearrange. Or Deposit All."
		if is_bag
		else "Drag to rearrange. Click a stack, set amount (X/Max), Withdraw."
	)
	hint.add_theme_color_override(&"font_color", MUTED)
	hint.add_theme_font_size_override(&"font_size", 12)
	col.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	scroll.add_child(grid)

	if is_bag:
		_bag_grid = grid
		_bag_count = count
	else:
		_bank_grid = grid
		_bank_count = count
	return col


func _build_transfer_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)

	_selection_label = Label.new()
	_selection_label.text = "Select a stack"
	_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_label.add_theme_color_override(&"font_color", MUTED)
	row.add_child(_selection_label)

	var amount_label := Label.new()
	amount_label.text = "Amount"
	amount_label.add_theme_color_override(&"font_color", MUTED)
	row.add_child(amount_label)

	_amount_spin = SpinBox.new()
	_amount_spin.min_value = 1
	_amount_spin.max_value = 1
	_amount_spin.value = 1
	_amount_spin.rounded = true
	_amount_spin.custom_minimum_size = Vector2(96, 0)
	_amount_spin.editable = false
	row.add_child(_amount_spin)

	# "X" = custom amount: focus the spinner so the player can type a count.
	var x_btn := Button.new()
	x_btn.text = "X"
	x_btn.focus_mode = Control.FOCUS_NONE
	x_btn.tooltip_text = "Type a custom amount"
	x_btn.pressed.connect(func() -> void:
		if _selected_have <= 0:
			return
		_amount_spin.editable = true
		_amount_spin.get_line_edit().grab_focus()
		_amount_spin.get_line_edit().select_all())
	row.add_child(x_btn)

	var max_btn := Button.new()
	max_btn.text = "Max"
	max_btn.focus_mode = Control.FOCUS_NONE
	max_btn.tooltip_text = "Fill your bag with as many as will fit"
	max_btn.pressed.connect(_on_max_pressed)
	row.add_child(max_btn)

	_transfer_button = Button.new()
	_transfer_button.text = "Transfer"
	_transfer_button.focus_mode = Control.FOCUS_NONE
	_transfer_button.disabled = true
	_transfer_button.pressed.connect(_on_transfer_pressed)
	row.add_child(_transfer_button)
	return row


func _refresh() -> void:
	if InstanceClient.current == null or not visible:
		return
	var result: Array = await Client.request_data_await(
		&"bank.get",
		{},
		InstanceClient.current.name
	)
	if not is_instance_valid(self) or not visible:
		return
	if result.size() < 2 or result[1] != OK or not (result[0] is Dictionary):
		Toaster.toast("Could not open the bank.")
		return
	var payload: Dictionary = result[0]
	if not bool(payload.get("ok", false)):
		Toaster.toast("Could not open the bank.")
		return
	_inventory = payload.get("inventory", {}) as Dictionary
	_bank = payload.get("bank", {}) as Dictionary
	_clear_selection()
	_rebuild_grids()


func _rebuild_grids() -> void:
	_fill_grid(_bag_grid, _inventory, true)
	_fill_grid(_bank_grid, _bank, false)
	var bag_stacks: int = _count_stacks(_inventory)
	_bag_count.text = "%d stacks" % bag_stacks
	_bank_count.text = "%d stacks · no limit" % _count_stacks(_bank)
	if _deposit_all_button != null:
		_deposit_all_button.disabled = _busy or bag_stacks <= 0


func _count_stacks(store: Dictionary) -> int:
	var n: int = 0
	for uid: Variant in store:
		var data: Dictionary = store[uid]
		var item_id: int = int(data.get("id", 0))
		var amount: int = int(data.get("a", 0))
		if item_id <= 0 or amount <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item != null and item.is_currency:
			continue
		n += 1
	return n


func _fill_grid(grid: GridContainer, store: Dictionary, is_bag: bool) -> void:
	for child: Node in grid.get_children():
		child.queue_free()
	var live_uids: Array = []
	for uid: Variant in store.keys():
		var data: Dictionary = store[uid]
		var item_id: int = int(data.get("id", 0))
		var amount: int = int(data.get("a", 0))
		if item_id <= 0 or amount <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item != null and item.is_currency:
			continue
		live_uids.append(int(uid))
	var order: Array
	if is_bag:
		order = BagOrder.sync_with_entries(_bag_entries_for_order(live_uids))
	else:
		order = BankOrder.sync_with_uids(live_uids)
	live_uids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ia: int = BagOrder.index_of(order, int(a)) if is_bag else BankOrder.index_of(order, int(a))
		var ib: int = BagOrder.index_of(order, int(b)) if is_bag else BankOrder.index_of(order, int(b))
		return ia < ib)
	for uid: Variant in live_uids:
		var data: Dictionary = store[uid]
		var item_id: int = int(data.get("id", 0))
		var amount: int = int(data.get("a", 0))
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		var button := Button.new()
		button.custom_minimum_size = SLOT_SIZE
		button.clip_contents = true
		button.focus_mode = Control.FOCUS_NONE
		button.toggle_mode = true
		button.set_meta(&"bank_uid", int(uid))
		button.set_pressed_no_signal(int(uid) == _selected_uid and is_bag == _selected_from_bag)
		if item != null:
			PixelIcon.mount(button, item.item_icon)
			var tip: String = ItemTooltip.hover_text(item)
			if is_bag:
				tip += "\nLeft-click: deposit" if amount <= 1 else "\nLeft-click: choose amount (X/Max)"
			else:
				tip += "\nLeft-click: choose amount (X/Max)\nDrag: rearrange"
			button.tooltip_text = tip
		else:
			button.tooltip_text = "Unknown item"
		if amount > 1:
			var badge := Label.new()
			badge.text = "x%d" % amount
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.85))
			badge.add_theme_constant_override(&"outline_size", 4)
			badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			button.add_child(badge)
		button.pressed.connect(_on_stack_selected.bind(int(uid), is_bag, amount, item))
		_wire_slot_drag(button, int(uid), is_bag, item)
		grid.add_child(button)
	if grid.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Empty"
		empty.add_theme_color_override(&"font_color", MUTED)
		grid.add_child(empty)


func _bag_entries_for_order(uids: Array) -> Array:
	var entries: Array = []
	for uid: Variant in uids:
		entries.append({"uid": int(uid)})
	return entries


func _wire_slot_drag(button: Button, uid: int, is_bag: bool, item: Item) -> void:
	if item == null:
		return
	button.set_drag_forwarding(
		func(_at: Vector2) -> Variant:
			BagOrder.elevate_drag_preview(
				button,
				BagOrder.make_drag_preview(item.item_icon, Vector2(56, 56))
			)
			return {
				"bank_uid": uid,
				"from_bag": is_bag,
				"item_id": int(item.get_meta(&"id", 0)),
				"bag_uid": uid if is_bag else -1,
			},
		func(_at: Vector2, data: Variant) -> bool:
			if data is not Dictionary:
				return false
			var dict: Dictionary = data
			if not dict.has("bank_uid"):
				return false
			# Only rearrange within the same pane (bag↔bag or vault↔vault).
			return bool(dict.get("from_bag", false)) == is_bag,
		func(_at: Vector2, data: Variant) -> void:
			if data is not Dictionary:
				return
			var dict: Dictionary = data
			var from_uid: int = int(dict.get("bank_uid", -1))
			if from_uid < 0 or from_uid == uid:
				return
			if is_bag:
				BagOrder.move_before(BagOrder.load_order(), from_uid, uid)
			else:
				BankOrder.move_before(BankOrder.load_order(), from_uid, uid)
			_rebuild_grids()
	)


func _on_stack_selected(uid: int, from_bag: bool, have: int, item: Item) -> void:
	# Bag qty 1: instant deposit. Qty 2+ (and all vault clicks): select + amount UI.
	if from_bag and have <= 1:
		_transfer_stack(uid, true, have)
		return

	_selected_uid = uid
	_selected_from_bag = from_bag
	_selected_have = maxi(1, have)
	_selected_item_id = int(item.get_meta(&"id", 0)) if item != null else 0
	_selected_name = String(item.item_name) if item != null else "Item"
	_amount_spin.editable = true
	# Withdraw Max can span every bank pile of this item, so cap the spinner at
	# the vault total (still clamped to bag fit when Max is pressed).
	var spin_cap: int = _selected_have
	if not from_bag and _selected_item_id > 0:
		spin_cap = maxi(1, Inventory.count(_bank, _selected_item_id))
	_amount_spin.max_value = spin_cap
	_amount_spin.min_value = 1
	_amount_spin.value = _selected_have
	_transfer_button.disabled = false
	_transfer_button.text = "Deposit" if from_bag else "Withdraw"
	_selection_label.text = "%s  ·  %s" % [
		_selected_name,
		"from bag" if from_bag else "from vault",
	]
	_selection_label.add_theme_color_override(&"font_color", Color(1, 1, 1))
	_sync_selection_highlights()


func _sync_selection_highlights() -> void:
	for grid_pair: Array in [[_bag_grid, true], [_bank_grid, false]]:
		var grid: GridContainer = grid_pair[0]
		var is_bag: bool = grid_pair[1]
		if grid == null:
			continue
		for child: Node in grid.get_children():
			if child is not Button:
				continue
			var button: Button = child as Button
			# Selection identity is stashed on the button meta at fill time.
			var uid: int = int(button.get_meta(&"bank_uid", -1))
			var selected: bool = uid == _selected_uid and is_bag == _selected_from_bag
			button.set_pressed_no_signal(selected)


func _clear_selection() -> void:
	_selected_uid = -1
	_selected_have = 0
	_selected_item_id = 0
	_selected_name = ""
	_amount_spin.editable = false
	_amount_spin.max_value = 1
	_amount_spin.value = 1
	_transfer_button.disabled = true
	_transfer_button.text = "Transfer"
	_selection_label.text = "Select a stack"
	_selection_label.add_theme_color_override(&"font_color", MUTED)


func _on_max_pressed() -> void:
	if _selected_have <= 0 or _selected_item_id <= 0:
		return
	if _selected_from_bag:
		_amount_spin.value = _selected_have
		return
	# Withdraw: fill the bag with as many of this item as inventory space allows,
	# pulling across every bank pile of the same id.
	var banked: int = Inventory.count(_bank, _selected_item_id)
	var fit: int = Inventory.max_fit(_inventory, _selected_item_id)
	var amount: int = mini(banked, fit)
	_amount_spin.max_value = maxi(1, banked)
	_amount_spin.value = maxi(1, amount)


func _on_transfer_pressed() -> void:
	if _selected_uid < 0:
		return
	_transfer_stack(_selected_uid, _selected_from_bag, int(_amount_spin.value))


func _transfer_stack(uid: int, from_bag: bool, amount: int) -> void:
	if _busy or InstanceClient.current == null or uid < 0:
		return
	if amount <= 0:
		return
	_busy = true
	if _deposit_all_button != null:
		_deposit_all_button.disabled = true
	var type: StringName = &"bank.deposit" if from_bag else &"bank.withdraw"
	var result: Array = await Client.request_data_await(
		type,
		{"uid": uid, "amount": amount},
		InstanceClient.current.name
	)
	_busy = false
	if not is_instance_valid(self) or not visible:
		return
	if result.size() < 2 or result[1] != OK or not (result[0] is Dictionary):
		Toaster.toast("That transfer failed.")
		_rebuild_grids()
		return
	var payload: Dictionary = result[0]
	if not bool(payload.get("ok", false)):
		match str(payload.get("reason", "")):
			"currency":
				Toaster.toast("Gold stays in your currency pouch.")
			"inventory_full":
				Toaster.toast("Your bag is full. Deposit or drop something first.")
			_:
				Toaster.toast("That transfer failed.")
		_rebuild_grids()
		return
	_inventory = payload.get("inventory", {}) as Dictionary
	_bank = payload.get("bank", {}) as Dictionary
	_clear_selection()
	_rebuild_grids()
	ClientState.inventory_changed.emit({"quiet": true})


func _on_deposit_all_pressed() -> void:
	if _busy or InstanceClient.current == null:
		return
	if _count_stacks(_inventory) <= 0:
		Toaster.toast("Your bag has nothing to deposit.")
		return
	_busy = true
	if _deposit_all_button != null:
		_deposit_all_button.disabled = true
	var result: Array = await Client.request_data_await(
		&"bank.deposit_all",
		{},
		InstanceClient.current.name
	)
	_busy = false
	if not is_instance_valid(self) or not visible:
		return
	if result.size() < 2 or result[1] != OK or not (result[0] is Dictionary):
		Toaster.toast("Deposit All failed.")
		_rebuild_grids()
		return
	var payload: Dictionary = result[0]
	if not bool(payload.get("ok", false)):
		Toaster.toast("Deposit All failed.")
		_rebuild_grids()
		return
	_inventory = payload.get("inventory", {}) as Dictionary
	_bank = payload.get("bank", {}) as Dictionary
	var stacks: int = int(payload.get("stacks", 0))
	if stacks <= 0:
		Toaster.toast("Your bag has nothing to deposit.")
	else:
		Toaster.toast("Deposited %d stack%s into the vault." % [
			stacks,
			"" if stacks == 1 else "s",
		])
	_clear_selection()
	_rebuild_grids()
	ClientState.inventory_changed.emit({"quiet": true})
