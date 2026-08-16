extends MenuShell
## Cosmetics wardrobe — browse and equip VFX cosmetics. Opened from the Curator in
## the VFX Vault (CosmeticsInteraction → open_menu_requested(&"cosmetics")).
##
## TABBED BY SLOT. One flat cycler through 20+ effects was unusable, so the roster
## is split into Auras / Trails / Halos / Flourishes / Departures / Weapon Skins
## (Cosmetics.SLOTS order). Each tab keeps its own browse position.
##
## Two INDEPENDENT equipped slots: a body effect and a weapon effect, so an aura and
## an Ascended weapon glow can be worn together. The Weapon Skins tab drives the
## second one; every other tab drives the first.
##
## STAFF ONLY, and the client does not enforce it: cosmetics.state returns an empty
## roster to non-staff and cosmetics.equip refuses them, so a forced-open menu shows
## nothing and changes nothing.

const PREVIEW_BOX: float = 200.0
const PREVIEW_SCALE: float = 1.6

## Tab labels, keyed by slot. Anything not listed falls back to a capitalized slug.
const SLOT_LABELS: Dictionary = {
	&"aura": "Auras",
	&"trail": "Trails",
	&"halo": "Halos",
	&"flourish": "Flourishes",
	&"departure": "Departures",
	&"weapon": "Weapon Skins",
}

## slot -> Array[int] of cosmetic ids in that tab.
var _by_slot: Dictionary = {}
## slot -> browse index, so switching tabs returns you where you were.
var _idx_by_slot: Dictionary = {}
var _slots: Array[StringName] = []
var _slot: StringName = &""

var _equipped_body: int = 0
var _equipped_weapon: int = 0
var _allowed: bool = false

var _preview: AnimatedSprite2D
var _tab_bar: HBoxContainer
var _tab_buttons: Dictionary = {}
var _name_label: Label
var _status_label: Label
var _action_button: Button
var _clear_button: Button


func _ready() -> void:
	var embedded: bool = bool(get_meta(&"embedded", false))
	if not embedded:
		build_shell("Cosmetics", null, true)
	_build_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			_on_shown())
	# The HUD instantiates this menu already-visible then calls show() (a no-op), so
	# visibility_changed does NOT fire on the first open — same quirk the skin
	# wardrobe documents.
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

	# Tab strip. Populated in _rebuild_tabs once the roster arrives — building it
	# from the response rather than a hardcoded list means an empty slot (or a new
	# one) needs no change here.
	_tab_bar = HBoxContainer.new()
	_tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_bar.add_theme_constant_override(&"separation", 4)
	col.add_child(_tab_bar)

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
	_name_label.custom_minimum_size = Vector2(190, 44)
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


# --- Data ---

func _on_shown() -> void:
	if InstanceClient.current == null:
		return
	Client.request_data(&"cosmetics.state", _on_state, {}, String(InstanceClient.current.name))


func _on_state(data: Dictionary) -> void:
	_allowed = bool(data.get("allowed", false))
	_equipped_body = int(data.get("equipped", 0))
	_equipped_weapon = int(data.get("equipped_weapon", 0))

	_by_slot.clear()
	_slots.clear()
	for id_v: Variant in data.get("cosmetics", []):
		var id: int = int(id_v)
		var slot: StringName = Cosmetics.slot_of(id)
		if not _by_slot.has(slot):
			_by_slot[slot] = []
		(_by_slot[slot] as Array).append(id)

	# Keep Cosmetics.SLOTS order, skipping slots with no content.
	for slot: StringName in Cosmetics.SLOTS:
		if _by_slot.has(slot):
			_slots.append(slot)

	_rebuild_tabs()
	if _slots.is_empty():
		_name_label.text = "—"
		_status_label.text = "Nothing to show."
		_action_button.text = "Unavailable"
		_action_button.disabled = true
		_clear_button.visible = false
		return
	_clear_button.visible = true
	# Open on the tab holding whatever is already equipped, else the first tab.
	var want: StringName = _slots[0]
	for slot: StringName in _slots:
		var ids: Array = _by_slot[slot]
		if ids.has(_equipped_body) or ids.has(_equipped_weapon):
			want = slot
			break
	_select_slot(want)


