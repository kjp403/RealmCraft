extends PanelContainer

const PANEL_SIZE := Vector2(180.0, 300.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 48.0

const GRID_COLUMNS := 5
const GRID_ROWS := 6
## 5×6 = 30 cells for a 28-slot bag ([constant Inventory.MAX_SLOTS]): the whole
## bag fits the panel at once, so the dock never needs a scrollbar. The last two
## cells stay empty. Slots are sized so five columns fit the 180px panel.
## Cells drawn (30) vs. slots a bag can actually hold (28) — the last two cells
## are always empty filler that keeps the final row square.
const CELL_COUNT := GRID_COLUMNS * GRID_ROWS
const MIN_SLOT_COUNT := CELL_COUNT
const MAX_SLOT_COUNT := Inventory.MAX_SLOTS
const SLOT_SIZE := Vector2(28.0, 28.0)

## Display-only price labels for buyable bags, keyed by BAG NUMBER (not index).
## The authoritative costs live in inventory.upgrade_bag.gd on the server.
const BAG_PRICE_LABELS: Dictionary = {
	2: "500K",
	3: "1.25M",
}

const ACTION_PRIMARY := 0
const ACTION_DROP := 1
const ACTION_HOTKEY := 2
const ACTION_SALVAGE := 3

@onready var header: HBoxContainer = $MarginContainer/MainColumn/Header
@onready var close_button: Button = $MarginContainer/MainColumn/Header/CloseButton
@onready var content_margin: MarginContainer = $MarginContainer/MainColumn/Content
@onready var inventory_grid: GridContainer = $MarginContainer/MainColumn/Content/InventoryScroll/InventoryGrid

var gold_label: Label
## Current active inventory bag (0-2) and unlocked count (1-3), mirrored from
## the server by inventory.bags. The grid below shows ONE bag at a time.
var active_bag: int = 0
var bag_count: int = 1
var bag_tab_buttons: Array[Button] = []
## A tab is a cheap click target and a bag costs up to 1.25M gold, so buying
## takes two clicks: the first arms, the second spends. Mirrors inventory_menu.
var pending_bag_purchase: int = -1
var context_menu: PopupMenu
var context_entry: Dictionary = {}
var primary_action_in_progress: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

	inventory_grid.columns = GRID_COLUMNS
	inventory_grid.add_theme_constant_override(&"h_separation", 3)
	inventory_grid.add_theme_constant_override(&"v_separation", 3)

	content_margin.add_theme_constant_override(&"margin_left", 10)

	_build_currency_pouch()
	_build_bag_tabs()
	_build_context_menu()
	_build_empty_grid()

	close_button.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)
	ClientState.local_player_ready.connect(_on_local_player_ready)
	# Mining / gathering awards go to the server bag; refresh while the dock is open
	# so ore counts climb without close→reopen (fullscreen inventory already does this).
	ClientState.gather_succeeded.connect(_on_gather_succeeded)
	ClientState.inventory_changed.connect(_on_inventory_changed)

	var hud := get_parent() as Control
	if hud != null:
		hud.resized.connect(_place_panel)

	call_deferred(&"_place_panel")
	_connect_equipment_signal()
	hide()


func _place_panel() -> void:
	var hud := get_parent() as Control
	if hud == null:
		return

	size = PANEL_SIZE
	position = Vector2(
		hud.size.x - PANEL_SIZE.x - RIGHT_MARGIN,
		hud.size.y - PANEL_SIZE.y - BOTTOM_CLEARANCE
	)


func _build_currency_pouch() -> void:
	var pouch := HBoxContainer.new()
	pouch.tooltip_text = "Currency pouch"
	pouch.add_theme_constant_override(&"separation", 2)

	var gold_item: Item = ContentRegistryHub.load_by_id(
		&"items",
		Economy.gold_id()
	) as Item

	var gold_icon := TextureRect.new()
	gold_icon.custom_minimum_size = Vector2(16.0, 16.0)
	gold_icon.custom_maximum_size = Vector2(16.0, 16.0)
	gold_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	gold_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if gold_item != null:
		gold_icon.texture = gold_item.item_icon

	gold_label = Label.new()
	gold_label.text = "0"
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_label.add_theme_font_size_override(&"font_size", 11)
	gold_label.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.85, 0.45)
	)
	gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	pouch.add_child(gold_icon)
	pouch.add_child(gold_label)

	header.add_child(pouch)

	# Move the pouch immediately before the X button.
	header.move_child(pouch, close_button.get_index())


