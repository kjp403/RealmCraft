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
const STAGE_BG: Color = Color(0.035, 0.042, 0.06, 0.94)

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
	&"pet": "Pets",
	&"pet_reactive": "Reactive Pets",
}

## A SECTION is a tab that is not a slot of its own. The Pets tab splits the one
## "pet" slot into two shelves - pets with themed reactions to what their owner
## is doing, and the rest - so the ones that do the most get a shelf of their
## own. Every section maps back to the real slot it equips into; see _real_slot.
const SECTION_REACTIVE_PETS: StringName = &"pet_reactive"

## SLOT FILTER, set by whoever embeds this menu (before it enters the tree) as the
## "slots" meta: an Array of slot names to show, or unset for every slot EXCEPT the
## ones listed in "exclude_slots". The Vault embeds two copies - Cosmetics without
## pets, and Pets with only pets - so pets get a shelf of their own instead of
## being a seventh tab crammed into a row with no room for it.
var _only_slots: Array = []
var _exclude_slots: Array = []

## Pets preview WALK, THEN STOP, on a loop: a pet's whole appeal is that it
## follows you AND does something when you stand still, and a preview that only
## walks (or only stands) sells half of it.
const PET_WALK_S: float = 2.6
const PET_STAND_S: float = 3.4

## slot -> Array[int] of cosmetic ids in that tab.
var _by_slot: Dictionary = {}
## slot -> browse index, so switching tabs returns you where you were.
var _idx_by_slot: Dictionary = {}
var _slots: Array[StringName] = []
var _slot: StringName = &""

## slot -> equipped id, straight from cosmetics.state. Replaces the two scalars
## this used to keep: every slot is independent now, and a halo, an aura and a
## trail are worn at the same time.
var _equipped: Dictionary = {}
## Staff: may equip ANYTHING, owned or not. Ordinary players get their rights
## one cosmetic at a time, from _owned.
var _allowed: bool = false
var _owned: Dictionary[int, bool] = {}

