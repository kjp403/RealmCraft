extends PanelContainer

const PANEL_SIZE := Vector2(180.0, 262.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 52.0
const SLOT_SIZE := Vector2(38.0, 38.0)

const SLOT_RES_PATHS: Dictionary = {
	&"helmet": "res://source/common/gameplay/items/item_slot/slots/helmet.tres",
	&"weapon": "res://source/common/gameplay/items/item_slot/slots/weapon.tres",
	&"torso": "res://source/common/gameplay/items/item_slot/slots/torso.tres",
	&"ring": "res://source/common/gameplay/items/item_slot/slots/ring.tres",
	&"relic": "res://source/common/gameplay/items/item_slot/slots/relic.tres",
	&"boot": "res://source/common/gameplay/items/item_slot/slots/boot.tres",
}

const SLOT_LAYOUT: Array[StringName] = [
	&"", &"helmet", &"relic",
	&"weapon", &"torso", &"ring",
	&"", &"boot", &"",
]

const SLOT_LABELS: Dictionary = {
	&"helmet": "HEAD",
	&"relic": "RELIC",
	&"weapon": "WPN",
	&"torso": "BODY",
	&"ring": "RING",
	&"boot": "BOOTS",
}

@onready var close_button: Button = (
	$MarginContainer/MainColumn/Header/CloseButton
)
@onready var content: MarginContainer = (
	$MarginContainer/MainColumn/Content
)

var _slots: Dictionary[StringName, ItemSlot] = {}
var _slot_buttons: Dictionary[StringName, Button] = {}
var _slot_pixels: Dictionary[StringName, TextureRect] = {}
var _slot_group := ButtonGroup.new()

var _selected_slot: StringName = &""
var _selected_name: Label
var _selected_details: RichTextLabel
var _unequip_button: Button
var _unequip_request_pending := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	var title_label: Label = (
		$MarginContainer/MainColumn/Header/TitleLabel
	)
	var header_spacer: Control = (
		$MarginContainer/MainColumn/Header/HeaderSpacer
	)

	header_spacer.hide()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_theme_constant_override(&"margin_left", 6)
	content.add_theme_constant_override(&"margin_right", 6)

	for slot_key: StringName in SLOT_RES_PATHS:
		_slots[slot_key] = load(
			SLOT_RES_PATHS[slot_key]
		) as ItemSlot

	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()

	_build_equipment_layout()

	close_button.pressed.connect(hide)
	visibility_changed.connect(_on_visibility_changed)
	ClientState.local_player_ready.connect(_on_local_player_ready)

	var hud := get_parent() as Control
	if hud != null:
		hud.resized.connect(_place_panel)

	_hook_equipment()
	call_deferred(&"_place_panel")
	hide()


func _build_equipment_layout() -> void:
	var main_box := VBoxContainer.new()
	main_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_box.add_theme_constant_override(&"separation", 3)
	content.add_child(main_box)

	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_center.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	main_box.add_child(grid_center)

	var equipment_grid := GridContainer.new()
	equipment_grid.columns = 3
	equipment_grid.add_theme_constant_override(&"h_separation", 5)
	equipment_grid.add_theme_constant_override(&"v_separation", 5)
	grid_center.add_child(equipment_grid)

	for slot_key: StringName in SLOT_LAYOUT:
		if slot_key.is_empty():
			var spacer := Control.new()
			spacer.custom_minimum_size = SLOT_SIZE
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			equipment_grid.add_child(spacer)
		else:
			equipment_grid.add_child(_make_slot_button(slot_key))

	_selected_name = Label.new()
	_selected_name.text = "Select an equipment slot"
	_selected_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selected_name.add_theme_font_size_override(&"font_size", 11)
	main_box.add_child(_selected_name)

	_selected_details = RichTextLabel.new()
	_selected_details.bbcode_enabled = true
	_selected_details.fit_content = false
	_selected_details.custom_minimum_size = Vector2(0.0, 34.0)
	_selected_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_selected_details.scroll_active = true
	_selected_details.add_theme_font_size_override(&"normal_font_size", 9)
	_selected_details.add_theme_font_size_override(&"bold_font_size", 9)
	_selected_details.add_theme_font_size_override(&"italics_font_size", 9)
	_selected_details.add_theme_font_size_override(&"mono_font_size", 9)
	_selected_details.add_theme_constant_override(&"line_separation", 0)
	main_box.add_child(_selected_details)

	_unequip_button = Button.new()
	_unequip_button.text = "Unequip"
	_unequip_button.custom_minimum_size = Vector2(82.0, 22.0)
	_unequip_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_unequip_button.add_theme_font_size_override(&"font_size", 10)
	_unequip_button.disabled = true
	_unequip_button.pressed.connect(_on_unequip_pressed)
	main_box.add_child(_unequip_button)


func _make_slot_button(slot_key: StringName) -> Button:
	var button := Button.new()
	button.custom_minimum_size = SLOT_SIZE
	button.size = SLOT_SIZE
	button.clip_contents = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.toggle_mode = true
	button.button_group = _slot_group
	button.text = str(SLOT_LABELS.get(slot_key, ""))
	button.tooltip_text = _slot_display_name(slot_key)

	button.add_theme_font_size_override(&"font_size", 8)
	button.add_theme_color_override(
		&"font_color",
		Color(0.82, 0.76, 0.64, 0.9)
	)
	button.add_theme_color_override(
		&"font_hover_color",
		Color(1.0, 0.9, 0.62, 1.0)
	)

	_apply_slot_styles(button)
	button.pressed.connect(_on_slot_pressed.bind(slot_key))
	button.gui_input.connect(
		_on_slot_gui_input.bind(slot_key, button)
	)

	_slot_buttons[slot_key] = button
	_slot_pixels[slot_key] = PixelIcon.mount(button)

	return button


func _on_slot_gui_input(
	event: InputEvent,
	slot_key: StringName,
	button: Button
) -> void:
	if event is not InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton
	if (
		mouse_event.button_index == MOUSE_BUTTON_LEFT
		and mouse_event.pressed
	):
		button.button_pressed = true
		_on_slot_pressed(slot_key)
		button.accept_event()

		if mouse_event.double_click:
			_on_unequip_pressed()


func _apply_slot_styles(button: Button) -> void:
	var normal_style := _make_slot_style(
		Color(0.035, 0.03, 0.055, 0.72),
		Color(0.45, 0.28, 0.18, 0.8)
	)
	var hover_style := _make_slot_style(
		Color(0.10, 0.075, 0.08, 0.88),
		Color(0.86, 0.57, 0.25, 1.0)
	)
	var pressed_style := _make_slot_style(
		Color(0.16, 0.11, 0.07, 0.92),
		Color(1.0, 0.72, 0.30, 1.0)
	)

	button.add_theme_stylebox_override(&"normal", normal_style)
	button.add_theme_stylebox_override(&"hover", hover_style)
	button.add_theme_stylebox_override(&"pressed", pressed_style)


func _make_slot_style(
	background_color: Color,
	border_color: Color
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color

	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1

	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	return style


func _slot_display_name(slot_key: StringName) -> String:
	var slot_resource: ItemSlot = _slots.get(slot_key, null)
	if slot_resource != null:
		return slot_resource.display_name

	return String(slot_key).capitalize()


func _place_panel() -> void:
	var hud := get_parent() as Control
	if hud == null:
		return

	size = PANEL_SIZE
	position = Vector2(
		hud.size.x - PANEL_SIZE.x - RIGHT_MARGIN,
		hud.size.y - PANEL_SIZE.y - BOTTOM_CLEARANCE
	)


func _on_visibility_changed() -> void:
	if visible:
		_hook_equipment()
		_refresh()


func _on_local_player_ready(_local_player: LocalPlayer) -> void:
	_hook_equipment()

	if visible:
		_refresh()


func _hook_equipment() -> void:
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
	if visible:
		_refresh()


func _refresh() -> void:
	var local_player: Player = ClientState.local_player
	if local_player == null:
		return

	var values: Dictionary = (
		local_player.equipment_component.slots.values
	)

	for slot_key: StringName in _slot_buttons:
		var item: Item = _get_slot_item(slot_key, values)
		var button: Button = _slot_buttons[slot_key]
		var pixel: TextureRect = _slot_pixels[slot_key]

		if item != null:
			button.text = ""
			PixelIcon.set_art(pixel, item.item_icon)
			pixel.modulate = Color.WHITE
			button.tooltip_text = str(item.item_name)
		else:
			var slot_resource: ItemSlot = _slots.get(
				slot_key,
				null
			)

			button.text = str(SLOT_LABELS.get(slot_key, ""))

			PixelIcon.set_art(pixel, null)
			pixel.modulate = Color.WHITE
			button.tooltip_text = _slot_display_name(slot_key)

	_render_selected_slot()


func _get_slot_item(
	slot_key: StringName,
	values: Dictionary
) -> Item:
	var item_id: int = int(values.get(slot_key, 0))
	if item_id <= 0:
		return null

	return ContentRegistryHub.load_by_id(
		&"items",
		item_id
	) as Item


func _on_slot_pressed(slot_key: StringName) -> void:
	_selected_slot = slot_key
	_render_selected_slot()


func _render_selected_slot() -> void:
	if _selected_slot.is_empty():
		_selected_name.text = "Select an equipment slot"
		_selected_details.text = ""
		_unequip_button.disabled = true
		return

	var local_player: Player = ClientState.local_player
	if local_player == null:
		return

	var item: Item = _get_slot_item(
		_selected_slot,
		local_player.equipment_component.slots.values
	)

	if item == null:
		_selected_name.text = (
			"Empty " + _slot_display_name(_selected_slot)
		)
		_selected_details.text = ""
		_unequip_button.disabled = true
		return

	_selected_name.text = str(item.item_name)
	# Compact panels do not need a full blank line between stats and flavor.
	_selected_details.text = ItemTooltip.body(item).replace("\n\n", "\n")
	_unequip_button.disabled = false


func _on_unequip_pressed() -> void:
	if _selected_slot.is_empty() or _unequip_request_pending:
		return

	if InstanceClient.current == null:
		return

	var local_player: Player = ClientState.local_player
	if local_player == null:
		return

	var item: Item = _get_slot_item(
		_selected_slot,
		local_player.equipment_component.slots.values
	)
	if item == null:
		return

	_unequip_request_pending = true
	_unequip_button.disabled = true

	var result: Array = await Client.request_data_await(
		&"item.unequip",
		{"slot": _selected_slot},
		InstanceClient.current.name
	)
	_unequip_request_pending = false

	if result.size() < 2 or result[1] != OK:
		Toaster.toast("The item could not be unequipped.")
		_render_selected_slot()
		return

	var payload: Dictionary = (
		result[0] if result[0] is Dictionary else {}
	)

	if str(payload.get("reason", "")) == "in_combat":
		Toaster.toast("Armor cannot be changed during combat.")
		_render_selected_slot()
		return

	if not bool(payload.get("ok", false)):
		Toaster.toast("The item could not be unequipped.")
		_render_selected_slot()
		return

	_refresh()
