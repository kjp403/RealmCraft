extends MenuShell
## Claim UI for staged chest loot. Opens on chest.opened; further opens refresh
## the same panel so players can empty a stack of bag chests before claiming.

var _list: VBoxContainer
var _status: Label
var _pending: Array = []
var _free_slots: int = 0
var _busy: bool = false


func _ready() -> void:
	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_status = Label.new()
	_status.add_theme_font_size_override(&"font_size", 13)
	_status.add_theme_color_override(&"font_color", Color(0.78, 0.82, 0.9))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(420, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_list)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	body.add_child(actions)

	var take_all := Button.new()
	take_all.text = "Take All (Bag)"
	take_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	take_all.custom_minimum_size = Vector2(0, 36)
	take_all.pressed.connect(_on_take_all)
	actions.add_child(take_all)

	var bank_all := Button.new()
	bank_all.text = "Bank All"
	bank_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bank_all.custom_minimum_size = Vector2(0, 36)
	bank_all.pressed.connect(_on_bank_all)
	actions.add_child(bank_all)

	var bank_close := Button.new()
	bank_close.text = "Bank Rest & Close"
	bank_close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bank_close.custom_minimum_size = Vector2(0, 36)
	bank_close.pressed.connect(_on_bank_rest_and_close)
	actions.add_child(bank_close)

	build_shell("Chest Loot", body, false)
	close_requested.connect(_on_shell_close)


func open(data: Variant = null) -> void:
	if data is Dictionary:
		_apply_payload(data as Dictionary)
	else:
		_refresh_from_server()


func apply_opened(data: Dictionary) -> void:
	_apply_payload(data)
	show()
	move_to_front()


func _apply_payload(data: Dictionary) -> void:
	_pending = data.get("pending", []) as Array
	_free_slots = int(data.get("free_slots", _free_slots))
	_rebuild()


func _rebuild() -> void:
	for child: Node in _list.get_children():
		child.queue_free()

	var stack_count: int = _pending.size()
	_status.text = (
		"%d stack%s staged · Bag free slots: %d\nGold already went to your pouch."
		% [stack_count, "" if stack_count == 1 else "s", _free_slots]
	)
	set_title("Chest Loot" if stack_count > 0 else "Chest Loot (empty)")

	if _pending.is_empty():
		var empty := Label.new()
		empty.text = "Nothing left to claim."
		empty.add_theme_color_override(&"font_color", Color(0.7, 0.74, 0.82))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(empty)
		return

	for entry: Variant in _pending:
		if not entry is Dictionary:
			continue
		_list.add_child(_make_row(entry as Dictionary))


func _make_row(entry: Dictionary) -> Control:
	var item_id: int = int(entry.get("id", 0))
	var amount: int = int(entry.get("amount", 0))
	var item_name: String = str(entry.get("name", "Item"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.custom_minimum_size = Vector2(0, 44)

	var icon_wrap := CenterContainer.new()
	icon_wrap.custom_minimum_size = Vector2(40, 40)
	row.add_child(icon_wrap)

	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if item != null and item.item_icon != null:
		PixelIcon.mount(icon_wrap, item.item_icon)
	else:
		var placeholder := ColorRect.new()
		placeholder.custom_minimum_size = Vector2(32, 32)
		placeholder.color = Color(0.25, 0.28, 0.34)
		icon_wrap.add_child(placeholder)

	var label := Label.new()
	label.text = "%s ×%d" % [item_name, amount] if amount > 1 else item_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var take := Button.new()
	take.text = "Take"
	take.custom_minimum_size = Vector2(72, 34)
	take.pressed.connect(_on_take_one.bind(item_id))
	row.add_child(take)

	var bank := Button.new()
	bank.text = "Bank"
	bank.custom_minimum_size = Vector2(72, 34)
	bank.pressed.connect(_on_bank_one.bind(item_id))
	row.add_child(bank)

	return row


func _on_take_one(item_id: int) -> void:
	_request_claim(&"chest.loot_take", {"id": item_id})


func _on_bank_one(item_id: int) -> void:
	_request_claim(&"chest.loot_bank", {"id": item_id})


func _on_take_all() -> void:
	_request_claim(&"chest.loot_take", {})


func _on_bank_all() -> void:
	_request_claim(&"chest.loot_bank", {})


func _on_bank_rest_and_close() -> void:
	_request_claim(&"chest.loot_bank", {}, true)


func _on_shell_close() -> void:
	# Pending stays server-side until claimed or logout auto-bank.
	hide()


func _refresh_from_server() -> void:
	if _busy:
		return
	_busy = true
	var instance_id: String = InstanceClient.current.name if InstanceClient.current else ""
	var result: Array = await Client.request_data_await(&"chest.loot_get", {}, instance_id)
	_busy = false
	if result[1] != OK or not (result[0] as Dictionary).get("ok", false):
		Toaster.toast("Could not load chest loot.")
		return
	_apply_payload(result[0] as Dictionary)


func _request_claim(request: StringName, args: Dictionary, close_after: bool = false) -> void:
	if _busy:
		return
	_busy = true
	var instance_id: String = InstanceClient.current.name if InstanceClient.current else ""
	var result: Array = await Client.request_data_await(request, args, instance_id)
	_busy = false
	if result[1] != OK:
		Toaster.toast("No response from the server.")
		return
	var payload: Dictionary = result[0] as Dictionary
	if not bool(payload.get("ok", false)):
		match str(payload.get("reason", "")):
			"full":
				Toaster.toast("Your bank is full. Buy more slots or withdraw something.")
			"inventory_full":
				Toaster.toast("Bag is full — bank some items or free slots.")
			_:
				Toaster.toast("Could not claim loot.")
		return
	_apply_payload(payload)
	ClientState.inventory_changed.emit(payload)
	var moved: int = int(payload.get("moved", 0))
	if moved > 0:
		var dest: String = "bag" if request == &"chest.loot_take" else "bank"
		Toaster.toast("Moved %d item%s to your %s." % [
			moved, "" if moved == 1 else "s", dest
		])
	if close_after:
		hide()
	elif request == &"chest.loot_take" and moved <= 0 and not _pending.is_empty():
		Toaster.toast("Bag is full — bank some items or free slots.")
	elif request == &"chest.loot_bank" and moved <= 0 and not _pending.is_empty():
		Toaster.toast("Your bank is full. Buy more slots or withdraw something.")