## Bag 1/2/3 selector directly under the header, above the grid. The grid, the
## slots and every action below it are untouched — the tabs only change WHICH
## bag those 28 squares are showing.
func _build_bag_tabs() -> void:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 2)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for index: int in range(Inventory.MAX_BAGS):
		var tab := Button.new()
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(0.0, 20.0)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override(&"font_size", 11)
		tab.pressed.connect(_on_bag_tab.bind(index))
		tabs.add_child(tab)
		bag_tab_buttons.append(tab)

	var column: VBoxContainer = content_margin.get_parent() as VBoxContainer
	column.add_child(tabs)
	column.move_child(tabs, content_margin.get_index())
	_update_bag_tabs()


func _update_bag_tabs() -> void:
	for index: int in bag_tab_buttons.size():
		var tab: Button = bag_tab_buttons[index]
		tab.set_pressed_no_signal(index == active_bag)
		if index < bag_count:
			tab.disabled = false
			tab.text = str(index + 1)
			tab.tooltip_text = "Bag %d" % (index + 1)
			continue
		# Locked. Only the NEXT bag is buyable — bag 3 cannot be bought before
		# bag 2, and the server refuses a mismatch (reason "wrong_bag").
		var price: String = BAG_PRICE_LABELS.get(index + 1, "?")
		var buyable: bool = index == bag_count
		tab.disabled = not buyable
		if not buyable:
			tab.text = str(index + 1)
			tab.tooltip_text = "Unlock Bag %d first." % index
			continue
		if pending_bag_purchase == index:
			tab.text = "Buy?"
			tab.tooltip_text = "Click again to spend %s gold." % price
		else:
			tab.text = "%d +" % (index + 1)
			tab.tooltip_text = "Buy Bag %d for %s gold." % [index + 1, price]


func _on_bag_tab(index: int) -> void:
	if InstanceClient.current == null:
		return

	if index < bag_count:
		pending_bag_purchase = -1
		active_bag = index
		Client.request_data(
			&"inventory.set_active_bag",
			Callable(),
			{"bag": index},
			InstanceClient.current.name
		)
		_update_bag_tabs()
		_refresh_inventory()
		return

	# Locked tab. Only the next bag is for sale.
	if index != bag_count:
		Toaster.toast("Unlock Bag %d first." % index)
		_update_bag_tabs()
		return

	if pending_bag_purchase != index:
		pending_bag_purchase = index
		_update_bag_tabs()
		Toaster.toast("Tap again to buy Bag %d for %s gold." % [
			index + 1, BAG_PRICE_LABELS.get(index + 1, "?")
		])
		return

	pending_bag_purchase = -1
	# Send which bag we believe we are buying; the server refuses a mismatch so
	# the label and the charge can never disagree.
	var result: Array = await Client.request_data_await(
		&"inventory.upgrade_bag",
		{"bag": index + 1},
		InstanceClient.current.name
	)
	var payload: Dictionary = result[0] if result[0] is Dictionary else {}
	if result[1] == OK and bool(payload.get("ok", false)):
		Toaster.toast("Bag %d unlocked!" % int(payload.get("bags", index + 1)))
		_refresh_inventory()
		return
	match str(payload.get("reason", "")):
		"cant_afford":
			Toaster.toast("You need %s gold." % BAG_PRICE_LABELS.get(index + 1, "more"))
		"max_bags":
			Toaster.toast("You already own every bag.")
		_:
			Toaster.toast("Could not buy Bag %d." % (index + 1))
	_update_bag_tabs()


func _build_context_menu() -> void:
	context_menu = PopupMenu.new()
	context_menu.id_pressed.connect(_on_context_action)
	add_child(context_menu)


