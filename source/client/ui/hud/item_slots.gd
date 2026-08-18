extends Control
## HUD quick slots (keys 1 / 2 / 3): one-press access to bag items — weapons
## and tools EQUIP (with swap), consumables USE via item.consume so a potion
## never displaces the held weapon.
##
## Assignment:
##  • Inventory / compact bag → Hotkey / Bind to 1-2-3
##  • Drag an item from the bag onto a slot button
## Bindings persist client-side per character.


const SLOT_COUNT: int = 3
const SLOT_ACTIONS: Array[StringName] = [
	&"player_quickslot_1", &"player_quickslot_2", &"player_quickslot_3",
]
const SETTINGS_SECTION: StringName = &"quick_slots"
const SLOT_SIZE: Vector2 = Vector2(32, 32)

var item_shortcuts: Array[Item]
## Per-slot cooldown overlays (sweep + seconds), keyed by index.
var _cd_overlays: Array[Dictionary] = []

@onready var slot_container: VBoxContainer = $VBoxContainer


func _ready() -> void:
	item_shortcuts.resize(SLOT_COUNT)
	_cd_overlays.resize(SLOT_COUNT)
	for i: int in slot_container.get_child_count():
		var button: Button = slot_container.get_child(i) as Button
		button.pressed.connect(_trigger_slot.bind(i))
		button.set_meta(&"quick_slot_index", i)
		# Accept inventory / bag drag-drops of potions and gear.
		button.set_drag_forwarding(Callable(), _quickslot_can_drop.bind(i), _quickslot_drop.bind(i))
		# Corner key hint that survives the icon replacing the button text.
		var key_label: Label = Label.new()
		key_label.text = str(i + 1)
		key_label.add_theme_font_size_override(&"font_size", 8)
		key_label.add_theme_color_override(&"font_color", Color(0.75, 0.78, 0.85))
		key_label.position = Vector2(3, 1)
		key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		key_label.z_index = 1
		button.add_child(key_label)
		button.set_meta(&"pixel_icon", PixelIcon.mount(button))
		_cd_overlays[i] = _make_cd_overlay(button)

	ClientState.quick_slots.data_changed.connect(_on_slot_assigned)
	# Re-sync from any bindings already in memory (instance changes rebuild
	# the HUD; ClientState persists across them).
	for slot_index: Variant in ClientState.quick_slots.data:
		_on_slot_assigned(slot_index, ClientState.quick_slots.data[slot_index])
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer) -> void: _load_persisted())
	set_process(true)


func _make_cd_overlay(button: Button) -> Dictionary:
	var sweep := ColorRect.new()
	sweep.color = Color(0.0, 0.0, 0.0, 0.55)
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sweep.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sweep.visible = false
	button.add_child(sweep)
	var cd_label := Label.new()
	cd_label.add_theme_font_size_override(&"font_size", 14)
	cd_label.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_label.visible = false
	cd_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.add_child(cd_label)
	return {"sweep": sweep, "cd_label": cd_label}


func _process(_delta: float) -> void:
	_refresh_cooldown_overlays()


func _refresh_cooldown_overlays() -> void:
	var player: Character = ClientState.local_player
	if player == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	for i: int in SLOT_COUNT:
		if i >= _cd_overlays.size() or _cd_overlays[i].is_empty():
			continue
		var sweep: ColorRect = _cd_overlays[i]["sweep"]
		var cd_label: Label = _cd_overlays[i]["cd_label"]
		var item: Item = item_shortcuts[i] if i < item_shortcuts.size() else null
		var consumable: ConsumableItem = item as ConsumableItem
		if consumable == null or consumable.shared_cooldown_ms <= 0:
			sweep.visible = false
			cd_label.visible = false
			continue
		var key: String = "consumable:" + str(consumable.cooldown_category)
		if not player.ability_cooldowns.has(key):
			sweep.visible = false
			cd_label.visible = false
			continue
		var last: float = float(player.ability_cooldowns[key])
		var cooldown: float = float(consumable.shared_cooldown_ms) / 1000.0
		var remaining: float = maxf(0.0, cooldown - (now - last))
		if remaining > 0.05 and cooldown > 0.0:
			var slot_h: float = button_height_for(i)
			sweep.visible = true
			sweep.offset_top = -slot_h * clampf(remaining / cooldown, 0.0, 1.0)
			cd_label.text = "%.1f" % remaining
			cd_label.visible = true
		else:
			sweep.visible = false
			cd_label.visible = false


