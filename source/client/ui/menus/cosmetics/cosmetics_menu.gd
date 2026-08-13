extends MenuShell
## Cosmetics wardrobe — browse the VFX cosmetics (auras, trails, halos, flourishes,
## death effects) and equip one. Opened from the Curator in the VFX Vault
## (CosmeticsInteraction → open_menu_requested(&"cosmetics")).
##
## STAFF ONLY for now, and the client is NOT what enforces that: cosmetics.state
## returns an empty roster to anyone below admin and cosmetics.equip refuses them, so
## a player who forces this menu open sees "nothing to show" and can change nothing.
## The empty-state copy below is deliberately incurious for that reason.
##
## Layout mirrors the skin wardrobe: big animated preview, prev/next cycler, and one
## action button. There is no Buy — nothing here is purchasable yet.

const PREVIEW_BOX: float = 200.0
const PREVIEW_SCALE: float = 1.6

var _cosmetics: Array[int] = []
var _idx: int = 0
var _equipped: int = 0
var _allowed: bool = false

var _preview: AnimatedSprite2D
var _name_label: Label
var _slot_label: Label
var _status_label: Label
var _action_button: Button
var _clear_button: Button


func _ready() -> void:
	build_shell("Cosmetics", null, true)
	_build_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			_on_shown())
	# The HUD instantiates this menu already-visible then calls show() (a no-op), so
	# visibility_changed does NOT fire on the first open — same quirk the skin
	# wardrobe documents. Load once here.
	_on_shown.call_deferred()


func _build_layout() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 10)
	content.add_child(col)

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
	_name_label.custom_minimum_size = Vector2(170, 44)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override(&"font_size", 18)
	nav.add_child(_name_label)

	var next: Button = Button.new()
	next.text = ">"
	next.custom_minimum_size = Vector2(44, 44)
	next.add_theme_font_size_override(&"font_size", 22)
	next.pressed.connect(_cycle.bind(1))
	nav.add_child(next)

	_slot_label = Label.new()
	_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_label.modulate = Color(1, 1, 1, 0.6)
	col.add_child(_slot_label)

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
	_clear_button.pressed.connect(_equip.bind(0))
	col.add_child(_clear_button)


# --- Data ---

func _on_shown() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"cosmetics.state", _on_state, {}, String(InstanceClient.current.name))


func _on_state(data: Dictionary) -> void:
	_allowed = bool(data.get("allowed", false))
	_cosmetics.clear()
	for id_v: Variant in data.get("cosmetics", []):
		_cosmetics.append(int(id_v))
	_equipped = int(data.get("equipped", 0))

	if _cosmetics.is_empty():
		_name_label.text = "—"
		_slot_label.text = ""
		_status_label.text = "Nothing to show."
		_action_button.disabled = true
		_action_button.text = "Unavailable"
		_clear_button.visible = false
		return

	_clear_button.visible = true
	var equipped_idx: int = _cosmetics.find(_equipped)
	_idx = equipped_idx if equipped_idx >= 0 else 0
	_update_preview()


# --- Browsing ---

func _cycle(delta: int) -> void:
	if _cosmetics.is_empty():
		return
	_idx = wrapi(_idx + delta, 0, _cosmetics.size())
	_update_preview()


func _update_preview() -> void:
	if _idx < 0 or _idx >= _cosmetics.size():
		return
	var id: int = _cosmetics[_idx]
	var frames: SpriteFrames = Cosmetics.frames(id)
	if _preview != null and frames != null:
		_preview.sprite_frames = frames
		if frames.has_animation(&"loop"):
			_preview.play(&"loop")
	_name_label.text = Cosmetics.display_name(id)
	_slot_label.text = String(Cosmetics.slot_of(id)).capitalize()
	_update_action()


func _update_action() -> void:
	if _idx < 0 or _idx >= _cosmetics.size():
		return
	var id: int = _cosmetics[_idx]
	if id == _equipped:
		_action_button.text = "Equipped"
		_action_button.disabled = true
		_status_label.text = "Currently worn."
	else:
		_action_button.text = "Equip"
		_action_button.disabled = not _allowed
		_status_label.text = "Unreleased — staff testing only."


func _on_action_pressed() -> void:
	if _idx < 0 or _idx >= _cosmetics.size():
		return
	_equip(_cosmetics[_idx])


func _equip(id: int) -> void:
	if InstanceClient.current == null:
		return
	_action_button.disabled = true
	Client.request_data(
		&"cosmetics.equip",
		_on_equipped.bind(id),
		{"cosmetic_id": id},
		String(InstanceClient.current.name)
	)


func _on_equipped(data: Dictionary, id: int) -> void:
	if not data.get("ok", false):
		_status_label.text = _equip_error(str(data.get("reason", "")))
		_update_action()
		return
	_equipped = id
	# Instant local feedback (Character._set_cosmetic_id); the server syncs
	# :cosmetic_id to everyone else.
	if ClientState.local_player != null and is_instance_valid(ClientState.local_player):
		ClientState.local_player.cosmetic_id = id
	_update_action()


func _equip_error(reason: String) -> String:
	match reason:
		"not_allowed":
			return "You can't use these."
		"unknown_cosmetic":
			return "That cosmetic no longer exists."
	return "Couldn't equip that."
