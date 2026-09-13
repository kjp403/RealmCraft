extends MenuShell
## Titles shelf - browse premium title VFX, buy one and wear it. The Vault's first
## tab, and also opened standalone from the Curator in the VFX Vault
## (TitlesInteraction).
##
## Laid out like every Vault tab: the whole shelf listed on the left with prices,
## the selected title shown large on the right with Buy and Wear under it.

const VaultStyle := preload("res://source/client/ui/menus/vault/vault_style.gd")
const VaultShelf := preload("res://source/client/ui/menus/vault/vault_shelf.gd")

var _roster: Array = []
var _idx: int = 0
var _equipped: String = ""
## Staff: may wear ANY title on the shelf. Everyone else wears what they hold,
## which is _owned - bought here, or granted from the donation ladder.
var _allowed: bool = false
var _owned: Dictionary[String, bool] = {}
## Set by a refresh after a purchase: re-read ownership but stay on the title the
## player just bought, so Wear is right under their cursor.
var _keep_selection: bool = false

var _shelf: VaultShelf
var _preview: Label
var _name_label: Label
var _blurb_label: Label
var _status_label: Label
var _action_button: Button
var _clear_button: Button
## The right-hand column, so the shell can drop its Buy button into it.
var _detail: VBoxContainer
var _action_row: HBoxContainer


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
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override(&"separation", 10)
	if content == null:
		body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host().add_child(body)

	_shelf = VaultShelf.new()
	_shelf.picked.connect(_on_picked)
	body.add_child(_shelf)

	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override(&"separation", 6)
	body.add_child(_detail)

	var stage: PanelContainer = PanelContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.add_theme_stylebox_override(&"panel", VaultStyle.stage_box())
	_detail.add_child(stage)

	var preview_center: CenterContainer = CenterContainer.new()
	stage.add_child(preview_center)

	_preview = Label.new()
	_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_preview.add_theme_font_size_override(&"font_size", 26)
	_preview.custom_minimum_size = Vector2(280, 56)
	preview_center.add_child(_preview)

	_name_label = VaultStyle.name_label()
	_detail.add_child(_name_label)

	_blurb_label = VaultStyle.note_label()
	_detail.add_child(_blurb_label)

	_status_label = VaultStyle.note_label()
	_detail.add_child(_status_label)

	_action_row = VaultStyle.action_row()
	_detail.add_child(_action_row)

	_action_button = VaultStyle.action_button("Wear")
	_action_button.pressed.connect(_on_action_pressed)
	_action_row.add_child(_action_button)

	_clear_button = VaultStyle.action_button("Take off")
	_clear_button.pressed.connect(_on_clear_pressed)
	_action_row.add_child(_clear_button)


func _on_shown() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"titles.state", _on_state, {}, String(InstanceClient.current.name))


func _on_state(data: Dictionary) -> void:
	var was_showing: String = str(_current().get("name", ""))
	_allowed = bool(data.get("allowed", false))
	_owned.clear()
	for owned_v: Variant in data.get("owned", []):
		# Lower-cased to match VaultGrants.title_token, which does the same on the
		# way into the entitlement list - "Gilded" and "gilded" are one title.
		_owned[str(owned_v).strip_edges().to_lower()] = true
	_equipped = str(data.get("equipped", ""))
	_roster = data.get("titles", [])
	if _roster.is_empty():
		_keep_selection = false
		_shelf.set_rows([])
		_preview.text = "—"
		TitleVfx.apply_to_label(_preview, "", true)
		_name_label.text = "—"
		_blurb_label.text = ""
		_status_label.text = "Nothing to show."
		_announce_selection("")
		_action_button.disabled = true
		_clear_button.visible = false
		return
	_clear_button.visible = true
	# After a purchase, stay put; on a fresh open, land on what is worn.
	var want: String = was_showing if _keep_selection else _equipped
	_keep_selection = false
	var found: int = -1
	for i: int in _roster.size():
		if str((_roster[i] as Dictionary).get("name", "")) == want:
			found = i
			break
	_idx = found if found >= 0 else 0
	var rows: Array = []
	for i: int in _roster.size():
		rows.append({"name": str((_roster[i] as Dictionary).get("name", "")), "tag": _tag_for(i)})
	_shelf.set_rows(rows)
	_update_preview()


