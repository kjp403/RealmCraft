extends MenuShell
## Inventory menu, BotW-style: top category rail (LB/RB cycle on pad), a
## sorted + grouped bag grid with equipped gear rendered as badged tiles at
## the head of their section (the Gear tab IS the paperdoll), a full-height
## detail column with stat compare, and a bottom input-hint bar. See
## docs/inventory.md.

## Rail-only pseudo filter: every favorited ("p"-flagged) bag item, any
## category, grouped by its normal sections.
const TAB_FAVORITES: int = -2
## Rail tabs in order: [label, filter]. Text-first — icons can slot in with an
## owner art pass later. No "All": weapons/armor are deliberately separate
## (equip-and-act vs silent stat buffers); Favorites / Others / Quest only
## appear while matching items are held.
const RAIL_TABS: Array[Array] = [
	["Favorites", TAB_FAVORITES],
	["Weapons", Item.InventoryTab.WEAPON],
	["Armor", Item.InventoryTab.ARMOR],
	["Consumables", Item.InventoryTab.CONSUMABLE],
	["Materials", Item.InventoryTab.MATERIAL],
	["Others", Item.InventoryTab.OTHER],
	["Quest", Item.InventoryTab.QUEST],
]
## Tabs hidden while no matching item is held.
const DYNAMIC_TABS: Array[int] = [TAB_FAVORITES, Item.InventoryTab.OTHER, Item.InventoryTab.QUEST]
## Bag sections in render order: [group key (Item.group_key()), label].
## Weapon mastery categories get their own sections, armor groups by SET —
## a group key NOT listed here still renders (appended alphabetically,
## capitalized label), so new categories / armor sets never vanish.
const GROUPS: Array[Array] = [
	[&"sword", "Swords"],
	[&"hammer", "Hammers"],
	[&"bow", "Bows"],
	[&"wand", "Wands"],
	[&"book", "Books"],
	[&"weapons", "Weapons"],
	[&"tools", "Tools"],
	[&"rings", "Rings"],
	[&"relics", "Relics"],
	[&"armor", "Armor"],
	[&"consumables", "Consumables"],
	[&"materials", "Materials"],
	[&"quest", "Quest"],
	[&"items", "Items"],
]
## Display-only price labels for buyable bags, keyed by BAG NUMBER (not index).
## The authoritative costs live in inventory.upgrade_bag.gd on the server.
const BAG_PRICE_LABELS: Dictionary = {
	2: "500K",
	3: "1.25M",
}

const GRID_COLUMNS: int = 4
const SECTION_HEADER_COLOR: Color = Color(0.56, 0.72, 0.85)
const EQUIPPED_BADGE_COLOR: Color = Color(1.0, 0.9, 0.55)
## Gear slot keys that hold REAL equipment (moved out of the bag on equip).
## The weapon slot can also hold a bag item (a potion in hand) — synthetic
## equipped tiles therefore only render for GearItems.
const EQUIP_SLOT_KEYS: Array[StringName] = [
	&"weapon", &"helmet", &"torso", &"boot", &"ring", &"amulet", &"relic", &"ammo",
]

## Last active tab, remembered across menu opens for the whole session.
static var _session_tab: int = Item.InventoryTab.WEAPON

var _inventory: Dictionary
var _gold_id: int
var _tab_filter: int = Item.InventoryTab.WEAPON
var _filling: bool
## A refresh that arrived while one was in flight — run it after (an
## equipment_changed can land mid-fill when a weapon draw completes).
var _refill_queued: bool
## Current active inventory bag (0-2) and unlocked count (1-3).
var _active_bag: int = 0
var _bag_count: int = 1
var _bag_tab_buttons: Array[Button] = []
var _bag_tab_container: HBoxContainer
## Bag tab index armed for purchase, or -1. Buying costs 500K/1.25M gold from a
## TAB click, so it takes two clicks — see _on_bag_tab.
var _pending_bag_purchase: int = -1

## Current selection driving the detail column.
var _selected_item: Item
var _selected_item_id: int
var _selected_slot_uid: int = -1
## Set when an equipped tile is selected (Unequip mode); empty for a bag item.
var _selected_gear_slot: StringName
var _selected_pinned: bool
## Salvage recipe for the current selection, or null when it can't be broken
## down. Drives whether the Break Down button shows at all.
var _selected_salvage: SalvageRecipe
## Built at runtime (same pattern as PlayerContextMenu's dialogs). Breaking down
## destroys the item, so it is the one bag action behind a confirm.
var _salvage_dialog: ConfirmationDialog