## slot -> the CosmeticVfx drawing that slot in the preview. One node per slot,
## all mounted on the same pivot, so the box shows a COMBINATION rather than the
## one effect being browsed.
var _preview_vfx: Dictionary = {}
## slot -> the id being tried on. Seeded from what the player actually wears and
## then changed by browsing - THIS MENU ONLY. Nothing here is sent anywhere: the
## point is to see how a halo sits over an aura before spending on either.
var _try_on: Dictionary = {}
## Says so, in the corner of the stage, whenever the mannequin is wearing
## something the player is not.
var _try_on_label: Label
## The buyer's OWN character, drawn under the effect. Not decoration: an aura is
## sized and positioned against a body, and a trail is drawn from where one has
## been, so an effect floating in an empty box is not the thing being sold.
var _body: AnimatedSprite2D
## The buyer's worn title, floating over the preview the way it floats over their
## head in the world. Inside the preview box on purpose - this tab carries the
## six slot tabs and has no vertical budget for another row (see PREVIEW_BOX).
##
## NOT _title_label: MenuShell already owns that name for the window's own
## heading, and shadowing it is a parse error that takes the whole menu down.
var _wearer_title: Label
## Carries the whole preview - body, title and every slot's effect - around the
## walk circle. Separate from the effect nodes so the walk can be switched off
## per tab without touching what is being worn.
var _preview_pivot: Node2D
## The preview draws in its own viewport, shown on the stage through this rect -
## see _build_layout for why it cannot draw on the panel directly.
var _preview_view: TextureRect
var _preview_viewport: SubViewport
var _preview_center: CenterContainer
var _preview_box: Control
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
	_only_slots = get_meta(&"slots", [])
	_exclude_slots = get_meta(&"exclude_slots", [])
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

	# A STAGE, NOT A TRANSPARENT GAP. The Vault is a fullscreen MenuShell, which
	# drops the card frame on purpose and leaves only a half-alpha dim - so
	# before this, a 1.6x pixel character and a particle effect were drawn over
	# the lit Guild House, its NPCs and the leaderboard text. The preview was
	# there and simply could not be seen, worst of all when the buyer's own
	# character happened to be standing behind it.
	#
	# Clipped, so a wide trail cannot paint over the Buy button underneath.
	var stage: PanelContainer = PanelContainer.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.add_theme_stylebox_override(&"panel", _stage_style())
	col.add_child(stage)

	# THE PREVIEW RENDERS IN ITS OWN VIEWPORT. The HUD hosts every menu at
	# z_index 100 (hud.gd), and a pet's body - like several trail layers - is
	# top_level, which drops that inherited z. Drawn straight onto this panel the
	# pet sat at z 2, UNDER the stage, and showed only as a shadow through it. A
	# top_level node cannot leave its viewport's canvas, so inside one the host's
	# z stops mattering.
	#
	# OPAQUE, with the stage colour painted in: an additive glow blended onto a
	# transparent target keeps alpha 0 and vanishes once composited.
	_preview_view = TextureRect.new()
	_preview_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_view.stretch_mode = TextureRect.STRETCH_SCALE
	_preview_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_preview_view)

	_preview_viewport = SubViewport.new()
	_preview_viewport.transparent_bg = false
	_preview_viewport.gui_disable_input = true
	_preview_viewport.size_2d_override_stretch = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_view.add_child(_preview_viewport)
	_preview_view.texture = _preview_viewport.get_texture()

	# At the lowest z there is, so a companion passing BEHIND its owner (z -7)
	# still draws in front of the backdrop.
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(STAGE_BG, 1.0)
	backdrop.size = Vector2(4096, 4096)
	backdrop.z_index = RenderingServer.CANVAS_ITEM_Z_MIN
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_viewport.add_child(backdrop)

	# Still laid out on the stage: it holds the title and try-on labels, and its
	# position is where the preview is centred (see _preview_box_origin).
	_preview_center = CenterContainer.new()
	_preview_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_preview_center)

	var preview_box: Control = Control.new()
	preview_box.custom_minimum_size = Vector2(PREVIEW_BOX, PREVIEW_BOX)
	preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_center.add_child(preview_box)
	_preview_box = preview_box

	# The viewport covers the stage's 1px border; redraw it on top. A bare Panel
	# has no minimum size, so it costs this tab none of its height.
	var border: Panel = Panel.new()
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame: StyleBoxFlat = _stage_style()
	frame.draw_center = false
	border.add_theme_stylebox_override(&"panel", frame)
	stage.add_child(border)

	_preview_pivot = Node2D.new()
	_preview_pivot.position = _preview_home()
	_preview_pivot.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	_preview_viewport.add_child(_preview_pivot)

	# One node per slot, built up front and left hidden until something is put in
	# it. The world mounts these under a Character, which puts them behind the
	# body at z_index -1; a NEGATIVE z here would sink the effect behind the
	# panel it sits on, so the same order is built the other way up: effects at
	# 0, body above them.
	for slot: StringName in Cosmetics.SLOTS:
		var vfx: CosmeticVfx = CosmeticVfx.new()
		vfx.z_index = 0
		vfx.preview_mode = true
		vfx.visible = false
		_preview_pivot.add_child(vfx)
		_preview_vfx[slot] = vfx

	# Rides the pivot, so a trail preset is drawn from a body that is actually
	# moving rather than trailing off empty space.
	_body = AnimatedSprite2D.new()
	_body.z_index = 1
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# The SAME offset the character scene uses (see render_cosmetic_presets's
	# stand-in): it puts the body's FEET on the node origin. Every preset is
	# anchored to the feet, so without this the body hangs half a torso low and
	# an aura meant to ring the knees rings the head.
	_body.offset = Vector2(0, -30)
	_preview_pivot.add_child(_body)

	# Above the box, not above the column: a row here would push Equip off the
	# bottom of a 540px client, which is the same 70px trap documented in
	# vault_menu._build_purchase_bar. z_index clears the body, which sits at 1.
	var title_center: CenterContainer = CenterContainer.new()
	title_center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title_center.custom_minimum_size = Vector2(PREVIEW_BOX, 20)
	title_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_center.z_index = 2
	preview_box.add_child(title_center)

	_wearer_title = Label.new()
	_wearer_title.add_theme_font_size_override(&"font_size", 13)
	title_center.add_child(_wearer_title)

	# Bottom-left of the stage, so it costs the column ZERO height - this tab has
	# none to give. Only ever visible when the mannequin and the player disagree.
	_try_on_label = Label.new()
	_try_on_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_try_on_label.offset_left = 6
	_try_on_label.offset_top = -20
	_try_on_label.add_theme_font_size_override(&"font_size", 11)
	_try_on_label.modulate = Color(1, 1, 1, 0.55)
	_try_on_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_try_on_label.z_index = 2
	_try_on_label.visible = false
	preview_box.add_child(_try_on_label)

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


