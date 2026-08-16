extends MenuShell
## The Hunt Chest — the character's persistent Guild Hall stash. Every Boss Hunt
## drop is banked here as it falls, and the pile keeps across sessions, so this
## panel is a stash view rather than a claim prompt: take what you want now,
## leave the rest for next time.
##
## Opened from the Hunt Broker (open_menu_requested(&"hunt_chest")). Shape and
## row layout mirror chest_loot_menu deliberately — same gesture, different pile.

const COLOR_MUTED: Color = Color(0.78, 0.82, 0.9)

var _list: VBoxContainer
var _status: Label
var _stacks: Array = []
var _free_slots: int = 0
var _capacity: int = 0
var _busy: bool = false


func _ready() -> void:
	var body: VBoxContainer = VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_status = Label.new()
	_status.add_theme_font_size_override(&"font_size", 13)
	_status.add_theme_color_override(&"font_color", COLOR_MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(460, 320)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_list)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	body.add_child(actions)

	var take_all: Button = Button.new()
	take_all.text = "Take All (Bag)"
	take_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_all.custom_minimum_size = Vector2(0, 36)
	take_all.pressed.connect(func() -> void: _claim(&"hunt_chest.take", {"all": true}))
	actions.add_child(take_all)

	var bank_all: Button = Button.new()
	bank_all.text = "Bank All"
	bank_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bank_all.custom_minimum_size = Vector2(0, 36)
	bank_all.pressed.connect(func() -> void: _claim(&"hunt_chest.bank", {"all": true}))
	actions.add_child(bank_all)

	build_shell("Hunt Chest", body, false)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())


func open(_arg: Variant = null) -> void:
	_refresh()


func _refresh() -> void:
	Client.request_data(
		&"hunt_chest.get", _apply, {},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _apply(response: Dictionary) -> void:
	_busy = false
	if not bool(response.get("ok", false)) and response.has("message"):
		Toaster.toast(str(response["message"]))
	if response.has("stacks"):
		_stacks = response["stacks"] as Array
	_free_slots = int(response.get("free_slots", _free_slots))
	_capacity = int(response.get("capacity", _capacity))
	_rebuild()


func _rebuild() -> void:
	for child: Node in _list.get_children():
		child.queue_free()

	var count: int = _stacks.size()
	set_title("Hunt Chest" if count > 0 else "Hunt Chest (empty)")
	_status.text = (
		"%d / %d stacks stored · Bag free slots: %d\nLoot stays here until you take it. Gold goes straight to your pouch."
		% [count, _capacity, _free_slots]
	)

	if _stacks.is_empty():
		var empty: Label = Label.new()
		empty.text = "Nothing in here yet. Buy a contract from the broker."
		empty.add_theme_color_override(&"font_color", Color(0.7, 0.74, 0.82))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(empty)
		return

	for entry: Variant in _stacks:
		if entry is Dictionary:
			_list.add_child(_make_row(entry as Dictionary))


func _make_row(entry: Dictionary) -> Control:
	var item_id: int = int(entry.get("id", 0))
	var amount: int = int(entry.get("amount", 0))
	var item_name: String = str(entry.get("name", "Item"))

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.custom_minimum_size = Vector2(0, 44)

	var icon_wrap: CenterContainer = CenterContainer.new()
	icon_wrap.custom_minimum_size = Vector2(40, 40)
	row.add_child(icon_wrap)

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.item_icon != null:
		PixelIcon.mount(icon_wrap, item.item_icon)
	else:
		var placeholder: ColorRect = ColorRect.new()
		placeholder.custom_minimum_size = Vector2(32, 32)
		placeholder.color = Color(0.25, 0.28, 0.34)
		icon_wrap.add_child(placeholder)

	var label: Label = Label.new()
	label.text = "%s ×%d" % [item_name, amount] if amount > 1 else item_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var take: Button = Button.new()
	take.text = "Take"
	take.custom_minimum_size = Vector2(72, 34)
	take.pressed.connect(func() -> void: _claim(&"hunt_chest.take", {"item": item_id}))
	row.add_child(take)

	var bank: Button = Button.new()
	bank.text = "Bank"
	bank.custom_minimum_size = Vector2(72, 34)
	bank.pressed.connect(func() -> void: _claim(&"hunt_chest.bank", {"item": item_id}))
	row.add_child(bank)

	return row


## One in-flight claim at a time — double-tapping Take All while the first
## response is still in the air would render a stale pile over the new one.
func _claim(request: StringName, args: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	Client.request_data(
		request, _apply, args,
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)
