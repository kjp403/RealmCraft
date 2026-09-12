extends MenuShell
## Staff Titles shelf — browse premium title VFX and wear one. Opened from the
## Curator in the VFX Vault (TitlesInteraction). Existing cosmetics wardrobe
## is a separate menu and is not changed here.


var _roster: Array = []
var _idx: int = 0
var _equipped: String = ""
## Staff: may wear ANY title on the shelf. Everyone else wears what they hold,
## which is _owned - bought here, or granted from the donation ladder.
var _allowed: bool = false
var _owned: Dictionary[String, bool] = {}

var _preview: Label
var _name_label: Label
var _blurb_label: Label
var _status_label: Label
var _action_button: Button
var _clear_button: Button
## The panel's own column, so the shell can drop its Buy button into it.
var _col: VBoxContainer


func _ready() -> void:
	var embedded: bool = bool(get_meta(&"embedded", false))
	if not embedded:
		build_shell("Titles", null, true)
	_build_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			_on_shown())
	_on_shown.call_deferred()


func _host() -> Control:
	return content if content != null else self


func _build_layout() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	_col = col
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 10)
	if content == null:
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host().add_child(col)

	var hint: Label = Label.new()
	hint.text = "Text VFX only. Wear one, leave the Vault, walk the live world."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.65)
	hint.add_theme_font_size_override(&"font_size", 12)
	col.add_child(hint)

	var preview_center: CenterContainer = CenterContainer.new()
	preview_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(preview_center)

	_preview = Label.new()
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview.add_theme_font_size_override(&"font_size", 22)
	_preview.custom_minimum_size = Vector2(280, 48)
	preview_center.add_child(_preview)

	var nav: HBoxContainer = HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override(&"separation", 10)
	col.add_child(nav)

	var prev: Button = Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(44, 44)
	prev.add_theme_font_size_override(&"font_size", 22)
	prev.pressed.connect(_cycle.bind(-1))
	nav.add_child(prev)

	_name_label = Label.new()
	_name_label.custom_minimum_size = Vector2(190, 44)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override(&"font_size", 16)
	nav.add_child(_name_label)

	var next: Button = Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(44, 44)
	next.add_theme_font_size_override(&"font_size", 22)
	next.pressed.connect(_cycle.bind(1))
	nav.add_child(next)

	_blurb_label = Label.new()
	_blurb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb_label.add_theme_font_size_override(&"font_size", 13)
	_blurb_label.modulate = Color(1, 1, 1, 0.8)
	col.add_child(_blurb_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.modulate = Color(1, 1, 1, 0.7)
	col.add_child(_status_label)

	_action_button = Button.new()
	_action_button.custom_minimum_size = Vector2(0, 44)
	_action_button.add_theme_font_size_override(&"font_size", 18)
	_action_button.pressed.connect(_on_action_pressed)
	col.add_child(_action_button)

	_clear_button = Button.new()
	_clear_button.text = "Take off"
	_clear_button.custom_minimum_size = Vector2(0, 34)
	_clear_button.pressed.connect(_on_clear_pressed)
	col.add_child(_clear_button)


func _on_shown() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"titles.state", _on_state, {}, String(InstanceClient.current.name))


func _on_state(data: Dictionary) -> void:
	_allowed = bool(data.get("allowed", false))
	_owned.clear()
	for owned_v: Variant in data.get("owned", []):
		# Lower-cased to match VaultGrants.title_token, which does the same on the
		# way into the entitlement list - "Gilded" and "gilded" are one title.
		_owned[str(owned_v).strip_edges().to_lower()] = true
	_equipped = str(data.get("equipped", ""))
	_roster = data.get("titles", [])
	if _roster.is_empty():
		_preview.text = "—"
		TitleVfx.apply_to_label(_preview, "")
		_name_label.text = "—"
		_blurb_label.text = ""
		_status_label.text = "Nothing to show."
		_announce_selection("")
		_action_button.disabled = true
		_clear_button.visible = false
		return
	_clear_button.visible = true
	var found: int = -1
	for i: int in _roster.size():
		if str((_roster[i] as Dictionary).get("name", "")) == _equipped:
			found = i
			break
	_idx = found if found >= 0 else 0
	_update_preview()


func _current() -> Dictionary:
	if _idx < 0 or _idx >= _roster.size():
		return {}
	return _roster[_idx]


func _cycle(delta: int) -> void:
	if _roster.is_empty():
		return
	_idx = wrapi(_idx + delta, 0, _roster.size())
	_update_preview()


func _update_preview() -> void:
	var entry: Dictionary = _current()
	var name: String = str(entry.get("name", ""))
	_preview.text = "— %s —" % name
	TitleVfx.apply_to_label(_preview, name)
	_name_label.text = "%s  (%d/%d)" % [name, _idx + 1, _roster.size()]
	_blurb_label.text = str(entry.get("blurb", ""))
	_announce_selection(VaultGrants.title_token(name))
	if name == _equipped:
		_action_button.text = "Wearing"
		_action_button.disabled = true
		_status_label.text = "Shown on your profile and in chat."
	else:
		_action_button.text = "Wear"
		_action_button.disabled = not _can_wear(name)
		_status_label.text = "Worn on your profile and in chat, anywhere in the world."


## Whether THIS title may be worn. titles.equip re-checks it server-side; a
## disabled button is a courtesy, not a lock.
func _can_wear(title: String) -> bool:
	return _allowed or _owned.has(title.strip_edges().to_lower())


func _on_action_pressed() -> void:
	_equip(str(_current().get("name", "")))


func _on_clear_pressed() -> void:
	_equip("")


func _equip(title: String) -> void:
	if InstanceClient.current == null:
		return
	_action_button.disabled = true
	Client.request_data(
		&"titles.equip",
		_on_equipped.bind(title),
		{"title": title},
		String(InstanceClient.current.name)
	)


func _on_equipped(data: Dictionary, title: String) -> void:
	if not data.get("ok", false):
		_status_label.text = "Couldn't wear that."
		_update_preview()
		return
	_equipped = str(data.get("title", title))
	_update_preview()


## Tell the Vault shell what is highlighted, so its Buy button can price it.
## Walks up rather than assuming a parent: this menu also runs standalone
## (embedded == false), where there is no shell to talk to and this no-ops.
func _announce_selection(item_id: String) -> void:
	var host: Node = get_parent()
	while host != null and not host.has_method("set_selection"):
		host = host.get_parent()
	if host != null:
		host.set_selection(item_id)


## Re-emit the current selection. Called by the Vault shell when this tab
## becomes visible, so the Buy button is priced on the frame the tab opens
## instead of after a server round trip.
func announce_selection_now() -> void:
	_update_preview()


## Host the Vault shell's Buy button directly above this panel's own action
## button, so price and purchase sit with the thing they act on.
func mount_purchase_button(button: Button) -> void:
	if _col == null or button == null or _action_button == null:
		return
	if button.get_parent() != null:
		button.get_parent().remove_child(button)
	_col.add_child(button)
	_col.move_child(button, _action_button.get_index())