## Near-opaque, because the point is to take the world out from behind the
## effect. Not fully opaque: a sliver of the room still shows through, which
## keeps the menu feeling like it is over the Guild House rather than a separate
## screen - the same call the fullscreen shell makes with its dim.
func _stage_style() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = STAGE_BG
	box.border_color = Color(0.38, 0.34, 0.28, 0.9)
	box.set_border_width_all(1)
	box.set_corner_radius_all(0)
	# ZERO margins. This tab has no vertical slack - six slot tabs, a Buy button,
	# Equip and Take off inside 540px - and 4px of padding top and bottom was
	# enough to push Take off off the bottom edge. The stage already expands to
	# fill whatever the column has spare.
	box.set_content_margin_all(0)
	return box


# --- Data ---

func _on_shown() -> void:
	# Before the request, not after: the body and title come from the local
	# player and need no server round trip, so the preview is never empty while
	# the roster is in flight.
	_refresh_wearer()
	if InstanceClient.current == null:
		return
	Client.request_data(&"cosmetics.state", _on_state, {}, String(InstanceClient.current.name))


func _on_state(data: Dictionary) -> void:
	_allowed = bool(data.get("allowed", false))
	_owned.clear()
	for owned_v: Variant in data.get("owned", []):
		_owned[int(owned_v)] = true
	_equipped.clear()
	for slot_key: Variant in (data.get("slots", {}) as Dictionary):
		var worn: int = int((data.get("slots", {}) as Dictionary)[slot_key])
		if worn > 0:
			_equipped[StringName(str(slot_key))] = worn
	# The state fetch runs on every open, so this is also the reset: the
	# mannequin starts each visit dressed as the player is.
	_reset_try_on()

	_by_slot.clear()
	_slots.clear()
	for id_v: Variant in data.get("cosmetics", []):
		var id: int = int(id_v)
		var slot: StringName = Cosmetics.slot_of(id)
		if not _shows_slot(slot):
			continue
		var key: StringName = slot
		if slot == &"pet" and _has_themed_reactions(id):
			key = SECTION_REACTIVE_PETS
		if not _by_slot.has(key):
			_by_slot[key] = []
		(_by_slot[key] as Array).append(id)

	# Keep Cosmetics.SLOTS order, skipping slots with no content.
	for slot: StringName in Cosmetics.SLOTS:
		# Reactive pets shelve first: they are the flagship of the Pets tab.
		if slot == &"pet" and _by_slot.has(SECTION_REACTIVE_PETS):
			_slots.append(SECTION_REACTIVE_PETS)
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
	# Open on the first tab that has something equipped in it, else the first tab.
	var want: StringName = _slots[0]
	for slot: StringName in _slots:
		if _equipped_for(slot) > 0:
			want = slot
			break
	_select_slot(want)


## The slot a tab EQUIPS into: a section maps back to its real slot, and every
## other tab is its own slot. Anything that equips, tries on or reads what is
## worn must go through this - the section key is only a shelf.
func _real_slot(key: StringName) -> StringName:
	return &"pet" if key == SECTION_REACTIVE_PETS else key


## True for a pet whose preset declares THEMED_REACTIONS - read straight off the
## script, so marking a pet reactive is one line in its own file.
func _has_themed_reactions(cosmetic_id: int) -> bool:
	var script: GDScript = CosmeticPresetLibrary.script_for(cosmetic_id)
	return script != null and script.get_script_constant_map().has(&"THEMED_REACTIONS")


## Whether this copy of the menu shows [param slot] at all (see _only_slots).
func _shows_slot(slot: StringName) -> bool:
	if not _only_slots.is_empty():
		return _only_slots.has(slot)
	return not _exclude_slots.has(slot)


func _rebuild_tabs() -> void:
	for child: Node in _tab_bar.get_children():
		child.queue_free()
	_tab_buttons.clear()
	# A one-slot shelf (Pets) needs no tab strip: a single tab is just a label
	# costing a row this layout does not have.
	_tab_bar.visible = _slots.size() > 1
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


## Which equipped id this tab drives. Every slot has its own now, so this is a
## lookup rather than the weapon/everything-else split it used to be.
func _equipped_for(slot: StringName) -> int:
	return int(_equipped.get(_real_slot(slot), 0))


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