func button_height_for(index: int) -> float:
	if index < 0 or index >= slot_container.get_child_count():
		return SLOT_SIZE.y
	var button: Control = slot_container.get_child(index) as Control
	if button == null:
		return SLOT_SIZE.y
	return maxf(SLOT_SIZE.y, button.size.y)


## Keyboard 1/2/3. _unhandled_input on purpose: keys consumed by the GUI
## (typing numbers in chat) never reach here. Ignore key-repeat echoes so
## holding a rebound hotkey (e.g. Space) can't fire the slot every OS repeat.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	for i: int in SLOT_ACTIONS.size():
		if event.is_action_pressed(SLOT_ACTIONS[i]):
			_trigger_slot(i)
			get_viewport().set_input_as_handled()
			return


func _trigger_slot(index: int) -> void:
	var item: Item = item_shortcuts[index] if index < item_shortcuts.size() else null
	if item == null:
		return
	# Potions / food always drink from the bag — never toggle a held copy.
	if item is ConsumableItem:
		Client.request_data(
			&"item.consume",
			func(result: Dictionary) -> void:
				_on_item_action_result(result)
				if bool(result.get("ok", false)):
					ConsumableItem.stamp_client_cooldown(item as ConsumableItem)
				_after_slot_used(result, index),
			{"id": int(item.get_meta(&"id", 0))},
			InstanceClient.current.name
		)
		return
	# Loot chests open from the bag (same payout as a world chest).
	if item is LootChestItem:
		Client.request_data(
			&"chest.open_item",
			func(result: Dictionary) -> void:
				_on_item_action_result(result)
				_after_slot_used(result, index),
			{"id": int(item.get_meta(&"id", 0))},
			InstanceClient.current.name
		)
		return
	if item is DungeonKeyItem:
		Client.request_data(
			&"dungeon.key_use",
			func(result: Dictionary) -> void:
				_on_item_action_result(result)
				_after_slot_used(result, index),
			{"id": int(item.get_meta(&"id", 0))},
			InstanceClient.current.name
		)
		return
	# Toggle: tapping the slot of whatever you're HOLDING puts it away.
	if _is_equipped(item):
		var slot_key: StringName = (item as GearItem).slot.key if item is GearItem else &"weapon"
		Client.request_data(
			&"item.unequip",
			_on_item_action_result,
			{"slot": slot_key},
			InstanceClient.current.name
		)
		return
	Client.request_data(
		&"item.equip",
		func(result: Dictionary) -> void:
			_on_item_action_result(result)
			_after_slot_used(result, index),
		{"id": int(item.get_meta(&"id", 0))},
		InstanceClient.current.name
	)


## Surfaces server rejections (combat lock, potion cooldown) as a toast so a
## key that "did nothing" explains itself.
func _on_item_action_result(result: Dictionary) -> void:
	match str(result.get("reason", "")):
		"in_combat":
			Toaster.toast("You cannot do that while in combat.")
		"cooldown":
			Toaster.toast("That's still on cooldown.")
		"no_effect":
			Toaster.toast("You do not currently need that potion.")
		"coating_active":
			Toaster.toast("You already have an active potion.")
		"level":
			Toaster.toast("Requires level %d to equip." % int(result.get("level", 0)))
		"mastery":
			var cats: PackedStringArray = PackedStringArray()
			for entry: Variant in result.get("categories", []):
				cats.append(str(entry).capitalize())
			var level: int = int(result.get("level", 0))
			if cats.is_empty() or (cats.size() == 1 and cats[0].to_lower() == "any"):
				Toaster.toast("Requires any mastery level %d." % level)
			else:
				Toaster.toast("Requires %s mastery %d." % [" / ".join(cats), level])
		"gear_level":
			Toaster.toast("Fair arena: level %d gear only." % int(result.get("level", 0)))
		"cant_equip":
			Toaster.toast("You can't equip that.")
		"inventory_full":
			Toaster.toast("Your bag is full. Bank some items first.")


