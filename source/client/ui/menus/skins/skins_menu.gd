extends MenuShell
## Skins shelf - every wardrobe body in every vault dye. Catalog is local (the
## dyes are code). Server only answers allowed + owned + equipped so Wear persists.
##
## Laid out like every Vault tab: the bodies listed on the left, the selected one
## large on the right, with its dyes as swatches under the preview. A dye is
## bought FOR ONE BODY, so each row's price is for that body in the dye picked.

const VaultStyle := preload("res://source/client/ui/menus/vault/vault_style.gd")
const VaultShelf := preload("res://source/client/ui/menus/vault/vault_shelf.gd")

const PREVIEW_BOX: float = 150.0
const PREVIEW_SCALE: float = 2.6
const SWATCH_PX: float = 26.0

var _bases: Array = []
var _dyes: Array = []
var _base_idx: int = 0
var _dye_idx: int = 0
var _equipped: int = 0
## Staff: may wear any pairing for testing. Everyone else wears what they bought,
## and a dye is bought FOR ONE BODY - "Obsidian" on the Scholar is not the same
## entitlement as "Obsidian" on the Knight, which is why _owned is keyed by the
## packed id rather than by dye.
var _allowed: bool = false
var _owned: Dictionary[int, bool] = {}
var _anim: StringName = &"idle"
## Set by a refresh after a purchase: re-read ownership but stay on the pairing
## the player just bought.
var _keep_selection: bool = false

var _shelf: VaultShelf
var _preview: AnimatedSprite2D
var _name_label: Label
var _dye_row: HFlowContainer
var _swatches: Array[Button] = []
var _blurb_label: Label
## SILENT unless something went wrong - it exists to say a Wear failed.
var _status_label: Label
var _action_button: Button
var _clear_button: Button
## The right-hand column, so the shell can drop its Buy button into it.
var _detail: VBoxContainer
var _action_row: HBoxContainer


func _ready() -> void:
	var embedded: bool = bool(get_meta(&"embedded", false))
	if not embedded:
		build_shell("Skins", null, true)
	_build_layout()
	_load_local_catalog()
	_build_swatches()
	_rebuild_shelf()
	_update_preview()
	visibility_changed.connect(func() -> void:
		if visible:
			_on_shown())
	_on_shown.call_deferred()


func _host() -> Control:
	return content if content != null else self


func _load_local_catalog() -> void:
	_bases = VaultSkins.base_roster()
	_dyes = VaultSkins.dye_roster()


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

	var preview_box: Control = Control.new()
	preview_box.custom_minimum_size = Vector2(PREVIEW_BOX, PREVIEW_BOX)
	preview_center.add_child(preview_box)

	_preview = AnimatedSprite2D.new()
	_preview.position = Vector2(PREVIEW_BOX * 0.5, PREVIEW_BOX * 0.5)
	_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_box.add_child(_preview)

	_name_label = VaultStyle.name_label()
	_detail.add_child(_name_label)

	# Every dye at once, as its own colour. Picking one recolours the preview and
	# re-prices every body on the left for that dye.
	_dye_row = HFlowContainer.new()
	_dye_row.add_theme_constant_override(&"h_separation", 4)
	_dye_row.add_theme_constant_override(&"v_separation", 4)
	_detail.add_child(_dye_row)

	_blurb_label = VaultStyle.note_label()
	_detail.add_child(_blurb_label)

	_status_label = VaultStyle.note_label()
	_status_label.visible = false
	_detail.add_child(_status_label)

	_action_row = VaultStyle.action_row()
	_detail.add_child(_action_row)

	_action_button = VaultStyle.action_button("Wear")
	_action_button.pressed.connect(_on_action_pressed)
	_action_row.add_child(_action_button)

	_clear_button = VaultStyle.action_button("Take off")
	_clear_button.pressed.connect(_on_clear_pressed)
	_action_row.add_child(_clear_button)