## Wallet widgets, created in the shell header at runtime.
var wallet_icon: TextureRect
var wallet_amount: Label
var hint_bar: InputHintBar
var _tab_buttons: Array[Button]
## One selection across every section grid — the pressed tile shows the
## theme's accent style, marking what the detail column describes.
var _tile_group: ButtonGroup = ButtonGroup.new()
## [button, entry] pairs of the current grid build, for selection restore.
var _tiles: Array
## Captured before build_shell reparents it — $MainBody stops resolving after.
var _main_body: HBoxContainer
## The Equipment view (paperdoll + gear totals), swapped with the bag via the
## shell-header Bag | Equipment tabs.
var _equipment_body: HBoxContainer
var _view_tabs: Dictionary[StringName, Button] = {}
## Crisp pixel preview mounted onto %DetailIcon (a sizing host; its own texture stays null).
var _detail_pixel: TextureRect

@onready var left_col: VBoxContainer = %LeftCol
@onready var rail_tabs: HBoxContainer = %RailTabs
@onready var lb_chip: Label = %LBChip
@onready var rb_chip: Label = %RBChip
@onready var bag_scroll: ScrollContainer = %BagScroll
@onready var section_list: VBoxContainer = %SectionList
@onready var detail_icon: TextureRect = %DetailIcon
@onready var detail_name: Label = %DetailName
@onready var detail_description: RichTextLabel = %DetailDescription
@onready var action_button: Button = %ActionButton
@onready var hotkey_button: Button = %HotkeyButton
@onready var pin_button: Button = %PinButton
@onready var salvage_button: Button = %SalvageButton


func _ready() -> void:
	_gold_id = Economy.gold_id()
	# Wrap the authored body in the shared menu shell (banner header + card).
	_main_body = $MainBody
	_equipment_body = $EquipmentBody
	build_shell("Inventory", _main_body, true)
	# The Equipment view shares the card; the header tabs swap the two bodies.
	_equipment_body.get_parent().remove_child(_equipment_body)
	content.add_child(_equipment_body)
	_build_view_tabs()
	_apply_blur_backdrop()
	_build_wallet()
	detail_icon.texture = null
	_detail_pixel = PixelIcon.mount(detail_icon)

	_build_bag_tabs()
	_build_rail_tabs()
	_build_hint_bar()

	action_button.pressed.connect(_on_action_button_pressed)
	hotkey_button.pressed.connect(_on_hotkey_button_pressed)
	pin_button.pressed.connect(_on_pin_button_pressed)
	salvage_button.pressed.connect(_on_salvage_button_pressed)
	_salvage_dialog = ConfirmationDialog.new()
	_salvage_dialog.title = "Break Down"
	_salvage_dialog.ok_button_text = "Break Down"
	_salvage_dialog.cancel_button_text = "Cancel"
	_salvage_dialog.confirmed.connect(_confirm_salvage)
	add_child(_salvage_dialog)

	_connect_equipment_signal()
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer): _connect_equipment_signal())
	ClientState.input_changed.connect(func(_t: InputComponent.InputType): _update_pad_chips())

	_tab_filter = _session_tab
	_sync_tab_buttons()
	_clear_detail()
	fill_inventory()
	visibility_changed.connect(fill_inventory)
	# Refresh the bag live when ore is gathered / ground loot is picked up.
	ClientState.gather_succeeded.connect(func(_result: Dictionary):
		if visible:
			fill_inventory())
	ClientState.inventory_changed.connect(func(_result: Dictionary):
		if visible:
			fill_inventory())


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"menu_tab_prev") and _main_body.visible:
		get_viewport().set_input_as_handled()
		_cycle_tab(-1)
	elif event.is_action_pressed(&"menu_tab_next") and _main_body.visible:
		get_viewport().set_input_as_handled()
		_cycle_tab(1)
	elif event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close_pressed()


## Currency chip (icon + amount) in the shell header, top-right next to Close.
## Icon-driven so it's ready for alt-currency the same way the shop is.
func _build_wallet() -> void:
	wallet_icon = TextureRect.new()
	wallet_icon.custom_minimum_size = Vector2(22, 22)
	wallet_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	wallet_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wallet_icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var gold: Item = ContentRegistryHub.load_by_id(&"items", _gold_id)
	if gold:
		wallet_icon.texture = gold.item_icon
	wallet_amount = Label.new()
	wallet_amount.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.45))
	wallet_amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_right.add_child(wallet_icon)
	header_right.add_child(wallet_amount)
	header_right.move_child(wallet_icon, 0)
	header_right.move_child(wallet_amount, 1)


# --- Bag | Equipment view tabs (shell header center) ---

func _build_view_tabs() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	for view: Array in [["Bag", &"bag"], ["Equipment", &"equipment"]]:
		var button: Button = Button.new()
		button.text = view[0]
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"FlatButton"
		button.custom_minimum_size = Vector2(110, 34)
		button.pressed.connect(_set_view.bind(StringName(view[1])))
		header_center.add_child(button)
		_view_tabs[view[1]] = button
	_view_tabs[&"bag"].set_pressed_no_signal(true)


func _set_view(view: StringName) -> void:
	_main_body.visible = view == &"bag"
	_equipment_body.visible = view == &"equipment"
	for key: StringName in _view_tabs:
		_view_tabs[key].set_pressed_no_signal(key == view)


# --- Category rail ---