func _rebuild_tabs() -> void:
	for child: Node in _tab_bar.get_children():
		child.queue_free()
	_tab_buttons.clear()
	for slot: StringName in _slots:
		var b: Button = Button.new()
		b.text = String(SLOT_LABELS.get(slot, String(slot).capitalize()))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 30)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_select_slot.bind(slot))
		_tab_bar.add_child(b)
		_tab_buttons[slot] = b


func _select_slot(slot: StringName) -> void:
	_slot = slot
	for key: StringName in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = (key == slot)
	if not _idx_by_slot.has(slot):
		# First visit: land on the equipped entry for this tab if there is one.
		var ids: Array = _by_slot.get(slot, [])
		var equipped: int = _equipped_for(slot)
		var found: int = ids.find(equipped)
		_idx_by_slot[slot] = found if found >= 0 else 0
	_update_preview()


## Which equipped id this tab drives — the weapon tab has its own slot.
func _equipped_for(slot: StringName) -> int:
	return _equipped_weapon if slot == &"weapon" else _equipped_body


# --- Browsing ---

func _current_ids() -> Array:
	return _by_slot.get(_slot, [])


func _current_id() -> int:
	var ids: Array = _current_ids()
	var i: int = int(_idx_by_slot.get(_slot, 0))
	return int(ids[i]) if i >= 0 and i < ids.size() else 0


func _cycle(delta: int) -> void:
	var ids: Array = _current_ids()
	if ids.is_empty():
		return
	_idx_by_slot[_slot] = wrapi(int(_idx_by_slot.get(_slot, 0)) + delta, 0, ids.size())
	_update_preview()


func _update_preview() -> void:
	var id: int = _current_id()
	if id == 0:
		return
	var frames: SpriteFrames = Cosmetics.frames(id)
	if _preview != null and frames != null:
		_preview.sprite_frames = frames
		if frames.has_animation(&"loop"):
			_preview.play(&"loop")
	var ids: Array = _current_ids()
	_name_label.text = "%s  (%d/%d)" % [
		Cosmetics.display_name(id),
		int(_idx_by_slot.get(_slot, 0)) + 1,
		ids.size(),
	]
	_update_action()


func _update_action() -> void:
	var id: int = _current_id()
	if id == 0:
		return
	if id == _equipped_for(_slot):
		_action_button.text = "Equipped"
		_action_button.disabled = true
		_status_label.text = "Currently worn."
	else:
		_action_button.text = "Equip"
		_action_button.disabled = not _allowed
		_status_label.text = (
			"Lights up any Ascended weapon you hold." if _slot == &"weapon"
			else "Unreleased — staff testing only."
		)


func _on_action_pressed() -> void:
	var id: int = _current_id()
	if id != 0:
		_equip(id, _slot)


## Clearing sends the slot explicitly — id 0 has no slot of its own, so the server
## cannot infer which one to clear.
func _on_clear_pressed() -> void:
	_equip(0, _slot)


func _equip(id: int, slot: StringName) -> void:
	if InstanceClient.current == null:
		return
	_action_button.disabled = true
	Client.request_data(
		&"cosmetics.equip",
		_on_equipped.bind(id, slot),
		{"cosmetic_id": id, "slot": String(slot)},
		String(InstanceClient.current.name)
	)


func _on_equipped(data: Dictionary, id: int, slot: StringName) -> void:
	if not data.get("ok", false):
		_status_label.text = _equip_error(str(data.get("reason", "")))
		_update_action()
		return
	var lp: Node = ClientState.local_player
	if slot == &"weapon":
		_equipped_weapon = id
		if lp != null and is_instance_valid(lp):
			lp.weapon_cosmetic_id = id
	else:
		_equipped_body = id
		if lp != null and is_instance_valid(lp):
			lp.cosmetic_id = id
	_update_action()


func _equip_error(reason: String) -> String:
	match reason:
		"not_allowed":
			return "You can't use these."
		"unknown_cosmetic":
			return "That cosmetic no longer exists."
	return "Couldn't equip that."
