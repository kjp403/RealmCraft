extends Control
## Confirm walking out of a boss hunt before the clock runs out. Opened by
## clicking the BossHuntExit station on the arena spawn pad
## (open_menu_requested(&"boss_hunt_exit")). Leave → return to the Guild Hall and
## drop out of the contract (server boss_hunt.leave → recall); Stay → close.
##
## The confirm matters more here than in a dungeon: the contract is paid for, and
## the rest of the clock is forfeit. Same card shape as dungeon_exit_menu.

var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(_arg: Variant = null) -> void:
	_build_shell()

	var title: Label = Label.new()
	title.text = "Leave the hunt?"
	title.add_theme_font_size_override(&"font_size", 20)
	title.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)

	var body: Label = Label.new()
	body.text = "You'll return to the Guild Hall.\nThe rest of the contract is forfeit — the fee isn't refunded.\nEverything you've killed for is already in your Hunt Chest."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override(&"font_color", Color(0.8, 0.84, 0.9))
	_content.add_child(body)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 10)
	_content.add_child(buttons)
	buttons.add_child(_button("Leave", _on_leave))
	buttons.add_child(_button("Stay", hide))


func _on_leave() -> void:
	Client.request_data(
		&"boss_hunt.leave", func(_response: Dictionary) -> void: hide(),
		{}, String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _build_shell() -> void:
	for child: Node in get_children():
		child.queue_free()
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.05, 0.08, 0.7)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card: PanelContainer = PanelContainer.new()
	card.custom_minimum_size = Vector2(360, 0)
	center.add_child(card)

	var pad: MarginContainer = MarginContainer.new()
	pad.add_theme_constant_override(&"margin_left", 18)
	pad.add_theme_constant_override(&"margin_right", 18)
	pad.add_theme_constant_override(&"margin_top", 14)
	pad.add_theme_constant_override(&"margin_bottom", 14)
	card.add_child(pad)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 12)
	pad.add_child(_content)


func _button(text: String, callback: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(110, 40)
	b.pressed.connect(callback)
	return b