func _build_bag_tabs() -> void:
	_bag_tab_container = HBoxContainer.new()
	_bag_tab_container.add_theme_constant_override(&"separation", 4)
	_bag_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.add_child(_bag_tab_container)
	left_col.move_child(_bag_tab_container, 0)
	var group: ButtonGroup = ButtonGroup.new()
	for i: int in range(Inventory.MAX_BAGS):
		var button: Button = Button.new()
		button.text = "Bag %d" % (i + 1)
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"FlatButton"
		button.custom_minimum_size = Vector2(0, 28)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_bag_tab.bind(i))
		_bag_tab_container.add_child(button)
		_bag_tab_buttons.append(button)


func _update_bag_tabs() -> void:
	for i: int in _bag_tab_buttons.size():
		var button: Button = _bag_tab_buttons[i]
		button.visible = true
		button.set_pressed_no_signal(i == _active_bag)
		if i < _bag_count:
			# Owned.
			button.disabled = false
			button.text = "Bag %d" % (i + 1)
			button.tooltip_text = ""
			continue
		# Locked. Only the NEXT bag is buyable — bag 3 cannot be bought before
		# bag 2, and the server refuses a mismatch (reason "wrong_bag").
		var buyable: bool = i == _bag_count
		button.disabled = not buyable
		if not buyable:
			button.text = "Bag %d (locked)" % (i + 1)
			button.tooltip_text = "Unlock Bag %d first." % (i)
			continue
		var price: String = BAG_PRICE_LABELS.get(i + 1, "?")
		if _pending_bag_purchase == i:
			button.text = "Buy for %s? Click again" % price
			button.tooltip_text = "Click once more to spend %s gold." % price
		else:
			button.text = "Bag %d (%s)" % [i + 1, price]
			button.tooltip_text = "Buy Bag %d for %s gold." % [i + 1, price]


func _on_bag_tab(index: int) -> void:
	if InstanceClient.current == null:
		return
	if index < _bag_count:
		_pending_bag_purchase = -1
		_active_bag = index
		Client.request_data(
			&"inventory.set_active_bag", Callable(), {"bag": index}, InstanceClient.current.name
		)
		_update_bag_tabs()
		_rebuild_grid()
		return

	# Locked tab. Only the next bag is for sale.
	if index != _bag_count:
		Toaster.toast("Unlock Bag %d first." % index)
		_update_bag_tabs()
		return

	# These cost 500,000 / 1,250,000 gold and the affordance is a TAB, so a
	# single stray click must never spend it. First click arms, second buys.
	if _pending_bag_purchase != index:
		_pending_bag_purchase = index
		_update_bag_tabs()
		Toaster.toast("Click again to buy Bag %d for %s gold." % [
			index + 1, BAG_PRICE_LABELS.get(index + 1, "?")
		])
		return

	_pending_bag_purchase = -1
	# Send which bag we believe we are buying; the server refuses a mismatch so
	# the label and the charge can never disagree.
	var result: Array = await Client.request_data_await(
		&"inventory.upgrade_bag", {"bag": index + 1}, InstanceClient.current.name
	)
	var payload: Dictionary = result[0] if result[0] is Dictionary else {}
	if result[1] == OK and bool(payload.get("ok", false)):
		Toaster.toast("Bag %d unlocked!" % int(payload.get("bags", index + 1)))
		fill_inventory()
		return
	match str(payload.get("reason", "")):
		"cant_afford":
			Toaster.toast("You need %s gold." % BAG_PRICE_LABELS.get(index + 1, "more"))
		"max_bags":
			Toaster.toast("You already own every bag.")
		"dead":
			Toaster.toast("Not while you are dead.")
		"wrong_bag":
			Toaster.toast("Unlock Bag %d first." % int(payload.get("next_bag", index)))
		_:
			Toaster.toast("Could not buy that bag.")
	_update_bag_tabs()


func _build_rail_tabs() -> void:
	var group: ButtonGroup = ButtonGroup.new()
	for tab: Array in RAIL_TABS:
		var button: Button = Button.new()
		button.text = tab[0]
		button.toggle_mode = true
		button.button_group = group
		button.theme_type_variation = &"FlatButton"
		button.custom_minimum_size = Vector2(0, 36)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_set_tab.bind(int(tab[1])))
		if int(tab[1]) in DYNAMIC_TABS:
			button.visible = false # shown by _update_dynamic_tabs when such an item is held
		rail_tabs.add_child(button)
		_tab_buttons.append(button)
	_sync_tab_buttons()
	_update_pad_chips()


func _set_tab(filter: int) -> void:
	_tab_filter = filter
	_session_tab = filter
	_sync_tab_buttons()
	_rebuild_grid()


## Cycle through the visible rail tabs (pad LB/RB).
func _cycle_tab(direction: int) -> void:
	var visible_tabs: Array[int] = []
	for i: int in RAIL_TABS.size():
		if _tab_buttons[i].visible:
			visible_tabs.append(i)
	if visible_tabs.is_empty():
		return
	var current: int = 0
	for idx: int in visible_tabs.size():
		if int(RAIL_TABS[visible_tabs[idx]][1]) == _tab_filter:
			current = idx
	var next: int = visible_tabs[(current + direction + visible_tabs.size()) % visible_tabs.size()]
	_set_tab(int(RAIL_TABS[next][1]))