func _build_empty_grid(slot_count: int = MIN_SLOT_COUNT) -> void:
	for child: Node in inventory_grid.get_children():
		inventory_grid.remove_child(child)
		child.queue_free()

	# Always the full 5x6 block: a partial last row would leave a gap where the
	# scrollbar used to be, and the bag never exceeds CELL_COUNT anyway.
	var count: int = clampi(slot_count, 0, CELL_COUNT)
	if count % GRID_COLUMNS != 0:
		count = mini(CELL_COUNT, count + (GRID_COLUMNS - (count % GRID_COLUMNS)))

	for index: int in range(count):
		var slot := Button.new()

		# Both minimum and maximum are fixed so item textures cannot resize rows.
		slot.custom_minimum_size = SLOT_SIZE
		slot.custom_maximum_size = SLOT_SIZE
		slot.clip_contents = true
		slot.expand_icon = true
		slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.focus_mode = Control.FOCUS_NONE
		# STOP so empty squares can accept bag-drag drops.
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.add_theme_constant_override(&"icon_max_width", 20)

		# 5x6 draws 30 squares but a bag holds MAX_SLOTS (28). The last two are
		# structural filler that keeps the final row square — players read two
		# identical-looking squares that never accept an item as broken slots,
		# so they are dimmed, disabled and inert instead.
		if index >= MAX_SLOT_COUNT:
			slot.disabled = true
			slot.modulate = Color(1.0, 1.0, 1.0, 0.25)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.tooltip_text = "Not a bag slot — a bag holds %d." % MAX_SLOT_COUNT

		inventory_grid.add_child(slot)


func _on_visibility_changed() -> void:
	if visible:
		_connect_equipment_signal()
		_refresh_inventory()


func _on_gather_succeeded(_result: Dictionary) -> void:
	if visible:
		_refresh_inventory()


func _on_inventory_changed(_result: Dictionary) -> void:
	if visible:
		_refresh_inventory()


func _on_local_player_ready(_local_player: LocalPlayer) -> void:
	_connect_equipment_signal()

	if visible:
		_refresh_inventory()


func _connect_equipment_signal() -> void:
	var local_player: Player = ClientState.local_player
	if local_player == null:
		return

	var changed_signal: Signal = (
		local_player.equipment_component.equipment_changed
	)
	if not changed_signal.is_connected(_on_equipment_changed):
		changed_signal.connect(_on_equipment_changed)


func _on_equipment_changed(
	_slot_key: StringName,
	_item_id: int
) -> void:
	# Weapon equip completes after its draw delay, not when item.equip replies.
	if visible:
		_refresh_inventory()


func _refresh_inventory() -> void:
	if InstanceClient.current == null:
		return

	var result: Array = await Client.request_data_await(
		&"inventory.get",
		{},
		InstanceClient.current.name
	)

	if result.size() < 2 or result[1] != OK:
		return

	var inventory: Dictionary = result[0]
	var entries: Array[Dictionary] = []

	gold_label.text = str(
		Inventory.count(inventory, Economy.gold_id())
	)

	var bag_result: Array = await Client.request_data_await(
		&"inventory.bags",
		{},
		InstanceClient.current.name
	)
	if bag_result.size() >= 2 and bag_result[1] == OK:
		var bag_data: Dictionary = bag_result[0] if bag_result[0] is Dictionary else {}
		bag_count = clampi(int(bag_data.get("bags", 1)), 1, Inventory.MAX_BAGS)
		active_bag = clampi(int(bag_data.get("active_bag", 0)), 0, bag_count - 1)
	_update_bag_tabs()

	for slot_uid: Variant in inventory:
		var data: Dictionary = inventory[slot_uid]
		var item: Item = ContentRegistryHub.load_by_id(
			&"items",
			int(data.get("id", 0))
		) as Item

		# Currency is displayed in the pouch instead of consuming a slot.
		if item == null or item.is_currency:
			continue

		# One bag at a time: the grid only ever holds the active bag's slots.
		if int(data.get("bag", 0)) != active_bag:
			continue

		entries.append({
			"uid": int(slot_uid),
			"data": data,
			"item": item,
		})

	var order: Array = BagOrder.sync_with_entries(entries)
	_build_empty_grid(MAX_SLOT_COUNT)
	_display_entries(entries, order)