func _build_swatches() -> void:
	for child: Node in _dye_row.get_children():
		_dye_row.remove_child(child)
		child.queue_free()
	_swatches.clear()
	for i: int in _dyes.size():
		var dye: Dictionary = _dyes[i]
		var hex: String = str(dye.get("tint", ""))
		var tint: Color = Color(hex) if not hex.is_empty() else Color(0.5, 0.5, 0.5)
		var swatch: Button = Button.new()
		swatch.toggle_mode = true
		swatch.focus_mode = Control.FOCUS_NONE
		swatch.custom_minimum_size = Vector2(SWATCH_PX, SWATCH_PX)
		swatch.tooltip_text = str(dye.get("label", ""))
		var rest: StyleBoxFlat = PixelUI.flat_tile(tint, VaultStyle.LINE, 0, 0)
		var hover: StyleBoxFlat = PixelUI.flat_tile(tint, VaultStyle.INK, 0, 0)
		var picked: StyleBoxFlat = PixelUI.flat_tile(tint, VaultStyle.GOLD, 0, 0)
		picked.set_border_width_all(2)
		swatch.add_theme_stylebox_override(&"normal", rest)
		swatch.add_theme_stylebox_override(&"hover", hover)
		swatch.add_theme_stylebox_override(&"pressed", picked)
		swatch.add_theme_stylebox_override(&"hover_pressed", picked)
		swatch.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
		swatch.pressed.connect(_on_dye_picked.bind(i))
		_dye_row.add_child(swatch)
		_swatches.append(swatch)


func _on_shown() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"vault_skins.state", _on_state, {}, String(InstanceClient.current.name))


func _on_state(data: Dictionary) -> void:
	_allowed = bool(data.get("allowed", false))
	_owned.clear()
	for owned_v: Variant in data.get("owned", []):
		_owned[int(owned_v)] = true
	_equipped = int(data.get("equipped", 0))
	if _bases.is_empty() or _dyes.is_empty():
		_load_local_catalog()
		_build_swatches()
		_rebuild_shelf()
	# After a purchase, stay on the pairing just bought; on a fresh open, land on
	# what is worn.
	if not _keep_selection:
		_select_equipped()
	_keep_selection = false
	refresh_shelf()
	_update_preview()


func _select_equipped() -> void:
	if _equipped <= 0 or _bases.is_empty() or _dyes.is_empty():
		return
	var skin_id: int = VaultSkins.base_skin_id(_equipped)
	var style: int = VaultSkins.style_of(_equipped)
	for i: int in _bases.size():
		if int((_bases[i] as Dictionary).get("id", 0)) == skin_id:
			_base_idx = i
			break
	for i: int in _dyes.size():
		if int((_dyes[i] as Dictionary).get("style", 0)) == style:
			_dye_idx = i
			break


func _packed_for(base_index: int) -> int:
	if _bases.is_empty() or _dyes.is_empty():
		return 0
	var skin_id: int = int((_bases[base_index] as Dictionary).get("id", 0))
	var style: int = int((_dyes[_dye_idx] as Dictionary).get("style", 0))
	return VaultSkins.pack(skin_id, style)


func _packed() -> int:
	return _packed_for(_base_idx)


func _on_picked(index: int) -> void:
	_base_idx = index
	_update_preview()


func _on_dye_picked(index: int) -> void:
	_dye_idx = index
	# The dye changes what every body on the shelf costs and whether it is owned.
	refresh_shelf()
	_update_preview()


func _play_anim() -> void:
	if _preview == null or _preview.sprite_frames == null:
		return
	var frames: SpriteFrames = _preview.sprite_frames
	var anim: StringName = _anim
	if not frames.has_animation(anim):
		if frames.has_animation(&"idle"):
			anim = &"idle"
		else:
			var names: PackedStringArray = frames.get_animation_names()
			if names.is_empty():
				return
			anim = StringName(names[0])
	_preview.play(anim)


func _update_preview() -> void:
	if _bases.is_empty() or _dyes.is_empty():
		if _preview != null:
			VaultSkinVfx.apply_to_sprite(_preview, 0)
		_name_label.text = "—"
		_blurb_label.text = ""
		_say("No wardrobe skins in the registry.")
		_announce_selection("")
		_action_button.disabled = true
		_clear_button.visible = false
		return
	_clear_button.visible = true
	_shelf.select(_base_idx)
	for i: int in _swatches.size():
		_swatches[i].set_pressed_no_signal(i == _dye_idx)
	var vault_id: int = _packed()
	var skin_id: int = VaultSkins.base_skin_id(vault_id)
	var dye: Dictionary = _dyes[_dye_idx] as Dictionary
	var frames: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", skin_id) as SpriteFrames
	if _preview != null and frames != null:
		_preview.sprite_frames = frames
		VaultSkinVfx.apply_to_sprite(_preview, vault_id)
		_play_anim()
	_name_label.text = "%s  ·  %s" % [
		str((_bases[_base_idx] as Dictionary).get("name", "")),
		str(dye.get("label", "")),
	]
	_blurb_label.text = str(dye.get("blurb", ""))
	_announce_selection(VaultGrants.skin_token(vault_id))
	_say("")
	if vault_id == _equipped and vault_id > 0:
		_action_button.text = "Wearing"
		_action_button.disabled = true
	else:
		_action_button.text = "Wear"
		_action_button.disabled = not _can_wear(vault_id)