func _sync_tab_buttons() -> void:
	# set_pressed_no_signal bypasses the ButtonGroup — sync every tab.
	for i: int in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(int(RAIL_TABS[i][1]) == _tab_filter)


func _update_pad_chips() -> void:
	var pad: bool = ClientState.input_type == InputComponent.InputType.GAMEPAD
	lb_chip.visible = pad
	rb_chip.visible = pad


func _build_hint_bar() -> void:
	hint_bar = InputHintBar.new()
	hint_bar.set_hints({
		InputComponent.InputType.MOUSE_KEYBOARD: [["Esc", "Close"]],
		InputComponent.InputType.GAMEPAD: [["LB/RB", "Category"], ["B", "Close"]],
	})
	# Bottom of the LEFT column — the detail column keeps its full height, and
	# on touch (no hints) the freed row goes back to the grid.
	left_col.add_child(hint_bar)


## Same frosted-glass backdrop as the settings menu (owner comparing looks).
func _apply_blur_backdrop() -> void:
	var blur: ShaderMaterial = ShaderMaterial.new()
	blur.shader = load("res://source/client/ui/shared/menu_blur_backdrop.gdshader")
	blur.set_shader_parameter(&"blur_lod", 2.5)
	blur.set_shader_parameter(&"dim_color", Color(0.073365234, 0.08239203, 0.122337736, 0.55))
	backdrop.material = blur


# --- Bag data + grid ---

func fill_inventory() -> void:
	if _filling:
		_refill_queued = true
		return
	_filling = true
	var bag_result: Array = await Client.request_data_await(&"inventory.bags", {}, InstanceClient.current.name)
	var result: Array = await Client.request_data_await(&"inventory.get", {}, InstanceClient.current.name)
	_filling = false
	if _refill_queued:
		_refill_queued = false
		fill_inventory()
		return
	if result[1] != OK:
		fill_inventory()
		return

	_inventory = result[0]
	if bag_result[1] == OK:
		var bag_data: Dictionary = bag_result[0] if bag_result[0] is Dictionary else {}
		_bag_count = clampi(int(bag_data.get("bags", 1)), 1, Inventory.MAX_BAGS)
		_active_bag = clampi(int(bag_data.get("active_bag", 0)), 0, _bag_count - 1)
	_set_wallet(Inventory.count(_inventory, _gold_id))
	_update_bag_tabs()
	_update_dynamic_tabs()
	_rebuild_grid()


## Favorites/Others/Quest tabs only exist while a matching item is held.
func _update_dynamic_tabs() -> void:
	var held: Dictionary = {}
	for tab: int in DYNAMIC_TABS:
		held[tab] = false
	for slot_uid_key in _inventory:
		var data: Dictionary = _inventory[slot_uid_key]
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(data.get("id", 0))) as Item
		if item == null or item.is_currency:
			continue
		if held.has(item.inventory_tab()):
			held[item.inventory_tab()] = true
		if data.get("p", false):
			held[TAB_FAVORITES] = true
	for i: int in RAIL_TABS.size():
		var filter: int = int(RAIL_TABS[i][1])
		if not held.has(filter):
			continue
		_tab_buttons[i].visible = held[filter]
		if not held[filter] and _tab_filter == filter:
			_set_tab(Item.InventoryTab.WEAPON)


func _rebuild_grid() -> void:
	for child: Node in section_list.get_children():
		child.queue_free()
	_tiles = []

	var sections: Dictionary = {}
	for entry: Dictionary in _collect_entries():
		var key: StringName = entry.group
		if not sections.has(key):
			sections[key] = []
		sections[key].append(entry)

	# Known groups render in GROUPS order; unknown group keys (a future weapon
	# category not listed yet) still render, appended alphabetically.
	var ordered_keys: Array = []
	for group: Array in GROUPS:
		ordered_keys.append(group[0])
	var extra_keys: Array = sections.keys().filter(func(k: StringName) -> bool: return not k in ordered_keys)
	extra_keys.sort()
	for key: StringName in ordered_keys + extra_keys:
		if not sections.has(key):
			continue
		var entries: Array = sections[key]
		entries.sort_custom(_entry_less_than)
		section_list.add_child(_make_section_header(_group_label(key)))
		var grid: GridContainer = GridContainer.new()
		grid.columns = GRID_COLUMNS
		grid.add_theme_constant_override(&"h_separation", 6)
		grid.add_theme_constant_override(&"v_separation", 6)
		for entry: Dictionary in entries:
			var tile: Button = _make_bag_button(entry)
			grid.add_child(tile)
			_tiles.append([tile, entry])
		section_list.add_child(grid)

	_restore_selection()
	DragScroll.enable(bag_scroll) # touch/mouse drag-scroll the bag (flips fresh rows to PASS)