func _display_entries(entries: Array[Dictionary], order: Array) -> void:
	var by_uid: Dictionary = {}
	for entry: Dictionary in entries:
		by_uid[int(entry["uid"])] = entry

	var slots: Array[Node] = inventory_grid.get_children()
	for index: int in range(slots.size()):
		var slot := slots[index] as Button

		slot.icon = null
		slot.tooltip_text = ""
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.focus_mode = Control.FOCUS_NONE
		for child: Node in slot.get_children():
			slot.remove_child(child)
			child.queue_free()

		# Every square accepts drops so items can land on empty cells.
		slot.remove_meta(&"item_id")
		slot.set_drag_forwarding(
			_bag_get_drag_data_empty,
			_bag_can_drop_data,
			_bag_drop_data.bind(index),
		)

		var uid: int = BagOrder.EMPTY
		if index < order.size():
			uid = int(order[index])
		if uid == BagOrder.EMPTY or not by_uid.has(uid):
			continue

		var entry: Dictionary = by_uid[uid]
		var data: Dictionary = entry["data"]
		var item: Item = entry["item"]

		slot.icon = item.item_icon
		slot.tooltip_text = ItemTooltip.hover_text(item)
		slot.set_meta(&"item_id", int(item.get_meta(&"id", 0)))

		slot.gui_input.connect(
			_on_slot_gui_input.bind(entry, slot),
		)
		slot.set_drag_forwarding(
			_bag_get_drag_data.bind(entry, slot),
			_bag_can_drop_data,
			_bag_drop_data.bind(index),
		)

		var amount: int = int(data.get("a", 1))
		if amount > 1:
			var quantity := Label.new()
			quantity.text = str(amount)
			quantity.mouse_filter = Control.MOUSE_FILTER_IGNORE
			quantity.add_theme_font_size_override(&"font_size", 10)
			quantity.add_theme_color_override(&"font_color", Color.WHITE)
			quantity.add_theme_color_override(
				&"font_outline_color",
				Color(0.0, 0.0, 0.0, 0.9)
			)
			quantity.add_theme_constant_override(&"outline_size", 3)

			# Add it first, then anchor it relative to its actual slot.
			slot.add_child(quantity)
			quantity.set_anchors_and_offsets_preset(
				Control.PRESET_BOTTOM_RIGHT
			)
			quantity.offset_left -= 2
			quantity.offset_right -= 2
			quantity.offset_top -= 2
			quantity.offset_bottom -= 2


func _bag_get_drag_data_empty(_at_position: Vector2) -> Variant:
	return null


func _bag_get_drag_data(
	_at_position: Vector2,
	entry: Dictionary,
	slot: Control
) -> Variant:
	BagOrder.elevate_drag_preview(
		slot,
		BagOrder.make_drag_preview((entry["item"] as Item).item_icon, Vector2(48, 48))
	)
	return {
		"bag_uid": int(entry["uid"]),
		"item_id": int((entry["item"] as Item).get_meta(&"id", 0)),
	}


func _bag_can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("bag_uid")


func _bag_drop_data(_at_position: Vector2, data: Variant, to_index: int) -> void:
	if data is not Dictionary:
		return
	var from_uid: int = int((data as Dictionary).get("bag_uid", -1))
	if from_uid < 0 or to_index < 0:
		return
	var order: Array = BagOrder.load_order()
	if BagOrder.index_of(order, from_uid) == to_index:
		return
	var dest_uid: int = BagOrder.EMPTY
	if to_index < order.size():
		dest_uid = int(order[to_index])
	if dest_uid >= 0 and dest_uid != from_uid:
		var from_id: int = int((data as Dictionary).get("item_id", 0))
		var dest_id: int = 0
		var slots: Array[Node] = inventory_grid.get_children()
		if to_index < slots.size():
			dest_id = int(slots[to_index].get_meta(&"item_id", 0))
		if from_id > 0 and from_id == dest_id:
			var moved: int = await StackMerge.try_merge(from_uid, dest_uid, false)
			if moved > 0:
				_refresh_inventory()
				return
		BagOrder.swap(order, from_uid, dest_uid)
	else:
		BagOrder.move_to_index(order, from_uid, to_index)
	_refresh_inventory()