func _rebuild_shelf() -> void:
	var rows: Array = []
	for i: int in _bases.size():
		rows.append({"name": str((_bases[i] as Dictionary).get("name", "")), "tag": _tag_for(i)})
	_shelf.set_rows(rows)


func _tag_for(base_index: int) -> Dictionary:
	var vault_id: int = _packed_for(base_index)
	return VaultStyle.row_tag(
		self, VaultGrants.skin_token(vault_id),
		vault_id == _equipped and vault_id > 0, _owned.has(vault_id)
	)


## Re-read every row's price / Owned / Equipped tag for the dye now picked.
## Called by the Vault shell when its catalog arrives.
func refresh_shelf() -> void:
	if _shelf.row_count() != _bases.size():
		_rebuild_shelf()
		return
	var tags: Array = []
	for i: int in _bases.size():
		tags.append(_tag_for(i))
	_shelf.set_tags(tags)


## A purchase just settled: fetch ownership again so Wear unlocks without
## reopening the Vault, and keep the bought pairing selected.
func refresh_after_purchase() -> void:
	_keep_selection = true
	_on_shown()


## Whether THIS pairing may be worn. vault_skins.equip re-checks it server-side;
## a disabled button is a courtesy, not a lock.
func _can_wear(vault_id: int) -> bool:
	return _allowed or _owned.has(vault_id)


func _on_action_pressed() -> void:
	_equip(_packed())


func _on_clear_pressed() -> void:
	_equip(0)


func _equip(vault_id: int) -> void:
	if InstanceClient.current == null:
		return
	_action_button.disabled = true
	Client.request_data(
		&"vault_skins.equip",
		_on_equipped.bind(vault_id),
		{"vault_skin_id": vault_id, "skin_id": vault_id},
		String(InstanceClient.current.name)
	)


func _on_equipped(data: Dictionary, vault_id: int) -> void:
	if not data.get("ok", false):
		_say("Couldn't wear that (%s)." % str(data.get("reason", "error")))
		_update_preview()
		return
	_equipped = int(data.get("vault_skin_id", data.get("skin_id", vault_id)))
	var lp: Node = ClientState.local_player
	if lp != null and is_instance_valid(lp):
		lp.vault_skin_id = _equipped
	_update_preview()
	refresh_shelf()


## Tell the Vault shell what is highlighted, so its Buy button can price it.
## Walks up rather than assuming a parent: this menu also runs standalone
## (embedded == false), where there is no shell to talk to and this no-ops.
func _announce_selection(item_id: String) -> void:
	var host: Node = get_parent()
	while host != null and not host.has_method("set_selection"):
		host = host.get_parent()
	if host != null:
		host.set_selection(item_id)


## Whether the highlighted body + dye is already held. The Vault shell hides Buy on it.
func selection_owned() -> bool:
	return _owned.has(_packed())


## Re-emit the current selection. Called by the Vault shell when this tab
## becomes visible, so the Buy button is priced on the frame the tab opens
## instead of after a server round trip.
func announce_selection_now() -> void:
	_update_preview()


## Status text, hidden entirely when there is nothing to say.
func _say(message: String) -> void:
	if _status_label == null:
		return
	_status_label.text = message
	_status_label.visible = not message.is_empty()


## Host the Vault shell's Buy button directly above Wear / Take off, so price and
## purchase sit with Wear rather than in a far corner.
func mount_purchase_button(button: Button) -> void:
	if _detail == null or button == null or _action_row == null:
		return
	if button.get_parent() != null:
		button.get_parent().remove_child(button)
	_detail.add_child(button)
	_detail.move_child(button, _action_row.get_index())