## Re-select the previously selected item after a rebuild (by bag uid, or by
## gear slot for equipped tiles); otherwise select the first tile so the
## detail column is never an empty box.
func _restore_selection() -> void:
	var target: Array = []
	for pair: Array in _tiles:
		var entry: Dictionary = pair[1]
		if _selected_item == null:
			break
		if _selected_slot_uid >= 0 and int(entry.uid) == _selected_slot_uid:
			target = pair
			break
		if _selected_slot_uid < 0 and not _selected_gear_slot.is_empty() and entry.slot_key == _selected_gear_slot:
			target = pair
			break
	if target.is_empty() and not _tiles.is_empty():
		target = _tiles[0]
	if target.is_empty():
		_clear_detail()
		return
	(target[0] as Button).set_pressed_no_signal(true)
	_on_entry_pressed(target[1])


func _group_label(key: StringName) -> String:
	for group: Array in GROUPS:
		if group[0] == key:
			return group[1]
	return String(key).capitalize()


## Everything the current tab shows: synthetic equipped-gear tiles first-in-
## group, then the bag. Each entry: item/id/uid/qty/pinned/equipped/slot_key/
## group/sort.
func _collect_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# item_id -> slot_key for equipped ids that are STILL in the bag (a weapon
	# mid-draw: the bag reconciles only when the draw lands). Those badge their
	# bag entry instead of getting a synthetic tile, so nothing duplicates.
	var equipped_in_bag: Dictionary = {}
	if ClientState.local_player != null and _tab_filter != TAB_FAVORITES:
		var values: Dictionary = ClientState.local_player.equipment_component.slots.values
		for slot_key: StringName in EQUIP_SLOT_KEYS:
			var item_id: int = int(values.get(slot_key, 0))
			if item_id <= 0:
				continue
			var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
			# Only true gear: a bag item riding the weapon slot (potion in
			# hand) already renders as its bag entry.
			if item == null or not item is GearItem:
				continue
			if not _passes_tab_value(item.inventory_tab()):
				continue
			if Inventory.has_item(_inventory, item_id):
				equipped_in_bag[item_id] = slot_key
				continue
			out.append({
				"item": item, "id": item_id, "uid": -1, "qty": 1,
				"pinned": false, "equipped": true, "slot_key": slot_key,
				"group": item.group_key(), "sort": item.sort_key(),
			})
	for slot_uid_key in _inventory:
		var data: Dictionary = _inventory[slot_uid_key]
		if int(data.get("bag", 0)) != _active_bag:
			continue
		var item_id: int = int(data.get("id", 0))
		var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
		if item == null or item.is_currency:
			continue
		var pinned: bool = bool(data.get("p", false))
		if _tab_filter == TAB_FAVORITES:
			if not pinned:
				continue
		elif not _passes_tab_value(item.inventory_tab()):
			continue
		var equipped_slot: StringName = equipped_in_bag.get(item_id, &"")
		if not equipped_slot.is_empty():
			equipped_in_bag.erase(item_id) # badge only one copy
		out.append({
			"item": item, "id": item_id, "uid": int(slot_uid_key),
			"qty": int(data.get("a", 1)), "pinned": pinned,
			"equipped": not equipped_slot.is_empty(), "slot_key": equipped_slot,
			"group": item.group_key(), "sort": item.sort_key(),
		})
	return out


func _passes_tab_value(tab: int) -> bool:
	return tab == _tab_filter


func _entry_less_than(a: Dictionary, b: Dictionary) -> bool:
	if a.equipped != b.equipped:
		return a.equipped # equipped tiles lead their section
	# Rank by group first, then player drag order (so rearrange sticks), and
	# only then intrinsic sort_key as a tie-breaker — never auto-resort.
	var rank_a: int = _group_rank(a.group)
	var rank_b: int = _group_rank(b.group)
	if rank_a != rank_b:
		return rank_a < rank_b
	var order: Array = BagOrder.load_order()
	var ia: int = BagOrder.index_of(order, int(a.uid))
	var ib: int = BagOrder.index_of(order, int(b.uid))
	if ia != ib:
		return ia < ib
	if a.sort != b.sort:
		return a.sort < b.sort
	return int(a.uid) < int(b.uid)


func _group_rank(key: StringName) -> int:
	for i: int in GROUPS.size():
		if GROUPS[i][0] == key:
			return i
	return GROUPS.size()


func _make_section_header(label_text: String) -> Label:
	var label: Label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override(&"font_size", 13)
	label.add_theme_color_override(&"font_color", SECTION_HEADER_COLOR)
	return label