func _on_slot_gui_input(
	event: InputEvent,
	entry: Dictionary,
	slot: Button
) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton

	if not mouse_event.pressed:
		return

	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		slot.accept_event()
		_open_context_menu(entry)
		return

	# Shift+Left: instant armor swap (helmet/torso/boots/ring/relic) — boss-fight
	# fluent gear changes without opening the context menu or double-clicking.
	# Weapons stay on double-click / Equip (they still need the draw cast).
	if (
		mouse_event.button_index == MOUSE_BUTTON_LEFT
		and mouse_event.shift_pressed
		and _is_armor_gear(entry["item"] as Item)
	):
		slot.accept_event()
		_perform_primary_action(entry)
		return

	if (
		mouse_event.button_index == MOUSE_BUTTON_LEFT
		and mouse_event.double_click
	):
		# Materials / non-holdables have no primary action — ignore double-click
		# so players don't get a misleading "could not be used" toast.
		var item: Item = entry["item"]
		if (
			item is ConsumableItem
			or item is LootChestItem
			or item is DungeonKeyItem
			or item is GearItem
			or item.holdable
		):
			slot.accept_event()
			_perform_primary_action(entry)


func _open_context_menu(entry: Dictionary) -> void:
	context_entry = entry
	context_menu.clear()

	var item: Item = entry["item"]

	if item is LootChestItem:
		context_menu.add_item("Open", ACTION_PRIMARY)
	elif item is ConsumableItem or item is DungeonKeyItem:
		context_menu.add_item("Use", ACTION_PRIMARY)
	elif item is GearItem:
		context_menu.add_item("Equip", ACTION_PRIMARY)
	elif item.holdable:
		context_menu.add_item("Hold", ACTION_PRIMARY)

	if (
		item is ConsumableItem
		or item is LootChestItem
		or item is DungeonKeyItem
		or item is GearItem
		or item.holdable
	):
		context_menu.add_item("Bind to 1-2-3", ACTION_HOTKEY)

	# Break down is the only route to salvage from the dock. Items the salvage
	# table does not know still get the row, disabled, so players stop hunting
	# for a feature that simply does not apply to that item.
	var salvage_table: SalvageTable = SalvageTable.shared()
	var item_id: int = int((entry.get("data", {}) as Dictionary).get("id", 0))
	var recipe: SalvageRecipe = (
		salvage_table.recipe_for(item_id)
		if salvage_table != null
		else null
	)
	if item is GearItem or item.holdable:
		# Show the level gate ON the row. Letting it through to the confirm
		# dialog meant agreeing to destroy the item and THEN being refused.
		var salvage_level: int = int(
			ClientState.skill_levels.get(String(salvage_table.profession), 1)
		) if salvage_table != null else 1
		var under_level: bool = recipe != null and salvage_level < recipe.required_level
		var label: String = "Break down"
		if under_level:
			label = "Break down (%s %d)" % [
				JobRegistry.display_name(salvage_table.profession), recipe.required_level
			]
		context_menu.add_item(label, ACTION_SALVAGE)
		if recipe == null or under_level:
			context_menu.set_item_disabled(context_menu.item_count - 1, true)
			context_menu.set_item_tooltip(
				context_menu.item_count - 1,
				"This can't be broken down." if recipe == null
				else "Requires %s %d." % [
					JobRegistry.display_name(salvage_table.profession),
					recipe.required_level,
				]
			)

	if item.can_drop():
		context_menu.add_item("Drop", ACTION_DROP)

	if context_menu.item_count == 0:
		return

	context_menu.position = Vector2i(
		get_viewport().get_mouse_position()
	)
	context_menu.popup()


func _on_context_action(action_id: int) -> void:
	if context_entry.is_empty():
		return
	if action_id == ACTION_PRIMARY:
		_perform_primary_action(context_entry)
	elif action_id == ACTION_DROP:
		_perform_drop(context_entry)
	elif action_id == ACTION_HOTKEY:
		_assign_hotkey(context_entry)
	elif action_id == ACTION_SALVAGE:
		_perform_salvage(context_entry)