func _current() -> Dictionary:
	if _idx < 0 or _idx >= _roster.size():
		return {}
	return _roster[_idx]


func _on_picked(index: int) -> void:
	_idx = index
	_update_preview()


func _update_preview() -> void:
	var entry: Dictionary = _current()
	var title: String = str(entry.get("name", ""))
	_shelf.select(_idx)
	_preview.text = "— %s —" % title
	# preview: this label is in a menu, nowhere near the camera and never
	# walking anywhere, so the emitter stacks must not cull themselves against
	# either - see TitleVfx.apply_to_label. Without it the shelf shows a
	# stripped-down version of the effect it is selling.
	TitleVfx.apply_to_label(_preview, title, true)
	_name_label.text = title
	_blurb_label.text = str(entry.get("blurb", ""))
	_announce_selection(VaultGrants.title_token(title))
	# Nothing to take off when nothing is worn.
	_clear_button.disabled = _equipped.is_empty()
	if title == _equipped:
		_action_button.text = "Wearing"
		_action_button.disabled = true
		_status_label.text = "Shown on your profile and in chat."
	else:
		_action_button.text = "Wear"
		_action_button.disabled = not _can_wear(title)
		_status_label.text = "Worn on your profile and in chat, anywhere in the world."


func _tag_for(index: int) -> Dictionary:
	var title: String = str((_roster[index] as Dictionary).get("name", ""))
	return VaultStyle.row_tag(
		self, VaultGrants.title_token(title), title == _equipped,
		_owned.has(title.strip_edges().to_lower())
	)


## Re-read every row's price / Owned / Equipped tag. Called by the Vault shell
## when its catalog arrives, and here after a Wear.
func refresh_shelf() -> void:
	var tags: Array = []
	for i: int in _roster.size():
		tags.append(_tag_for(i))
	_shelf.set_tags(tags)


## A purchase just settled: fetch ownership again so Wear unlocks without
## reopening the Vault, and keep the bought title selected.
func refresh_after_purchase() -> void:
	_keep_selection = true
	_on_shown()


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
	refresh_shelf()


## Tell the Vault shell what is highlighted, so its Buy button can price it.
## Walks up rather than assuming a parent: this menu also runs standalone
## (embedded == false), where there is no shell to talk to and this no-ops.
func _announce_selection(item_id: String) -> void:
	# Only the tab on screen may point Buy at something. Every tab fetches its
	# state when the Vault opens and again after each purchase; a hidden one
	# announcing on arrival re-targeted Buy at an item the buyer was not looking at.
	if not is_visible_in_tree():
		return
	var host: Node = get_parent()
	while host != null and not host.has_method("set_selection"):
		host = host.get_parent()
	if host != null:
		host.set_selection(item_id)


## Whether the highlighted title is already held. The Vault shell hides Buy on it.
func selection_owned() -> bool:
	return _owned.has(str(_current().get("name", "")).strip_edges().to_lower())


## Re-emit the current selection. Called by the Vault shell when this tab
## becomes visible, so the Buy button is priced on the frame the tab opens
## instead of after a server round trip.
func announce_selection_now() -> void:
	if not _roster.is_empty():
		_update_preview()


## Host the Vault shell's Buy button directly above Wear / Take off, so price and
## purchase sit with the thing they act on.
func mount_purchase_button(button: Button) -> void:
	if _detail == null or button == null or _action_row == null:
		return
	if button.get_parent() != null:
		button.get_parent().remove_child(button)
	_detail.add_child(button)
	_detail.move_child(button, _action_row.get_index())