## Where the preview sits when it is not walking. Below centre: a preset draws
## from the FEET, so centring it puts most of the effect in the lower half of the
## box and the head-height layers off the top.
##
## Dropped from 0.55 once halos joined the picture. A halo draws at head height
## and the worn title is pinned to the top of the box, so at 0.55 the two
## overlapped - the one pairing a buyer is most likely to be checking looked like
## a rendering fault. The feet still clear the bottom with an aura's radius to
## spare.
##
## PETS SIT LOWER STILL. A flying pet hovers a head above its owner, and at 0.62
## it flew straight through the worn title pinned to the top of the box.
func _preview_home() -> Vector2:
	var origin: Vector2 = _preview_box_origin()
	if _real_slot(_slot) == &"pet":
		return origin + Vector2(PREVIEW_BOX * 0.5, PREVIEW_BOX * 0.8)
	return origin + Vector2(PREVIEW_BOX * 0.5, PREVIEW_BOX * 0.62)


## Where the centred preview box sits inside the preview viewport, which spans
## the whole stage. The homes above are authored against the box. Local
## positions, not global rects, so a scaled menu host cannot skew it.
func _preview_box_origin() -> Vector2:
	if _preview_box == null or _preview_center == null or _preview_view == null:
		return Vector2.ZERO
	return _preview_center.position + _preview_box.position - _preview_view.position


## Match the preview viewport to the stage: its 2D space in UI units, so the box
## maps 1:1, and its pixels at the window's real scale, so a glow is not rendered
## at the 960x540 base size and blown up.
func _fit_preview_viewport() -> void:
	if _preview_view == null or _preview_viewport == null:
		return
	var ui_size: Vector2i = Vector2i(_preview_view.size.round())
	if ui_size.x <= 0 or ui_size.y <= 0:
		return
	var pixel_scale: float = 1.0
	var root: Window = get_tree().root
	var base: Vector2 = Vector2(root.content_scale_size)
	if base.x > 0.0 and base.y > 0.0:
		pixel_scale = maxf(1.0, minf(root.size.x / base.x, root.size.y / base.y))
	var pixels: Vector2i = Vector2i((Vector2(ui_size) * pixel_scale).round())
	if _preview_viewport.size_2d_override != ui_size:
		_preview_viewport.size_2d_override = ui_size
	if _preview_viewport.size != pixels:
		_preview_viewport.size = pixels


## Walk the preview so trail presets have movement to sample. A circle rather than
## the back-and-forth the render tool uses: a wardrobe preview has no room to run,
## and a circle keeps the whole trail inside the box at every moment.
func _process(delta: float) -> void:
	if _preview_pivot == null:
		return
	_fit_preview_viewport()
	if _real_slot(_slot) == &"pet":
		_pet_walk_cycle(delta)
		return
	if not _walking:
		# Every frame, not once: the box's place in the viewport follows the
		# stage's layout, which settles a frame or two after the tab opens.
		_preview_pivot.position = _preview_home()
		return
	_walk_elapsed += delta
	var angle: float = _walk_elapsed * TAU / WALK_PERIOD_S
	# Squashed vertically, so the walk reads as movement across a floor rather
	# than as the effect being swung around on a string.
	var orbit: Vector2 = Vector2(cos(angle), sin(angle) * 0.5) * WALK_RADIUS
	_preview_pivot.position = _preview_home() + orbit


## Walk for PET_WALK_S, stand for PET_STAND_S, repeat - so the pet is seen both
## following and doing its idle trick. The body switches run/idle with it.
func _pet_walk_cycle(delta: float) -> void:
	_walk_elapsed += delta
	var t: float = fposmod(_walk_elapsed, PET_WALK_S + PET_STAND_S)
	var moving: bool = t < PET_WALK_S
	if moving:
		var angle: float = t * TAU / WALK_PERIOD_S
		_preview_pivot.position = _preview_home() + Vector2(cos(angle), sin(angle) * 0.5) * WALK_RADIUS
	if moving != _walking:
		_walking = moving
		_play_body(&"run" if moving else &"idle")


func _update_preview() -> void:
	var id: int = _current_id()
	if id == 0:
		return
	# Browsing a slot tries that item ON. The other slots keep whatever is in
	# them, which is what turns arrowing through halos into "how does this sit
	# over the aura I already have".
	_try_on[_real_slot(_slot)] = id
	_render_outfit()
	# The walk exists to give a TRAIL something to sample, so it follows the tab
	# you are on rather than the outfit: standing still on the Auras tab while a
	# tried-on trail drags the mannequin round in circles reads as a bug.
	_walking = _slot == &"trail"
	if not _walking and _preview_pivot != null:
		_preview_pivot.position = _preview_home()
	# Re-read every browse for the same reason the wearer is: the player can
	# change skin in another menu while this one is open.
	_refresh_wearer()
	var ids: Array = _current_ids()
	_name_label.text = "%s  (%d/%d)" % [
		Cosmetics.display_name(id),
		int(_idx_by_slot.get(_slot, 0)) + 1,
		ids.size(),
	]
	_update_action()