## Break down one copy for materials. Confirmed first: salvage DESTROYS the
## item, and the dock sits under the player's thumb during combat.
func _perform_salvage(entry: Dictionary) -> void:
	if InstanceClient.current == null:
		return
	var item: Item = entry.get("item", null) as Item
	if item == null:
		return
	var salvage_table: SalvageTable = SalvageTable.shared()
	var item_id: int = int((entry.get("data", {}) as Dictionary).get("id", 0))
	var recipe: SalvageRecipe = (
		salvage_table.recipe_for(item_id) if salvage_table != null else null
	)
	if recipe == null:
		Toaster.toast("%s can't be broken down." % item.item_name)
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = "Break Down"
	dialog.ok_button_text = "Break Down"
	dialog.cancel_button_text = "Cancel"
	dialog.dialog_text = "Break down 1 %s into %s?
The %s is destroyed." % [
		item.item_name, _salvage_yield_text(recipe), item.item_name
	]
	dialog.confirmed.connect(_confirm_salvage.bind(int(entry.get("uid", -1))))
	dialog.visibility_changed.connect(
		func() -> void:
			if not dialog.visible:
				dialog.queue_free()
	)
	add_child(dialog)
	dialog.popup_centered()


func _confirm_salvage(slot_uid: int) -> void:
	if slot_uid < 0 or InstanceClient.current == null:
		return
	var result: Array = await Client.request_data_await(
		&"item.salvage",
		{"uid": slot_uid, "amount": 1},
		InstanceClient.current.name
	)
	var payload: Dictionary = result[0] if result[0] is Dictionary else {}
	if result.size() < 2 or result[1] != OK or not bool(payload.get("ok", true)):
		# Reasons are wire keys, not copy. Toasting them raw put "salvage_level"
		# on screen with no hint about which skill or what level.
		match str(payload.get("reason", "")):
			"salvage_level":
				Toaster.toast("Requires %s %d to break this down." % [
					JobRegistry.display_name(StringName(str(payload.get("profession", "")))),
					int(payload.get("required_level", 0)),
				])
			"inventory_full":
				Toaster.toast("Not enough bag space for the materials.")
			"cant_salvage":
				Toaster.toast("That can't be broken down.")
			"missing":
				Toaster.toast("You no longer have that item.")
			_:
				Toaster.toast("Could not break that down.")
		return
	Toaster.toast("Broke it down into %s." % _granted_text(payload.get("granted", [])))
	_refresh_inventory()


## "1-3x Iron Bar" — the authored yield, for the confirm prompt. Ranges stay
## ranges: the roll happens server-side, so this cannot promise a number.
func _salvage_yield_text(recipe: SalvageRecipe) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for output: SalvageOutput in recipe.outputs:
		if output == null or output.item == null:
			continue
		parts.append(output.describe())
	return ", ".join(parts) if not parts.is_empty() else "materials"


func _granted_text(granted: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry: Variant in granted:
		if entry is not Dictionary:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(entry.get("id", 0))) as Item
		if item == null:
			continue
		parts.append("%dx %s" % [int(entry.get("amount", 0)), item.item_name])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _assign_hotkey(entry: Dictionary) -> void:
	var item: Item = entry.get("item", null) as Item
	if item == null:
		return
	var entries: PackedStringArray = PackedStringArray()
	for i: int in 3:
		var occupant: Item = ClientState.quick_slots.get_key(i) as Item
		var occupant_name: String = String(occupant.item_name) if occupant != null else "empty"
		entries.append("Slot %d (key %d)  —  %s" % [i + 1, i + 1, occupant_name])
	SlotPickerOverlay.open(self, "Place %s on which quick slot?" % item.item_name, entries,
		func(slot: int) -> void:
			var occupant: Item = ClientState.quick_slots.get_key(slot) as Item
			if occupant == item:
				ClientState.quick_slots.set_key(slot, null)
				return
			for i: int in 3:
				if (ClientState.quick_slots.get_key(i) as Item) == item:
					ClientState.quick_slots.set_key(i, null)
			ClientState.quick_slots.set_key(slot, item)
			Toaster.toast("Bound %s to key %d." % [item.item_name, slot + 1])
	)