func _make_bag_button(entry: Dictionary) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(64, 64)
	button.clip_contents = true
	button.toggle_mode = true
	button.button_group = _tile_group
	var item: Item = entry.item
	PixelIcon.mount(button, item.item_icon)
	button.tooltip_text = ItemTooltip.hover_text(item)
	if int(entry.qty) > 1:
		var qty: Label = Label.new()
		qty.text = "x%d" % int(entry.qty)
		qty.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(qty)
	if entry.equipped:
		var badge: Label = Label.new()
		badge.text = "E"
		badge.add_theme_font_size_override(&"font_size", 12)
		badge.add_theme_color_override(&"font_color", EQUIPPED_BADGE_COLOR)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		# Tuck the badge inside the tile border instead of riding the edge.
		badge.offset_left -= 4
		badge.offset_right -= 4
		badge.offset_top += 2
		badge.offset_bottom += 2
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(badge)
	button.pressed.connect(_on_entry_pressed.bind(entry))
	# Double-click / double-tap = the primary action (equip/use/unequip).
	# Shift+Left on bag armor = instant Equip (fluent mid-fight swaps).
	button.gui_input.connect(func(event: InputEvent) -> void:
		if event is not InputEventMouseButton:
			return
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.shift_pressed and not bool(entry.equipped) \
				and entry.item is GearItem \
				and (entry.item as GearItem).slot != null \
				and (entry.item as GearItem).slot.key != &"weapon":
			_on_entry_pressed(entry)
			if not action_button.disabled:
				_on_action_button_pressed()
			return
		if mouse.double_click:
			_on_entry_pressed(entry)
			if not action_button.disabled:
				_on_action_button_pressed())
	# Drag bag tiles onto each other to rearrange (client-persisted order).
	if int(entry.uid) >= 0:
		button.set_drag_forwarding(
			func(_at: Vector2) -> Variant:
				BagOrder.elevate_drag_preview(
					button,
					BagOrder.make_drag_preview((entry.item as Item).item_icon, Vector2(56, 56))
				)
				return {
					"bag_uid": int(entry.uid),
					"item_id": int((entry.item as Item).get_meta(&"id", 0)),
				},
			func(_at: Vector2, data: Variant) -> bool:
				return data is Dictionary and (data as Dictionary).has("bag_uid"),
			func(_at: Vector2, data: Variant) -> void:
				if data is not Dictionary:
					return
				var from_uid: int = int((data as Dictionary).get("bag_uid", -1))
				var to_uid: int = int(entry.uid)
				if from_uid < 0 or to_uid < 0 or from_uid == to_uid:
					return
				var from_id: int = int((data as Dictionary).get("item_id", 0))
				var to_id: int = int((entry.item as Item).get_meta(&"id", 0))
				if from_id > 0 and from_id == to_id:
					var moved: int = await StackMerge.try_merge(from_uid, to_uid, false)
					if moved > 0:
						fill_inventory()
						return
				BagOrder.move_before(BagOrder.load_order(), from_uid, to_uid)
				fill_inventory()
		)
	return button


# --- Selection / detail column ---

func _on_entry_pressed(entry: Dictionary) -> void:
	_selected_item = entry.item
	_selected_item_id = int(entry.id)
	_selected_slot_uid = int(entry.uid)
	_selected_gear_slot = entry.slot_key
	_selected_pinned = bool(entry.pinned)
	PixelIcon.set_art(_detail_pixel, _selected_item.item_icon)
	detail_name.text = str(_selected_item.item_name)
	detail_description.text = ItemTooltip.body(_selected_item, _compare_target())

	salvage_button.visible = false
	if entry.equipped:
		action_button.text = "Unequip"
		action_button.disabled = false
		hotkey_button.disabled = true # bag items only — equipped gear isn't in the bag
		pin_button.disabled = true
		pin_button.text = "Favorite"
		return

	if _selected_item is GearItem:
		action_button.text = "Equip"
		action_button.disabled = false
	elif _selected_item is ConsumableItem or _selected_item is LootChestItem or _selected_item is DungeonKeyItem:
		action_button.text = "Open" if _selected_item is LootChestItem else "Use"
		action_button.disabled = false
	elif _selected_item.holdable:
		action_button.text = "Hold"
		action_button.disabled = false
	elif _selected_item.can_drop():
		action_button.text = "Drop"
		action_button.disabled = false
	else:
		action_button.text = "—"
		action_button.disabled = true
	# Quick slots are for equip / use / hold — not Drop-only materials.
	hotkey_button.disabled = not (
		_selected_item is GearItem
		or _selected_item is ConsumableItem
		or _selected_item is LootChestItem
		or _selected_item is DungeonKeyItem
		or _selected_item.holdable
	)
	pin_button.disabled = false
	pin_button.text = "Unfavorite" if _selected_pinned else "Favorite"
	# Breaking down is offered only for items the salvage table actually knows,
	# so the button never appears as a dead end on ordinary gear.
	var salvage_table: SalvageTable = SalvageTable.shared()
	_selected_salvage = (
		salvage_table.recipe_for(_selected_item_id)
		if salvage_table != null and _selected_slot_uid >= 0
		else null
	)
	# Shown for anything that COULD have a recipe, disabled when it does not, so
	# "where is salvage?" is answered on the item itself instead of by hunting.
	var salvageable_kind: bool = _selected_item is GearItem or _selected_item.holdable
	salvage_button.visible = salvageable_kind and _selected_slot_uid >= 0
	salvage_button.disabled = _selected_salvage == null
	salvage_button.tooltip_text = (
		"" if _selected_salvage != null else "This can't be broken down."
	)


