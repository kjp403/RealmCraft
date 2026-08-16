extends MenuShell
## Staff Skins shelf — every wardrobe body × every vault dye. Catalog is local
## (the dyes are code). Server only answers allowed + equipped so Wear persists.


const PREVIEW_BOX: float = 160.0
const PREVIEW_SCALE: float = 2.6
const ANIMS: Array[StringName] = [&"idle", &"run", &"death"]

var _bases: Array = []
var _dyes: Array = []
var _base_idx: int = 0
var _dye_idx: int = 0
var _equipped: int = 0
var _allowed: bool = false
var _anim: StringName = &"idle"

var _preview: AnimatedSprite2D
var _skin_label: Label
var _dye_label: Label
var _dye_swatch: ColorRect
var _blurb_label: Label
var _status_label: Label
var _action_button: Button
var _clear_button: Button
var _anim_buttons: Dictionary = {}


func _ready() -> void:
	var embedded: bool = bool(get_meta(&"embedded", false))
	if not embedded:
		build_shell("Skins", null, true)
	_build_layout()
	_load_local_catalog()
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
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 6)
	if content == null:
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_host().add_child(col)

	var hint: Label = Label.new()
	hint.text = "Pick a body, pick a dye, hit Wear. Faces, leather, and outlines stay."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(1, 1, 1, 0.65)
	hint.add_theme_font_size_override(&"font_size", 12)
	col.add_child(hint)

	var preview_center: CenterContainer = CenterContainer.new()
	preview_center.custom_minimum_size = Vector2(PREVIEW_BOX, PREVIEW_BOX)
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

	var skin_row: HBoxContainer = HBoxContainer.new()
	skin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	skin_row.add_theme_constant_override(&"separation", 10)
	col.add_child(skin_row)
	_skin_label = _add_nav(skin_row, _cycle_base)

	var dye_row: HBoxContainer = HBoxContainer.new()
	dye_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dye_row.add_theme_constant_override(&"separation", 10)
	col.add_child(dye_row)
	_dye_label = _add_nav(dye_row, _cycle_dye)
	_dye_swatch = ColorRect.new()
	_dye_swatch.custom_minimum_size = Vector2(18, 18)
	_dye_swatch.color = Color(0.94, 0.78, 0.29)
	dye_row.add_child(_dye_swatch)

	var anim_row: HBoxContainer = HBoxContainer.new()
	anim_row.alignment = BoxContainer.ALIGNMENT_CENTER
	anim_row.add_theme_constant_override(&"separation", 6)
	col.add_child(anim_row)
	for anim: StringName in ANIMS:
		var btn: Button = Button.new()
		btn.text = String(anim).capitalize()
		btn.toggle_mode = true
		btn.button_pressed = (anim == _anim)
		btn.custom_minimum_size = Vector2(0, 28)
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
	_action_button.text = "Wear"
	_action_button.custom_minimum_size = Vector2(0, 40)
	_action_button.add_theme_font_size_override(&"font_size", 18)
	_action_button.pressed.connect(_on_action_pressed)
	col.add_child(_action_button)

	_clear_button = Button.new()
	_clear_button.text = "Take off"
	_clear_button.custom_minimum_size = Vector2(0, 32)
	_clear_button.pressed.connect(_on_clear_pressed)
	col.add_child(_clear_button)


func _add_nav(row: HBoxContainer, cycler: Callable) -> Label:
	var prev: Button = Button.new()
	prev.text = "<"
	prev.custom_minimum_size = Vector2(44, 40)
	prev.add_theme_font_size_override(&"font_size", 22)
	prev.pressed.connect(cycler.bind(-1))
	row.add_child(prev)
	var label: Label = Label.new()
	label.custom_minimum_size = Vector2(200, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 16)
	row.add_child(label)
	var next: Button = Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(44, 40)
	next.add_theme_font_size_override(&"font_size", 22)
	next.pressed.connect(cycler.bind(1))
	row.add_child(next)
	return label


func _on_shown() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"vault_skins.state", _on_state, {}, String(InstanceClient.current.name))


func _on_state(data: Dictionary) -> void:
	_allowed = bool(data.get("allowed", false))
	_equipped = int(data.get("equipped", 0))
	if _bases.is_empty() or _dyes.is_empty():
		_load_local_catalog()
	_select_equipped()
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


func _packed() -> int:
	if _bases.is_empty() or _dyes.is_empty():
		return 0
	var skin_id: int = int((_bases[_base_idx] as Dictionary).get("id", 0))
	var style: int = int((_dyes[_dye_idx] as Dictionary).get("style", 0))
	return VaultSkins.pack(skin_id, style)


func _cycle_base(delta: int) -> void:
	if _bases.is_empty():
		return
	_base_idx = wrapi(_base_idx + delta, 0, _bases.size())
	_update_preview()


func _cycle_dye(delta: int) -> void:
	if _dyes.is_empty():
		return
	_dye_idx = wrapi(_dye_idx + delta, 0, _dyes.size())
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
	if _bases.is_empty() or _dyes.is_empty():
		if _preview != null:
			VaultSkinVfx.apply_to_sprite(_preview, 0)
		_skin_label.text = "—"
		_dye_label.text = "—"
		_blurb_label.text = ""
		_status_label.text = "No wardrobe skins in the registry."
		_action_button.disabled = true
		_clear_button.visible = false
		return
	_clear_button.visible = true
	var vault_id: int = _packed()
	var skin_id: int = VaultSkins.base_skin_id(vault_id)
	var dye: Dictionary = _dyes[_dye_idx] as Dictionary
	var frames: SpriteFrames = ContentRegistryHub.load_by_id(&"sprites", skin_id) as SpriteFrames
	if _preview != null and frames != null:
		_preview.sprite_frames = frames
		VaultSkinVfx.apply_to_sprite(_preview, vault_id)
		_play_anim()
	_skin_label.text = "%s  (%d/%d)" % [
		str((_bases[_base_idx] as Dictionary).get("name", "")),
		_base_idx + 1,
		_bases.size(),
	]
	_dye_label.text = "%s  (%d/%d)" % [
		str(dye.get("label", "")),
		_dye_idx + 1,
		_dyes.size(),
	]
	var hex: String = str(dye.get("tint", ""))
	if not hex.is_empty():
		_dye_swatch.color = Color(hex)
	_blurb_label.text = str(dye.get("blurb", ""))
	if vault_id == _equipped and vault_id > 0:
		_action_button.text = "Wearing"
		_action_button.disabled = true
		_status_label.text = "On your sprite in the live world. Leave the Vault — it stays."
	else:
		_action_button.text = "Wear"
		_action_button.disabled = not _allowed
		_status_label.text = "Wear writes this dye onto your character."


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
		_status_label.text = "Couldn't wear that (%s)." % str(data.get("reason", "error"))
		_update_preview()
		return
	_equipped = int(data.get("vault_skin_id", data.get("skin_id", vault_id)))
	var lp: Node = ClientState.local_player
	if lp != null and is_instance_valid(lp):
		lp.vault_skin_id = _equipped
	_update_preview()
