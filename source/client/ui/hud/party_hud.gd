class_name PartyHud
extends PanelContainer
## Persistent overworld party roster. Hidden when you are not in a party.
## Built in code (same as DungeonHud) so hud.tscn stays untouched.


## Card padding, on the stylebox rather than a MarginContainer (same as a toast).
const PAD_X: int = 8
const PAD_Y: int = 5

## Drag limits. The floor keeps a leader row ("★ Longestname") on one line; the
## ceiling stops the roster reaching the toast lane it already shares an edge with.
const MIN_WIDTH: float = 120.0
const MAX_WIDTH: float = 280.0

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
	# 148, not 168. At SIZE_TINY the longest realistic row ("★ Averyname") is well
	# under 100px, and the panel is SIZE_SHRINK on content anyway — the old minimum
	# was sized for 13px text and left a dead column on the right.
	custom_minimum_size = Vector2(148, 0)
	add_theme_stylebox_override(&"panel", _make_panel_style())

	_content = VBoxContainer.new()
	# 1, not 2. At SIZE_TINY a roster row is 10px tall, so 2px of separation is a
	# fifth of a line between every name — which is where the vertical slack in
	# this panel was coming from.
	_content.add_theme_constant_override(&"separation", 1)
	add_child(_content)

	# Width only, same reasoning as the quest tracker: the roster's height is the
	# number of people in the party, which is not the player's to drag. This one
	# grows RIGHTWARD (anchored top-left, GROW_DIRECTION_END), so the handle the
	# player gets is on the right edge.
	HudResizer.attach(
		self,
		&"party_hud",
		HudResizer.AXIS_X,
		HudResizer.SizeMode.MODE_MIN_SIZE,
		Vector2(MIN_WIDTH, 0.0),
		Vector2(MAX_WIDTH, 0.0)
	)

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

	var title: Label = PixelUI.hud_text("Party", PixelUI.SIZE_CAPTION, PixelUI.INK_GOLD)
	_content.add_child(title)

	var my_id: int = int(ClientState.player_id)
	for entry_v: Variant in _names:
		if entry_v is not Dictionary:
			continue
		var entry: Dictionary = entry_v
		var is_leader: bool = bool(entry.get("leader", false))
		var is_self: bool = int(entry.get("id", 0)) == my_id
		var name: String = str(entry.get("name", "Player"))
		if is_self:
			name = "You"
		var row: Label = PixelUI.hud_text(
			("%s %s" % ["★", name]) if is_leader else name,
			PixelUI.SIZE_TINY,
			PixelUI.INK_COIN if is_leader else PixelUI.INK
		)
		_content.add_child(row)

	_leave_button = Button.new()
	_leave_button.text = "Leave"
	# 18, not 26. The theme's carved Button frame carries a 10/6 content margin of
	# its own, so a 26px minimum on top of it was reserving roughly a full blank
	# line under the roster. flat_tile drops the frame; the height is now just the
	# 10px label plus its padding.
	_leave_button.custom_minimum_size = Vector2(0, 18)
	_leave_button.focus_mode = Control.FOCUS_NONE
	_leave_button.add_theme_stylebox_override(
		&"normal", PixelUI.flat_tile(Color(0.16, 0.17, 0.21, 0.85), Color(1, 1, 1, 0.10), 6, 2)
	)
	_leave_button.add_theme_stylebox_override(
		&"hover", PixelUI.flat_tile(Color(0.24, 0.20, 0.20, 0.92), Color(1, 0.55, 0.50, 0.35), 6, 2)
	)
	_leave_button.add_theme_stylebox_override(
		&"pressed", PixelUI.flat_tile(Color(0.12, 0.10, 0.10, 0.95), Color(1, 0.55, 0.50, 0.45), 6, 2)
	)
	_leave_button.add_theme_stylebox_override(
		&"focus", PixelUI.flat_tile(Color(0.16, 0.17, 0.21, 0.85), Color(1, 1, 1, 0.10), 6, 2)
	)
	_leave_button.add_theme_stylebox_override(
		&"disabled", PixelUI.flat_tile(Color(0.12, 0.13, 0.16, 0.70), Color(1, 1, 1, 0.06), 6, 2)
	)
	PixelUI.button_font(_leave_button, PixelUI.SIZE_TINY, PixelUI.INK_DIM)
	_leave_button.pressed.connect(_on_leave_pressed)
	# A 4px gap is the one deliberate piece of air in the panel: it separates the
	# roster (read-only) from the only control in it, so "Leave" cannot be
	# mistaken for another party member.
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(spacer)
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


## The shared overlay-card look — see [method PixelUI.hud_card]. Replaces a
## near-identical hand-rolled near-black + a 5px drop shadow that made the panel
## read a good deal larger than its contents.
func _make_panel_style() -> StyleBoxFlat:
	return PixelUI.hud_card(PAD_X, PAD_Y)
