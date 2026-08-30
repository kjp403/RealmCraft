class_name PartyHud
extends PanelContainer
## Persistent overworld party roster. Hidden when you are not in a party.
## Built in code (same as DungeonHud) so hud.tscn stays untouched.


var _content: VBoxContainer
var _leave_button: Button
var _names: Array = []
var _leader_peer: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END
	offset_left = 58.0
	offset_top = 56.0
	offset_right = 58.0
	offset_bottom = 56.0
	custom_minimum_size = Vector2(168, 0)
	add_theme_stylebox_override(&"panel", _make_panel_style())

	var margin: MarginContainer = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", 10)
	margin.add_theme_constant_override(&"margin_right", 10)
	margin.add_theme_constant_override(&"margin_top", 6)
	margin.add_theme_constant_override(&"margin_bottom", 6)
	add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 2)
	margin.add_child(_content)

	hide()
	Client.subscribe(&"party.roster", _on_roster)
	ClientState.local_player_ready.connect(func(_lp: LocalPlayer) -> void:
		_request_snapshot())
	_request_snapshot()


func _request_snapshot() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"party.get", _on_roster, {}, String(InstanceClient.current.name))


func _on_roster(payload: Dictionary) -> void:
	_names = payload.get("names", [])
	_leader_peer = int(payload.get("leader", 0))
	if _names.is_empty():
		hide()
		return
	_rebuild()
	show()


func _rebuild() -> void:
	for child: Node in _content.get_children():
		child.queue_free()

	var title: Label = Label.new()
	title.text = "Party"
	title.add_theme_font_size_override(&"font_size", 13)
	title.add_theme_color_override(&"font_color", Color(0.85, 0.92, 0.55))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(title)

	var my_id: int = int(ClientState.player_id)
	for entry_v: Variant in _names:
		if entry_v is not Dictionary:
			continue
		var entry: Dictionary = entry_v
		var row: Label = Label.new()
		var is_leader: bool = bool(entry.get("leader", false))
		var is_self: bool = int(entry.get("id", 0)) == my_id
		var name: String = str(entry.get("name", "Player"))
		if is_self:
			name = "You"
		row.text = ("%s %s" % ["★", name]) if is_leader else name
		row.add_theme_font_size_override(&"font_size", 12)
		row.add_theme_color_override(
			&"font_color",
			Color(1.0, 0.92, 0.45) if is_leader else Color(0.82, 0.88, 0.78)
		)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_child(row)

	_leave_button = Button.new()
	_leave_button.text = "Leave"
	_leave_button.custom_minimum_size = Vector2(0, 26)
	_leave_button.add_theme_font_size_override(&"font_size", 12)
	_leave_button.focus_mode = Control.FOCUS_NONE
	_leave_button.pressed.connect(_on_leave_pressed)
	_content.add_child(_leave_button)


func _on_leave_pressed() -> void:
	if InstanceClient.current == null:
		return
	_leave_button.disabled = true
	Client.request_data(&"party.leave", func(data: Dictionary) -> void:
		if not data.get("ok", false):
			Toaster.toast("Could not leave the party.")
			if _leave_button != null:
				_leave_button.disabled = false
		else:
			Toaster.toast("You left the party."),
		{}, String(InstanceClient.current.name))


func _make_panel_style() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.08, 0.6)
	box.set_border_width_all(1)
	box.border_color = Color(1.0, 1.0, 1.0, 0.07)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 5
	return box
