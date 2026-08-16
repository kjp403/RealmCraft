extends MenuShell
## Staff Skins shelf — prestige recolor + body-sprite VFX for every wearable
## sprite. Opened as the Skins tab of the Vault menu. Horizon cannot sell these.


const PREVIEW_BOX: float = 200.0
const PREVIEW_SCALE: float = 3.0
const ANIMS: Array[StringName] = [&"idle", &"run", &"death"]

var _wardrobe: Array = []
var _archives: Array = []
var _roster: Array = []
var _idx: int = 0
var _equipped: int = 0
var _allowed: bool = false
var _group: StringName = VaultSkins.GROUP_WARDROBE
var _anim: StringName = &"idle"

var _preview: AnimatedSprite2D
var _name_label: Label
var _blurb_label: Label
var _status_label: Label
var _action_button: Button
var _clear_button: Button
var _group_buttons: Dictionary = {}
var _anim_buttons: Dictionary = {}


func _ready() -> void:
	var embedded: bool = bool(get_meta(&"embedded", false))
	if not embedded:
		build_shell("Skins", null, true)
	_build_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			_on_shown())
	_on_shown.call_deferred()


func _host() -> Control:
	return content if content != null else self


func _build_layout() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 8)
	if content == null:
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host().add_child(col)

	var hint: Label = Label.new()
	hint.text = "Recolor + sprite VFX. Not in Horizon. Wear one, leave the Vault."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.65)
	hint.add_theme_font_size_override(&"font_size", 12)
	col.add_child(hint)

	var groups: HBoxContainer = HBoxContainer.new()
	groups.alignment = BoxContainer.ALIGNMENT_CENTER
	groups.add_theme_constant_override(&"separation", 4)
	col.add_child(groups)
	_add_group_tab(groups, VaultSkins.GROUP_WARDROBE, "Wardrobe")
	_add_group_tab(groups, VaultSkins.GROUP_ARCHIVES, "Archives")

	var preview_center: CenterContainer = CenterContainer.new()
	preview_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(preview_center)

	var preview_box: Control = Control.new()
	preview_box.custom_minimum_size = Vector2(PREVIEW_BOX, PREVIEW_BOX)
	preview_center.add_child(preview_box)

	_preview = AnimatedSprite2D.new()
	_preview.position = Vector2(PREVIEW_BOX * 0.5, PREVIEW_BOX * 0.5)
	_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_box.add_child(_preview)

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
	_name_label.custom_minimum_size = Vector2(220, 44)
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

	var anim_row: HBoxContainer = HBoxContainer.new()
	anim_row.alignment = BoxContainer.ALIGNMENT_CENTER
	anim_row.add_theme_constant_override(&"separation", 6)
	col.add_child(anim_row)
	for anim: StringName in ANIMS:
		var btn: Button = Button.new()
		btn.text = String(anim).capitalize()
		btn.toggle_mode = true
		btn.button_pressed = (anim == _anim)
		btn.custom_minimum_size = Vector2(0, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_set_anim.bind(anim))
		anim_row.add_child(btn)
		_anim_buttons[anim] = btn

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


func _add_group_tab(row: HBoxContainer, group: StringName, label: String) -> void:
	var b: Button = Button.new()
	b.text = label
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 30)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.button_pressed = (group == _group)
	b.pressed.connect(_select_group.bind(group))
	row.add_child(b)
	_group_buttons[group] = b


func _on_shown() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"vault_skins.state", _on_state, {}, String(InstanceClient.current.name))


func _on_state(data: Dictionary) -> void:
	_allowed = bool(data.get("allowed", false))
	_equipped = int(data.get("equipped", 0))
	_wardrobe = data.get("skins", [])
	_archives = data.get("archives", [])
	if _equipped > 0 and VaultSkins.group_of(_equipped) == VaultSkins.GROUP_ARCHIVES:
		_group = VaultSkins.GROUP_ARCHIVES
	_apply_group()


func _select_group(group: StringName) -> void:
	_group = group
	_apply_group()


func _apply_group() -> void:
	for key: StringName in _group_buttons:
		(_group_buttons[key] as Button).button_pressed = (key == _group)
	_roster = _archives if _group == VaultSkins.GROUP_ARCHIVES else _wardrobe
	var found: int = -1
	for i: int in _roster.size():
		if int((_roster[i] as Dictionary).get("id", 0)) == _equipped:
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


func _set_anim(anim: StringName) -> void:
	_anim = anim
	for key: StringName in _anim_buttons:
		(_anim_buttons[key] as Button).button_pressed = (key == anim)
	_play_anim()


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
	if _roster.is_empty():
		if _preview != null:
			VaultSkinVfx.apply_to_sprite(_preview, 0)
		_name_label.text = "—"
		_blurb_label.text = ""
		_status_label.text = "Nothing to show."
		_action_button.disabled = true
		_clear_button.visible = false
		return
	_clear_button.visible = true
	var entry: Dictionary = _current()
	var id: int = int(entry.get("id", 0))
	var frames: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", id) as SpriteFrames
	if _preview != null and frames != null:
		_preview.sprite_frames = frames
		VaultSkinVfx.apply_to_sprite(_preview, id)
		_play_anim()
	_name_label.text = "%s  (%d/%d)" % [str(entry.get("name", "")), _idx + 1, _roster.size()]
	_blurb_label.text = str(entry.get("blurb", ""))
	if id == _equipped:
		_action_button.text = "Wearing"
		_action_button.disabled = true
		_status_label.text = "Shown on your sprite in the live world."
	else:
		_action_button.text = "Wear"
		_action_button.disabled = not _allowed
		_status_label.text = "Staff testing — persists when you leave the Vault."


func _on_action_pressed() -> void:
	_equip(int(_current().get("id", 0)))


func _on_clear_pressed() -> void:
	_equip(0)


func _equip(skin_id: int) -> void:
	if InstanceClient.current == null:
		return
	_action_button.disabled = true
	Client.request_data(
		&"vault_skins.equip",
		_on_equipped.bind(skin_id),
		{"skin_id": skin_id},
		String(InstanceClient.current.name)
	)


func _on_equipped(data: Dictionary, skin_id: int) -> void:
	if not data.get("ok", false):
		_status_label.text = "Couldn't wear that."
		_update_preview()
		return
	_equipped = int(data.get("skin_id", skin_id))
	var lp: Node = ClientState.local_player
	if lp != null and is_instance_valid(lp):
		lp.vault_skin_id = _equipped
	_update_preview()