## The equipped counterpart for stat deltas — only when the selection is bag
## gear (comparing an equipped piece to itself is noise).
func _compare_target() -> Item:
	if not _selected_gear_slot.is_empty() or not _selected_item is GearItem:
		return null
	if ClientState.local_player == null or _selected_item.slot == null:
		return null
	var equipped_id: int = int(ClientState.local_player.equipment_component.slots.values.get(_selected_item.slot.key, 0))
	if equipped_id <= 0 or equipped_id == _selected_item_id:
		return null
	var equipped: Item = ContentRegistryHub.load_by_id(&"items", equipped_id) as Item
	return equipped if equipped is GearItem else null


func _clear_detail() -> void:
	_selected_item = null
	_selected_item_id = 0
	_selected_slot_uid = -1
	_selected_gear_slot = &""
	_selected_pinned = false
	PixelIcon.set_art(_detail_pixel, null)
	detail_name.text = "Select an item"
	detail_description.text = ""
	action_button.disabled = true
	hotkey_button.disabled = true
	pin_button.disabled = true
	pin_button.text = "Favorite"
	_selected_salvage = null
	salvage_button.visible = false


# --- Actions ---

func _on_action_button_pressed() -> void:
	# No _clear_detail on success: the refresh restores the selection (or the
	# first tile — for a fresh equip that IS the new badged tile).
	if not _selected_gear_slot.is_empty():
		var slot_key: StringName = _selected_gear_slot
		var unequip_result: Array = await Client.request_data_await(&"item.unequip", {"slot": slot_key}, InstanceClient.current.name)
		if not _surface_item_rejection(unequip_result):
			fill_inventory()
		return
	if _selected_item == null or _selected_item_id <= 0:
		return
	if _selected_item is LootChestItem:
		var open_result: Array = await Client.request_data_await(
			&"chest.open_item",
			{"id": _selected_item_id},
			InstanceClient.current.name
		)
		if not _surface_item_rejection(open_result):
			fill_inventory()
		return
	if _selected_item is DungeonKeyItem:
		var key_result: Array = await Client.request_data_await(
			&"dungeon.key_use",
			{"id": _selected_item_id},
			InstanceClient.current.name
		)
		if not _surface_item_rejection(key_result):
			fill_inventory()
		return
	if _selected_item is ConsumableItem:
		var consume_result: Array = await Client.request_data_await(
			&"item.consume",
			{"id": _selected_item_id},
			InstanceClient.current.name
		)
		if not _surface_item_rejection(consume_result):
			ConsumableItem.stamp_client_cooldown(_selected_item as ConsumableItem)
			fill_inventory()
		return
	if _selected_item is GearItem or _selected_item.holdable:
		var result: Array = await Client.request_data_await(&"item.equip", {"id": _selected_item_id}, InstanceClient.current.name)
		if not _surface_item_rejection(result):
			fill_inventory()
		return
	if _selected_item.can_drop() and _selected_slot_uid >= 0:
		var drop_result: Array = await Client.request_data_await(
			&"item.drop",
			{"uid": _selected_slot_uid},
			InstanceClient.current.name
		)
		if not _surface_item_rejection(drop_result):
			fill_inventory()


## Asks before breaking the selection down — the item is destroyed and the
## yield is worth a fraction of it, so a misclick here is not recoverable the
## way a Drop is (that one leaves the stack on the ground).
func _on_salvage_button_pressed() -> void:
	if _selected_item == null or _selected_salvage == null or _selected_slot_uid < 0:
		return
	_salvage_dialog.dialog_text = "Break down 1 %s into %s?\nThe %s is destroyed." % [
		_selected_item.item_name, _salvage_yield_text(_selected_salvage), _selected_item.item_name
	]
	_salvage_dialog.popup_centered()


func _confirm_salvage() -> void:
	if _selected_slot_uid < 0:
		return
	var result: Array = await Client.request_data_await(
		&"item.salvage",
		{"uid": _selected_slot_uid, "amount": 1},
		InstanceClient.current.name
	)
	if _surface_item_rejection(result):
		return
	var payload: Dictionary = result[0] if result[0] is Dictionary else {}
	Toaster.toast("Broke it down into %s." % _granted_text(payload.get("granted", [])))
	fill_inventory()


## "1-3x Iron Bar" — the authored yield, for the confirm prompt. Ranges stay
## ranges here: the roll happens server-side, so this cannot promise a number.
func _salvage_yield_text(recipe: SalvageRecipe) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for output: SalvageOutput in recipe.outputs:
		if output == null or output.item == null:
			continue
		parts.append(output.describe())
	return ", ".join(parts) if not parts.is_empty() else "nothing"


