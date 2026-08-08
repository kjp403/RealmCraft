extends PanelContainer

const PANEL_SIZE := Vector2(180.0, 262.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 52.0

const GRID_COLUMNS := 4
const GRID_ROWS := 5
## Minimum visible squares; grows with bag contents so /give / loot past 20 still show.
const MIN_SLOT_COUNT := GRID_COLUMNS * GRID_ROWS
const SLOT_SIZE := Vector2(36.0, 36.0)

const ACTION_PRIMARY := 0
const ACTION_DROP := 1

@onready var header: HBoxContainer = $MarginContainer/MainColumn/Header
@onready var close_button: Button = $MarginContainer/MainColumn/Header/CloseButton
@onready var content_margin: MarginContainer = $MarginContainer/MainColumn/Content
@onready var inventory_grid: GridContainer = $MarginContainer/MainColumn/Content/InventoryScroll/InventoryGrid

var gold_label: Label
var context_menu: PopupMenu
var context_entry: Dictionary = {}
var primary_action_in_progress: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE

	inventory_grid.columns = GRID_COLUMNS
	inventory_grid.add_theme_constant_override(&"h_separation", 4)
	inventory_grid.add_theme_constant_override(&"v_separation", 4)

	content_margin.add_theme_constant_override(&"margin_left", 10)

	_build_currency_pouch()
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
	gold_icon.custom_minimum_size = Vector2(14.0, 14.0)
	gold_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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


func _build_context_menu() -> void:
	context_menu = PopupMenu.new()
	context_menu.id_pressed.connect(_on_context_action)
	add_child(context_menu)


func _build_empty_grid(slot_count: int = MIN_SLOT_COUNT) -> void:
	for child: Node in inventory_grid.get_children():
		inventory_grid.remove_child(child)
		child.queue_free()

	var count: int = maxi(MIN_SLOT_COUNT, slot_count)
	if count % GRID_COLUMNS != 0:
		count += GRID_COLUMNS - (count % GRID_COLUMNS)

	for _index: int in range(count):
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
		slot.add_theme_constant_override(&"icon_max_width", 24)

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

	for slot_uid: Variant in inventory:
		var data: Dictionary = inventory[slot_uid]
		var item: Item = ContentRegistryHub.load_by_id(
			&"items",
			int(data.get("id", 0))
		) as Item

		# Currency is displayed in the pouch instead of consuming a slot.
		if item == null or item.is_currency:
			continue

		entries.append({
			"uid": int(slot_uid),
			"data": data,
			"item": item,
		})

	var order: Array = BagOrder.sync_with_entries(entries)
	_build_empty_grid(maxi(order.size() + GRID_COLUMNS, MIN_SLOT_COUNT))
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
	return {"bag_uid": int(entry["uid"])}


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

	if (
		mouse_event.button_index == MOUSE_BUTTON_LEFT
		and mouse_event.double_click
	):
		# Materials / non-holdables have no primary action — ignore double-click
		# so players don't get a misleading "could not be used" toast.
		var item: Item = entry["item"]
		if (
			item is ConsumableItem
			or item is GearItem
			or item.holdable
		):
			slot.accept_event()
			_perform_primary_action(entry)


func _open_context_menu(entry: Dictionary) -> void:
	context_entry = entry
	context_menu.clear()

	var item: Item = entry["item"]

	if item is ConsumableItem:
		context_menu.add_item("Use", ACTION_PRIMARY)
	elif item is GearItem:
		context_menu.add_item("Equip", ACTION_PRIMARY)
	elif item.holdable:
		context_menu.add_item("Hold", ACTION_PRIMARY)

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


func _perform_primary_action(entry: Dictionary) -> void:
	if primary_action_in_progress or InstanceClient.current == null:
		return

	var item: Item = entry["item"]
	var item_id: int = int(item.get_meta(&"id", 0))

	if item_id <= 0:
		return

	# Materials and other non-holdables are Drop-only — never send item.equip.
	if not (item is ConsumableItem or item is GearItem or item.holdable):
		return

	var request_name: StringName = &"item.equip"

	if item is ConsumableItem:
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

	if not bool(payload.get("ok", false)):
		Toaster.toast("The item could not be used.")
		return

	if item is ConsumableItem:
		Toaster.toast("Potion consumed.")

	_refresh_inventory()


func _mastery_equip_toast(payload: Dictionary) -> String:
	var level: int = int(payload.get("level", 0))
	var cats: PackedStringArray = PackedStringArray()
	for entry: Variant in payload.get("categories", []):
		cats.append(str(entry).capitalize())
	if cats.is_empty() or (cats.size() == 1 and cats[0].to_lower() == "any"):
		return "Requires any mastery level %d." % level
	return "Requires %s mastery %d." % [" / ".join(cats), level]
