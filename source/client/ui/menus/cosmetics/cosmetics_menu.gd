extends MenuShell
## Cosmetics wardrobe — browse, buy and equip VFX cosmetics. Opened from the Vault
## Keeper in the Guild House, or from the Curator in the staff VFX Vault
## (CosmeticsInteraction → open_menu_requested(&"cosmetics")).
##
## TABBED BY SLOT. One flat cycler through 20+ effects was unusable, so the roster
## is split into Auras / Trails / Halos / Flourishes / Departures / Weapon Skins
## (Cosmetics.SLOTS order). Each tab keeps its own browse position.
##
## Two INDEPENDENT equipped slots: a body effect and a weapon effect, so an aura and
## an Ascended weapon glow can be worn together. The Weapon Skins tab drives the
## second one; every other tab drives the first.
##
## THE CLIENT ENFORCES NOTHING. cosmetics.state decides what this caller may see -
## staff get the whole roster, everyone else gets what is for sale plus what they
## own - and cosmetics.equip refuses anything unowned. A forced-open menu with a
## hand-edited roster still changes nothing.
##
## The preview is a real [CosmeticVfx], the same node the world mounts, so a
## cosmetic upgraded to a scripted [CosmeticPreset] previews as what it actually
## is. A bare AnimatedSprite2D here would keep showing the old pre-rendered strip
## for those eleven, and the wardrobe would be advertising art the game no longer
## renders.

## Shrunk from 200 to make room for the Buy button that now sits above Equip.
## This tab carries a whole extra row the others do not - the six slot tabs -
## so it is the one with no slack, and at 200 the Equip button fell off the
## bottom of a 540px client. The preview still clears the walk radius by a
## wide margin (WALK_RADIUS is 26).
const PREVIEW_BOX: float = 140.0
const PREVIEW_SCALE: float = 1.6

## A trail preset renders from real movement and shows NOTHING standing still, so
## the preview walks in a small circle. Radial effects are left alone - orbiting an
## aura would just make the wardrobe look like it is drifting.
const WALK_RADIUS: float = 26.0
const WALK_PERIOD_S: float = 2.2

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
## Staff: may equip ANYTHING, owned or not. Ordinary players get their rights
## one cosmetic at a time, from _owned.
var _allowed: bool = false
var _owned: Dictionary[int, bool] = {}

var _preview: CosmeticVfx
## Carries [member _preview] around the walk circle. Separate from the preview node
## so the walk can be switched off per slot without touching the effect.
var _preview_pivot: Node2D
var _walking: bool = false
var _walk_elapsed: float = 0.0
var _tab_bar: HBoxContainer
var _tab_buttons: Dictionary = {}
var _name_label: Label
var _status_label: Label
var _action_button: Button
var _clear_button: Button
## The panel's own column, so the shell can drop its Buy button into it.
var _col: VBoxContainer


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
	_col = col
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 6)
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

	_preview_pivot = Node2D.new()
	_preview_pivot.position = _preview_home()
	_preview_pivot.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	preview_box.add_child(_preview_pivot)

	_preview = CosmeticVfx.new()
	# The world mounts this under a Character, which puts it behind the body. There
	# is no body here, so the preview must not sink behind the panel it sits on.
	_preview.z_index = 0
	_preview.preview_mode = true
	_preview_pivot.add_child(_preview)
	set_process(true)

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
	_owned.clear()
	for owned_v: Variant in data.get("owned", []):
		_owned[int(owned_v)] = true
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


## Where the preview sits when it is not walking. Slightly below centre: a preset
## draws from the FEET, so centring it puts most of the effect in the lower half
## of the box and the head-height layers off the top.
func _preview_home() -> Vector2:
	return Vector2(PREVIEW_BOX * 0.5, PREVIEW_BOX * 0.55)


## Walk the preview so trail presets have movement to sample. A circle rather than
## the back-and-forth the render tool uses: a wardrobe preview has no room to run,
## and a circle keeps the whole trail inside the box at every moment.
func _process(delta: float) -> void:
	if not _walking or _preview_pivot == null:
		return
	_walk_elapsed += delta
	var angle: float = _walk_elapsed * TAU / WALK_PERIOD_S
	# Squashed vertically, so the walk reads as movement across a floor rather
	# than as the effect being swung around on a string.
	var orbit: Vector2 = Vector2(cos(angle), sin(angle) * 0.5) * WALK_RADIUS
	_preview_pivot.position = _preview_home() + orbit


func _update_preview() -> void:
	var id: int = _current_id()
	if id == 0:
		return
	if _preview != null:
		# Lend the preview the player's own character, refreshed every browse
		# because it may not have existed when this menu was built. Chrono Echo
		# stamps the wearer's live sprite frame, so with nothing to read it
		# previews as an empty box — and borrowing the local player means the
		# wardrobe shows the effect on the skin the buyer is actually wearing.
		_preview.preview_wearer = ClientState.local_player
		_preview.apply(id)
	_walking = Cosmetics.slot_of(id) == &"trail"
	if not _walking and _preview_pivot != null:
		_preview_pivot.position = _preview_home()
	var ids: Array = _current_ids()
	_name_label.text = "%s  (%d/%d)" % [
		Cosmetics.display_name(id),
		int(_idx_by_slot.get(_slot, 0)) + 1,
		ids.size(),
	]
	_update_action()


func _update_action() -> void:
	var id: int = _current_id()
	_announce_selection(VaultGrants.cosmetic_token(id) if id != 0 else "")
	if id == 0:
		return
	if id == _equipped_for(_slot):
		_action_button.text = "Equipped"
		_action_button.disabled = true
		_status_label.text = "Currently worn."
	else:
		_action_button.text = "Equip"
		_action_button.disabled = not _can_wear(id)
		_status_label.text = _slot_blurb(_slot)


## Whether THIS cosmetic may be equipped. Staff may wear the whole roster for
## testing; everyone else may wear what they bought. The server re-checks exactly
## this in cosmetics.equip - a disabled button is a courtesy, not a lock.
func _can_wear(id: int) -> bool:
	return _allowed or _owned.has(id)


## What this slot actually does in the world, in the player's words.
##
## Replaces a flat "Unreleased — staff testing only." that was true when nothing
## was for sale and is now both wrong and off-putting on a thing with a price on
## it. Per slot rather than one line, because "it glows around you" and "it
## trails behind you" are the difference a buyer is choosing between.
func _slot_blurb(slot: StringName) -> String:
	match slot:
		&"aura":
			return "Glows around you wherever you go."
		&"trail":
			return "Leaves a wake behind you as you move."
		&"halo":
			return "Sits above your head, everywhere you go."
		&"weapon":
			return "Lights up any Ascended weapon you hold."
		&"flourish", &"departure":
			# Deliberately blunt. Nothing in the game plays these yet, and this
			# menu is the only place they render — so it says so rather than
			# implying they show up in the world. They are held out of the shop
			# for the same reason (PremiumCatalog.SLOTS_WITHOUT_A_TRIGGER).
			return "Preview only for now — nothing in the world plays this yet."
	return "Worn effect."


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
	_update_action()


## Host the Vault shell's Buy button directly above this panel's own action
## button, so price and purchase sit with the thing they act on.
func mount_purchase_button(button: Button) -> void:
	if _col == null or button == null or _action_button == null:
		return
	if button.get_parent() != null:
		button.get_parent().remove_child(button)
	_col.add_child(button)
	_col.move_child(button, _action_button.get_index())