## Draw every slot of the tried-on outfit at once.
##
## THE WHOLE POINT OF TRYING THINGS ON. A halo, an aura and a trail are worn
## together in the world, and the only question a buyer has once they like an
## effect is whether it goes with the rest of what they own. Showing one at a
## time answers a question nobody asked.
##
## THE TWO EVENT SLOTS ONLY RENDER ON THEIR OWN TAB. A flourish and a departure
## are one-shots that the preview node replays on a loop; left in the outfit they
## would fire over and over behind whatever else was being browsed, which reads
## as the aura being broken rather than as a flourish being worn.
##
## NOTHING HERE LEAVES THE MENU. No request, no equip, no push - the mannequin is
## the only thing that changes.
func _render_outfit() -> void:
	for slot: StringName in _preview_vfx:
		var vfx: CosmeticVfx = _preview_vfx[slot]
		# THE WEAPON SLOT ONLY RENDERS ON ITS OWN TAB TOO. In the world it re-skins
		# the Ascended weapon in hand and never draws on the body; the mannequin
		# holds no weapon, so worn here it drew the raw strip as a giant sword over
		# every aura and pet.
		var own_tab_only: bool = slot == &"weapon" or not Cosmetics.LOOPING_SLOTS.has(slot)
		var wanted: int = int(_try_on.get(slot, 0))
		if own_tab_only and slot != _real_slot(_slot):
			wanted = 0
		if wanted == 0:
			vfx.visible = false
			vfx.apply(0)
			continue
		# Lend each one the player's own character: Chrono Echo stamps the
		# wearer's live sprite frame, and with nothing to read it previews as an
		# empty box.
		vfx.preview_wearer = ClientState.local_player
		vfx.apply(wanted)
	_update_try_on_label()


## Say when the mannequin is wearing something the player is not, so nobody
## reads the preview as their character and wonders why the world disagrees.
func _update_try_on_label() -> void:
	if _try_on_label == null:
		return
	var extra: int = 0
	for slot: StringName in _try_on:
		if int(_try_on[slot]) != _equipped_for(slot):
			extra += 1
	_try_on_label.visible = extra > 0
	if extra > 0:
		_try_on_label.text = "Trying on %d — not worn. Reopen the Vault to reset." % extra


## Start every visit from what the player actually wears. A try-on that survived
## a close and reopen would be indistinguishable from the real thing the next
## time they looked.
func _reset_try_on() -> void:
	_try_on.clear()
	for slot: StringName in _equipped:
		_try_on[slot] = int(_equipped[slot])
	_render_outfit()


## Put the buyer's own character under the effect, and their title over it.
##
## THE POINT OF THE WHOLE PREVIEW. A player is choosing between auras they will
## see on THEIR body in THEIR dye, and the same effect reads differently over a
## dark Knight than over a pale Scholar. Reading it off the local player rather
## than off a stock mannequin also means a wardrobe change elsewhere shows up
## here without this menu knowing anything about wardrobes.
##
## FALLS BACK TO THE STARTER BODY rather than to nothing. With no local player -
## a render tool, or a menu opened before the world finished spawning - an empty
## box reads as a broken preview, while a stand-in body still shows how the
## effect sits on a character. In the game there is always a local player and
## this never fires.
func _refresh_wearer() -> void:
	if _body == null:
		return
	var wearer: Player = ClientState.local_player as Player
	var live: bool = wearer != null and is_instance_valid(wearer)

	_body.visible = true
	var skin_id: int = wearer.skin_id if live else PlayerSkins.starter_skin_id()
	var frames: SpriteFrames = ContentRegistryHub.load_by_id(
		&"sprites", skin_id
	) as SpriteFrames
	if frames != null and _body.sprite_frames != frames:
		_body.sprite_frames = frames
	# The prestige recolour is a shader on the sprite, exactly as the world
	# applies it - so an aura is judged against the dye it will actually sit on.
	VaultSkinVfx.apply_to_sprite(_body, wearer.vault_skin_id if live else 0)
	# "run", not "walk": player SpriteFrames are authored ["death", "idle",
	# "run"] and there is no walk clip to fall back from.
	_play_body(&"run" if _walking else &"idle")

	if _wearer_title == null:
		return
	var title: String = wearer.display_title.strip_edges() if live else ""
	# Not on the Pets tab: perching pets (the owls, the moth) sit on the head,
	# and in this small box that is exactly where the title is pinned.
	if _real_slot(_slot) == &"pet":
		title = ""
	_wearer_title.visible = not title.is_empty()
	if title.is_empty():
		return
	_wearer_title.text = "— %s —" % title
	# preview:true for the same reason the Titles shelf passes it - this label is
	# nowhere near the camera and never walks anywhere, so the emitter stacks
	# must not cull themselves against either.
	TitleVfx.apply_to_label(_wearer_title, title, true)


