extends MenuShell
## Personal bank vault. Left = bag, right = bank. Click a stack to move the
## whole stack across. No storage cap — the grid grows with contents.


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
	var root := HBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override(&"separation", 16)
	content.add_child(root)

	root.add_child(_build_side("Your bag", true))
	root.add_child(VSeparator.new())
	root.add_child(_build_side("Bank vault", false))


func _build_side(title: String, is_bag: bool) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)

	var header := HBoxContainer.new()
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

	var hint := Label.new()
	hint.text = "Click a stack to deposit." if is_bag else "Click a stack to withdraw."
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
	_rebuild_grids()


func _rebuild_grids() -> void:
	_fill_grid(_bag_grid, _inventory, true)
	_fill_grid(_bank_grid, _bank, false)
	_bag_count.text = "%d stacks" % _count_stacks(_inventory)
	_bank_count.text = "%d stacks · no limit" % _count_stacks(_bank)


func _count_stacks(store: Dictionary) -> int:
	var n: int = 0
	for uid: Variant in store:
		var data: Dictionary = store[uid]
		if int(data.get("id", 0)) > 0 and int(data.get("a", 0)) > 0:
			n += 1
	return n


func _fill_grid(grid: GridContainer, store: Dictionary, is_bag: bool) -> void:
	for child: Node in grid.get_children():
		child.queue_free()
	var uids: Array = store.keys()
	uids.sort()
	for uid: Variant in uids:
		var data: Dictionary = store[uid]
		var item_id: int = int(data.get("id", 0))
		var amount: int = int(data.get("a", 0))
		if item_id <= 0 or amount <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		var button := Button.new()
		button.custom_minimum_size = SLOT_SIZE
		button.clip_contents = true
		button.focus_mode = Control.FOCUS_NONE
		if item != null:
			PixelIcon.mount(button, item.item_icon)
			button.tooltip_text = ItemTooltip.hover_text(item)
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
		button.pressed.connect(_on_stack_pressed.bind(int(uid), is_bag))
		grid.add_child(button)
	if grid.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Empty"
		empty.add_theme_color_override(&"font_color", MUTED)
		grid.add_child(empty)


func _on_stack_pressed(uid: int, from_bag: bool) -> void:
	if _busy or InstanceClient.current == null:
		return
	_busy = true
	var type: StringName = &"bank.deposit" if from_bag else &"bank.withdraw"
	var result: Array = await Client.request_data_await(
		type,
		{"uid": uid},
		InstanceClient.current.name
	)
	_busy = false
	if not is_instance_valid(self) or not visible:
		return
	if result.size() < 2 or result[1] != OK or not (result[0] is Dictionary):
		Toaster.toast("That transfer failed.")
		return
	var payload: Dictionary = result[0]
	if not bool(payload.get("ok", false)):
		Toaster.toast("That transfer failed.")
		return
	_inventory = payload.get("inventory", {}) as Dictionary
	_bank = payload.get("bank", {}) as Dictionary
	_rebuild_grids()
	ClientState.inventory_changed.emit({"quiet": true})