## Same shape, built from what the server actually GRANTED — which is the only
## place a rolled yield (1-3 iron bars) becomes a real number.
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


## Opens the shared slot picker for the selected bag item. Picking the slot
## the item already occupies clears it (toggle); picking another slot moves
## it there, vacating its old one.
func _on_hotkey_button_pressed() -> void:
	if _selected_item == null:
		return
	var item: Item = _selected_item
	var entries: PackedStringArray = PackedStringArray()
	for i: int in 3:
		var occupant: Item = ClientState.quick_slots.get_key(i) as Item
		var occupant_name: String = String(occupant.item_name) if occupant != null else "empty"
		entries.append("Slot %d (key %d)  —  %s" % [i + 1, i + 1, occupant_name])
	SlotPickerOverlay.open(self, "Place %s on which quick slot?" % item.item_name, entries,
		func(slot: int) -> void:
			var occupant: Item = ClientState.quick_slots.get_key(slot) as Item
			if occupant == item:
				ClientState.quick_slots.set_key(slot, null) # toggle off
				return
			# Move semantics: vacate any other slot already holding this item.
			for i: int in 3:
				if (ClientState.quick_slots.get_key(i) as Item) == item:
					ClientState.quick_slots.set_key(i, null)
			ClientState.quick_slots.set_key(slot, item)
	)


func _on_pin_button_pressed() -> void:
	if _selected_slot_uid < 0:
		return
	var pin: bool = not _selected_pinned
	var result: Array = await Client.request_data_await(
		&"item.pin", {"uid": _selected_slot_uid, "on": pin}, InstanceClient.current.name)
	if result[1] != OK or not bool(result[0].get("ok", false)):
		Toaster.toast("Couldn't update favorites.")
		return
	_selected_pinned = pin
	fill_inventory()


## Toasts a server rejection (combat lock, cooldown) and returns true if the
## action was rejected, so the caller skips the success refresh.
func _surface_item_rejection(result: Array) -> bool:
	if result.size() < 2 or result[1] != OK:
		Toaster.toast("That action failed.")
		return true
	var payload: Dictionary = result[0] if result[0] is Dictionary else {}
	if bool(payload.get("ok", false)):
		return false
	match str(payload.get("reason", "")):
		"in_combat":
			Toaster.toast("You cannot do that while in combat.")
			return true
		"cooldown":
			Toaster.toast("That's still on cooldown.")
			return true
		"level":
			Toaster.toast("Requires level %d to equip." % int(payload.get("level", 0)))
			return true
		"mastery":
			Toaster.toast(_mastery_equip_toast(payload))
			return true
		"cant_equip":
			Toaster.toast("You can't equip that.")
			return true
		"cant_drop":
			Toaster.toast("That item cannot be dropped.")
			return true
		"coating_active":
			Toaster.toast("You already have an active potion.")
			return true
		"cant_salvage":
			Toaster.toast("That item cannot be broken down.")
			return true
		"salvage_level":
			Toaster.toast("Requires %s %d to break that down." % [
				str(payload.get("profession", "herblore")).capitalize(),
				int(payload.get("required_level", 0)),
			])
			return true
		"pinned":
			Toaster.toast("Unfavorite it first — favorites can't be broken down.")
			return true
		"dead":
			Toaster.toast("You cannot do that while dead.")
			return true
		"missing":
			Toaster.toast("That item is no longer in your inventory.")
			return true
		"inventory_full":
			Toaster.toast("Your bag is full. Bank some items first.")
			return true
		"no_map", "spawn_failed":
			Toaster.toast("Could not drop that item here.")
			return true
	if not payload.is_empty() and not bool(payload.get("ok", true)):
		Toaster.toast("That action failed.")
		return true
	return false


func _set_wallet(amount: int) -> void:
	wallet_amount.text = str(amount)


# --- Equipment sync (badged tiles are rebuilt on any equipment change) ---

func _connect_equipment_signal() -> void:
	var local_player: Player = ClientState.local_player
	if local_player == null:
		return
	if not local_player.equipment_component.equipment_changed.is_connected(_on_equipment_changed):
		local_player.equipment_component.equipment_changed.connect(_on_equipment_changed)


func _on_equipment_changed(_slot_key: StringName, _item_id: int) -> void:
	# Re-FETCH, don't just rebuild: a weapon draw reconciles the bag only when
	# the draw lands, and rebuilding from the stale snapshot duplicated the
	# weapon (synthetic equipped tile + its not-yet-removed bag entry).
	if visible:
		fill_inventory()


func _mastery_equip_toast(payload: Dictionary) -> String:
	var level: int = int(payload.get("level", 0))
	var cats: PackedStringArray = PackedStringArray()
	for entry: Variant in payload.get("categories", []):
		cats.append(str(entry).capitalize())
	if cats.is_empty() or (cats.size() == 1 and cats[0].to_lower() == "any"):
		return "Requires any mastery level %d." % level
	return "Requires %s mastery %d." % [" / ".join(cats), level]