## Play [param wanted], falling back the way the skin wardrobe does: not every
## sprite sheet carries every clip, and a missing one must not leave the body
## frozen on frame zero.
##
## NEVER falls back to names[0] blindly - that is "death" on player frames, and a
## corpse lying across the aura is not the sale.
func _play_body(wanted: StringName) -> void:
	if _body == null or _body.sprite_frames == null:
		return
	var frames: SpriteFrames = _body.sprite_frames
	var anim: StringName = wanted
	if not frames.has_animation(anim):
		anim = &""
		for candidate: StringName in [&"idle", &"run"]:
			if frames.has_animation(candidate):
				anim = candidate
				break
		if anim.is_empty():
			var names: PackedStringArray = frames.get_animation_names()
			if names.is_empty():
				return
			anim = StringName(names[0])
	if _body.animation != anim or not _body.is_playing():
		_body.play(anim)


func _update_action() -> void:
	var id: int = _current_id()
	_announce_selection(VaultGrants.cosmetic_token(id) if id != 0 else "")
	if id == 0:
		return
	if id == _equipped_for(_real_slot(_slot)):
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


## What this slot actually does, and WHEN IT SHOWS, in the player's words.
##
## Every line names the moment the effect appears, because the two event slots
## cannot be judged from the preview alone: a flourish and a departure look
## identical in the wardrobe - both replay on a loop there - and are completely
## different purchases. One fires every time you level, the other only when you
## die. A buyer who learns that after paying has been sold a surprise.
##
## "Everyone nearby sees it" is on the event lines on purpose. Both are
## broadcast to the whole instance, and being seen is the entire point of
## buying one.
func _slot_blurb(slot: StringName) -> String:
	match slot:
		&"aura":
			return "Worn: glows around you wherever you go."
		&"trail":
			return "Worn: leaves a wake behind you as you move."
		&"halo":
			return "Worn: sits above your head, everywhere you go."
		&"weapon":
			return "Worn: lights up any Ascended weapon you hold."
		&"flourish":
			return "Plays once each time you gain a level. Everyone nearby sees it."
		&"departure":
			return "Plays once where you fall when you die. Everyone nearby sees it."
		&"pet":
			return "Worn: follows you everywhere, and does something when you stop."
		&"pet_reactive":
			return "Worn: follows you, and joins in with whatever you're doing."
	return "Worn effect."


func _on_action_pressed() -> void:
	var id: int = _current_id()
	if id != 0:
		_equip(id, _real_slot(_slot))


## Clearing sends the slot explicitly — id 0 has no slot of its own, so the server
## cannot infer which one to clear.
func _on_clear_pressed() -> void:
	_equip(0, _real_slot(_slot))


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
	if id > 0:
		_equipped[slot] = id
	else:
		_equipped.erase(slot)

	# Instant local swap so the preview and the character behind the menu react
	# now rather than on the next state fetch. Only the three WORN slots have a
	# channel to write; a flourish or a departure has nothing to show until it
	# fires, which is the whole difference between the two kinds of slot.
	var lp: Node = ClientState.local_player
	if lp != null and is_instance_valid(lp):
		match slot:
			&"weapon":
				lp.weapon_cosmetic_id = id
			&"aura":
				lp.cosmetic_id = id
			&"halo":
				lp.halo_cosmetic_id = id
			&"trail":
				lp.trail_cosmetic_id = id
			&"pet":
				lp.pet_cosmetic_id = id
	# Bought or equipped for real, so the mannequin and the player agree about
	# this slot again - and the "trying on" count drops by one.
	_try_on[slot] = id
	_render_outfit()
	_update_action()
	_refresh_wearer()


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