func _is_equipped(item: Item) -> bool:
	if ClientState.local_player == null:
		return false
	# Weapons/gear sit in their own slot; every other hand item (potions, materials)
	# rides the &"weapon" hand slot. Either way: are we holding THIS exact item now?
	var slot_key: StringName = (item as GearItem).slot.key if item is GearItem else &"weapon"
	var equipped_id: int = int(ClientState.local_player.equipment_component.slots.values.get(slot_key, 0))
	return equipped_id == int(item.get_meta(&"id", 0))


## Consumables: once the LAST one is used, drop the binding — a key that
## silently no-ops reads as a bug. While a stack remains, the binding stays.
## (Gear bindings persist forever; the item just bounces bag <-> body.)
func _after_slot_used(_response: Dictionary, index: int) -> void:
	var item: Item = item_shortcuts[index] if index < item_shortcuts.size() else null
	if item == null or not (item is ConsumableItem or item is LootChestItem or item is DungeonKeyItem):
		return
	var item_id: int = int(item.get_meta(&"id", 0))
	Client.request_data(
		&"inventory.get",
		func(inventory: Dictionary) -> void:
			if Inventory.count(inventory, item_id) <= 0:
				ClientState.quick_slots.set_key(index, null),
		{},
		InstanceClient.current.name
	)


## Reacts to ClientState.quick_slots writes (inventory Hotkey assignment or
## the persisted load below). null item = cleared slot.
func _on_slot_assigned(index: Variant, item: Variant) -> void:
	var i: int = int(index)
	if i < 0 or i >= SLOT_COUNT:
		return
	item_shortcuts[i] = item as Item
	var button: Button = slot_container.get_child(i) as Button
	var pixel: TextureRect = button.get_meta(&"pixel_icon", null) as TextureRect
	if item != null:
		PixelIcon.set_art(pixel, (item as Item).item_icon)
		button.icon = null
		button.text = ""
	else:
		PixelIcon.set_art(pixel, null)
		button.icon = null
		button.text = str(i + 1)
	_persist()


func _load_persisted() -> void:
	if ClientState.player_id <= 0:
		return
	var section: Dictionary = ClientState.settings.data.get(SETTINGS_SECTION, {})
	var saved: Dictionary = section.get(StringName(str(ClientState.player_id)), {})
	for slot_key: Variant in saved:
		var item: Item = ContentRegistryHub.load_by_id(&"items", int(saved[slot_key])) as Item
		if item != null:
			ClientState.quick_slots.set_key(int(str(slot_key)), item)


func _persist() -> void:
	if ClientState.player_id <= 0:
		return
	var out: Dictionary = {}
	for i: int in SLOT_COUNT:
		if item_shortcuts[i] != null:
			out[str(i)] = int(item_shortcuts[i].get_meta(&"id", 0))
	if not ClientState.settings.data.has(SETTINGS_SECTION):
		ClientState.settings.data[SETTINGS_SECTION] = {}
	ClientState.settings.set_value(SETTINGS_SECTION, StringName(str(ClientState.player_id)), out)


func _quickslot_can_drop(_at_position: Vector2, data: Variant, _index: int) -> bool:
	var item: Item = _item_from_drag(data)
	if item == null:
		return false
	return (
		item is ConsumableItem
		or item is LootChestItem
		or item is DungeonKeyItem
		or item is GearItem
		or item.holdable
	)


func _quickslot_drop(_at_position: Vector2, data: Variant, index: int) -> void:
	var item: Item = _item_from_drag(data)
	if item == null:
		return
	# Move existing binding of the same item off other slots first.
	for i: int in SLOT_COUNT:
		if (ClientState.quick_slots.get_key(i) as Item) == item:
			ClientState.quick_slots.set_key(i, null)
	ClientState.quick_slots.set_key(index, item)
	Toaster.toast("Bound %s to key %d." % [item.item_name, index + 1])


static func _item_from_drag(data: Variant) -> Item:
	if data is Item:
		return data as Item
	if data is Dictionary:
		var dict: Dictionary = data
		var as_item: Variant = dict.get("item", null)
		if as_item is Item:
			return as_item as Item
		var item_id: int = int(dict.get("id", dict.get("item_id", 0)))
		if item_id > 0:
			return ContentRegistryHub.load_by_id(&"items", item_id) as Item
	return null