func _perform_drop(entry: Dictionary) -> void:
	if primary_action_in_progress or InstanceClient.current == null:
		return

	var item: Item = entry["item"]
	if not item.can_drop():
		Toaster.toast("That item cannot be dropped.")
		return

	var slot_uid: int = int(entry.get("uid", -1))
	if slot_uid < 0:
		return

	primary_action_in_progress = true
	var result: Array = await Client.request_data_await(
		&"item.drop",
		{"uid": slot_uid},
		InstanceClient.current.name
	)
	primary_action_in_progress = false

	if result.size() < 2 or result[1] != OK:
		Toaster.toast("Could not drop that item.")
		return

	var payload: Dictionary = (
		result[0] if result[0] is Dictionary else {}
	)
	match str(payload.get("reason", "")):
		"dead":
			Toaster.toast("You cannot drop items while dead.")
			return
		"missing":
			Toaster.toast("That item is no longer in your inventory.")
			_refresh_inventory()
			return
		"cant_drop":
			Toaster.toast("That item cannot be dropped.")
			return
		"no_map", "spawn_failed":
			Toaster.toast("Could not drop that item here.")
			return

	if not bool(payload.get("ok", false)):
		Toaster.toast("Could not drop that item.")
		return

	Toaster.toast("Dropped %s." % str(payload.get("name", item.item_name)))
	_refresh_inventory()


## True for bag armor / jewelry (not weapons). Used by Shift+click equip.
func _is_armor_gear(item: Item) -> bool:
	if item == null or not (item is GearItem):
		return false
	var gear: GearItem = item as GearItem
	return gear.slot != null and gear.slot.key != &"weapon"


func _perform_primary_action(entry: Dictionary) -> void:
	if primary_action_in_progress or InstanceClient.current == null:
		return

	var item: Item = entry["item"]
	var item_id: int = int(item.get_meta(&"id", 0))

	if item_id <= 0:
		return

	# Materials and other non-holdables are Drop-only — never send item.equip.
	if not (
		item is ConsumableItem
		or item is LootChestItem
		or item is DungeonKeyItem
		or item is GearItem
		or item.holdable
	):
		return

	var request_name: StringName = &"item.equip"

	if item is LootChestItem:
		request_name = &"chest.open_item"
	elif item is DungeonKeyItem:
		request_name = &"dungeon.key_use"
	elif item is ConsumableItem:
		request_name = &"item.consume"

	primary_action_in_progress = true
	var result: Array = await Client.request_data_await(
		request_name,
		{"id": item_id},
		InstanceClient.current.name
	)
	primary_action_in_progress = false

	if result.size() < 2 or result[1] != OK:
		Toaster.toast("The item could not be used.")
		return

	var payload: Dictionary = (
		result[0] if result[0] is Dictionary else {}
	)

	match str(payload.get("reason", "")):
		"dead":
			Toaster.toast("You cannot use items while dead.")
			return
		"missing":
			Toaster.toast("That item is no longer in your inventory.")
			_refresh_inventory()
			return
		"not_consumable":
			Toaster.toast("That item cannot be consumed.")
			return
		"no_effect":
			Toaster.toast("You do not currently need that potion.")
			return
		"cooldown":
			Toaster.toast("That potion is still on cooldown.")
			return
		"in_combat":
			Toaster.toast("You cannot do that while in combat.")
			return
		"level":
			Toaster.toast(
				"Requires level %d." % int(payload.get("level", 0))
			)
			return
		"mastery":
			Toaster.toast(_mastery_equip_toast(payload))
			return
		"gear_level":
			Toaster.toast(
				"Restricted to level %d gear." % int(
					payload.get("level", 0)
				)
			)
			return
		"cant_equip":
			Toaster.toast("You cannot equip that item.")
			return
		"inventory_full":
			Toaster.toast("Your bag is full. Bank some items first.")
			return

	if not bool(payload.get("ok", false)):
		Toaster.toast("The item could not be used.")
		return

	if item is ConsumableItem:
		ConsumableItem.stamp_client_cooldown(item as ConsumableItem)
		Toaster.toast("Potion consumed.")
	# LootChestItem loot toast rides the chest.opened push.

	_refresh_inventory()


func _mastery_equip_toast(payload: Dictionary) -> String:
	var level: int = int(payload.get("level", 0))
	var cats: PackedStringArray = PackedStringArray()
	for entry: Variant in payload.get("categories", []):
		cats.append(str(entry).capitalize())
	if cats.is_empty() or (cats.size() == 1 and cats[0].to_lower() == "any"):
		return "Requires any mastery level %d." % level
	return "Requires %s mastery %d." % [" / ".join(cats), level]
