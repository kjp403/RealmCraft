extends Control
## The one reward readout for every container in the game — bag chests, dungeon
## caskets, treasure clues, boss loot boxes, Daily Skilling Chests.
##
## NON-INTRUSIVE BY CONSTRUCTION, and that is the whole point of the file:
##
##   1. It is NOT a `display_menu` menu. display_menu hides every other menu when
##      it opens one, which is correct for full-screen shells and fatal for a
##      reward readout — it is what forced the old Bank All -> Close -> reopen
##      Inventory -> open the next chest cycle. This is mounted as a plain HUD
##      overlay, so display_menu neither knows about it nor can hide it.
##   2. It never hides anything itself. No backdrop, no modal dim.
##   3. The root Control spans the screen but is MOUSE_FILTER_IGNORE; only the
##      panel takes clicks. The inventory stays fully usable underneath, so you
##      can open a chest, read the haul, and open the next one without the window
##      ever moving or closing.
##
## ZERO GAMEPLAY MATH. Every number shown arrives on the payload, and rarity is a
## tier name the server stamped ([LootRarity]). This script decides how loud a
## drop looks, never how likely it was.
##
## PIXEL-ART CHROME. Frames are 9-slice textures from [PixelUI], type is the
## pixel font, and the root sets NEAREST filtering once for the whole subtree.
## A rare row is not a recoloured box: it gets a shimmering shader background, an
## animated frame that pulses between iron and its rarity metal, and a particle
## burst — the three together are what make a 1-in-1000 drop land.

## How long a freshly-added row takes to pop in. Deliberately brief — during an
## Open All this fires once per distinct item and anything slower reads as lag.
const POP_TIME: float = 0.16
## One full bright->dim cycle of a celebrated row's frame.
const GLOW_TIME: float = 0.55
## Cycles a celebrated frame pulses before settling on its rarity colour.
const GLOW_CYCLES: int = 3

## Minimum gap between ORDINARY drop ticks. An Open All fires reward_granted once
## per distinct item per server chunk, which without this is a wall of clicks
## rather than a sequence of events. Rare and ultra cues bypass the throttle —
## those are the ones the player is listening for, and they are rare by
## definition, so they can never flood.
const DROP_CUE_INTERVAL_MS: int = 70

## Ticks of the last ordinary drop cue, for DROP_CUE_INTERVAL_MS.
var _last_drop_cue_ms: int = 0

var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _batch_row: HBoxContainer
var _progress: ProgressBar
var _ledger_box: VBoxContainer
var _scroll: ScrollContainer
var _gold_label: Label
var _slots_label: Label
var _take_button: Button
var _bank_button: Button

## item id -> the row Control currently showing it, so a second arrival of the
## same item bumps the existing row instead of stacking duplicates.
var _rows: Dictionary[int, Control] = {}
## The chest stack the batch buttons act on. 0 hides them (a pushed reward with
## no stack behind it — a boss drop, a daily chest).
var _target_chest_id: int = 0
var _remaining: int = 0
## True while showing a standing pile (the Boss Hunt stash) rather than the
## result of opening something. Drives the wording and hides the reveal chrome.
var _is_claim_only: bool = false
## Stack cap of the pile on show, or 0 when it has none.
var _capacity: int = 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The root spans the viewport only so the panel can anchor against it. It must
	# not eat input, or it would swallow every click meant for the inventory
	# underneath — which is exactly the intrusiveness this window exists to avoid.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Before _build: texture_filter inherits, so every frame, slot and glyph
	# created below is drawn NEAREST.
	PixelUI.make_pixel_perfect(self)
	hide()
	_build()

	# Everything this window shows comes from the manager. It issues no gameplay
	# requests of its own beyond the claim buttons, and computes nothing.
	UniversalChestManager.batch_started.connect(_on_batch_started)
	UniversalChestManager.batch_progress.connect(_on_batch_progress)
	UniversalChestManager.reward_granted.connect(_on_reward_granted)
	UniversalChestManager.rare_granted.connect(_on_rare_granted)
	UniversalChestManager.batch_finished.connect(_on_batch_finished)
	UniversalChestManager.pending_changed.connect(_on_pending_changed)
	UniversalChestManager.claim_blocked.connect(_on_claim_blocked)


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

func _build() -> void:
	_panel = PanelContainer.new()
	# Right-hand column, vertically centred: clear of the inventory grid (left /
	# centre) and of the loot feed (left edge), so both stay readable with this up.
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -388.0
	_panel.offset_right = -20.0
	_panel.offset_top = -230.0
	_panel.offset_bottom = 230.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	PixelUI.panel(_panel, "frame_stone", 12)
	add_child(_panel)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 8)
	_panel.add_child(col)

	# --- Header ---
	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	col.add_child(head)

	var titles: VBoxContainer = VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override(&"separation", 2)
	head.add_child(titles)

	_title = PixelUI.text("", PixelUI.SIZE_HEADING, PixelUI.INK_GOLD)
	titles.add_child(_title)

	_subtitle = PixelUI.text("", PixelUI.SIZE_CAPTION, PixelUI.INK_DIM)
	titles.add_child(_subtitle)

	var close: Button = Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(32, 32)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.tooltip_text = "Close (loot stays staged until you claim it)"
	PixelUI.button_frame(close, "frame_iron", 4)
	PixelUI.button_font(close, PixelUI.SIZE_BODY, PixelUI.INK_DIM)
	close.pressed.connect(_on_close)
	head.add_child(close)

	# --- Batch actions ---
	_batch_row = HBoxContainer.new()
	_batch_row.add_theme_constant_override(&"separation", 6)
	col.add_child(_batch_row)
	_batch_row.add_child(_batch_button("Open 1", 1))
	_batch_row.add_child(_batch_button("Open 5", 5))
	_batch_row.add_child(_batch_button("Open All", UniversalChestManager.ALL))

	_progress = ProgressBar.new()
	PixelUI.progress_bar(_progress, PixelUI.INK_GOLD, 10)
	_progress.hide()
	col.add_child(_progress)

	# --- Ledger ---
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, 210)
	col.add_child(_scroll)

	_ledger_box = VBoxContainer.new()
	_ledger_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ledger_box.add_theme_constant_override(&"separation", 3)
	_scroll.add_child(_ledger_box)

	# --- Footer ---
	_gold_label = PixelUI.text("", PixelUI.SIZE_BODY, PixelUI.INK_COIN)
	col.add_child(_gold_label)

	_slots_label = PixelUI.text("", PixelUI.SIZE_TINY, PixelUI.INK_DIM)
	_slots_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_slots_label)

	var actions: HBoxContainer = HBoxContainer.new()
	actions.add_theme_constant_override(&"separation", 8)
	col.add_child(actions)

	_take_button = Button.new()
	_take_button.text = "Claim All"
	_take_button.tooltip_text = "Into your bag; anything that won't fit goes to your bank."
	_take_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_take_button.custom_minimum_size = Vector2(0, 36)
	PixelUI.button_frame(_take_button, "frame_gold", 6)
	PixelUI.button_font(_take_button, PixelUI.SIZE_BODY, PixelUI.INK_GOLD)
	_take_button.pressed.connect(_on_claim_all)
	actions.add_child(_take_button)

	_bank_button = Button.new()
	_bank_button.text = "Bank All"
	_bank_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bank_button.custom_minimum_size = Vector2(0, 36)
	PixelUI.button_frame(_bank_button, "frame_iron", 6)
	PixelUI.button_font(_bank_button, PixelUI.SIZE_BODY, PixelUI.INK)
	_bank_button.pressed.connect(_on_bank_all)
	actions.add_child(_bank_button)


func _batch_button(text: String, count: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 32)
	PixelUI.button_frame(b, "frame_iron", 4)
	PixelUI.button_font(b, PixelUI.SIZE_CAPTION, PixelUI.INK)
	b.pressed.connect(_on_batch_pressed.bind(count))
	return b


# ---------------------------------------------------------------------------
# Manager signals
# ---------------------------------------------------------------------------

func _on_batch_started(chest_name: String, requested: int) -> void:
	# A new run replaces the previous readout. Staged loot is server-side, so
	# clearing the list here never discards anything the player hasn't claimed.
	_clear_rows()
	_title.text = chest_name
	# requested 0 = nothing was opened. That is the Hunt Chest: a standing pile
	# to claim from, not a reveal. No "Opening...", no progress bar, and
	# set_target_chest(0) keeps the Open buttons hidden because there is nothing
	# to open.
	_is_claim_only = requested == 0
	if _is_claim_only:
		_subtitle.text = "Boss Hunt stash"
		set_target_chest(0, 0)
	else:
		_subtitle.text = "Opening..." if requested != 1 else "Opened"
	_progress.visible = not _is_claim_only and requested != 1
	_progress.value = 0.0
	_set_batch_enabled(false)
	show()
	move_to_front()


func _on_batch_progress(opened: int, remaining: int, _ledger: Array) -> void:
	_remaining = remaining
	_subtitle.text = "Opened %d · %d left" % [opened, remaining]
	# Fraction of the run done, computed from counts the SERVER reported.
	var total: float = float(opened + remaining)
	_progress.max_value = maxf(1.0, total)
	_progress.value = float(opened)


## One item arrived (or grew). Rows are keyed by item id, so a fifty-chest run
## produces one row per distinct item that keeps counting up.
func _on_reward_granted(entry: Dictionary) -> void:
	var id: int = int(entry.get("id", 0))
	if id <= 0:
		return
	# The tactile tick for ordinary loot. Celebrated tiers stay silent here and
	# get their own cue from _celebrate, so a rare drop is one sound, not two
	# stacked on the same frame.
	if not LootRarity.is_celebrated(
		LootRarity.from_name(str(entry.get("rarity", "common")))
	):
		var now_ms: int = Time.get_ticks_msec()
		if now_ms - _last_drop_cue_ms >= DROP_CUE_INTERVAL_MS:
			_last_drop_cue_ms = now_ms
			UISound.reward_drop()
	if _rows.has(id):
		_update_row(_rows[id], entry)
		return
	var row: Control = _build_row(entry)
	_rows[id] = row
	_ledger_box.add_child(row)
	_pop(row)


func _on_rare_granted(entry: Dictionary) -> void:
	var id: int = int(entry.get("id", 0))
	if not _rows.has(id):
		return
	var row: Control = _rows[id]
	_celebrate(row, str(entry.get("rarity", "common")))


func _on_batch_finished(summary: Dictionary) -> void:
	var opened: int = int(summary.get("opened", 0))
	_capacity = int(summary.get("capacity", 0))
	_remaining = int(summary.get("free_slots", 0))
	_title.text = str(summary.get("chest", "Rewards"))
	if _is_claim_only:
		var stacks: int = (summary.get("pending", []) as Array).size()
		# The Hunt Chest has a stack cap and silently refuses NEW ids once full,
		# so how close it is to that cap is the number that actually matters here.
		_subtitle.text = (
			"%d / %d stacks" % [stacks, _capacity] if _capacity > 0
			else "%d stacks" % stacks
		)
	else:
		_subtitle.text = "Opened %d" % opened if opened != 1 else "Opened"
	_progress.hide()
	_set_batch_enabled(true)
	var gold: int = int(summary.get("gold", 0))
	_gold_label.visible = gold > 0
	_gold_label.text = "+%s gold (already in your pouch)" % _fmt(gold)
	# One coin cue for the whole run, on the total — not one per chest, which
	# during an Open All would bury every other cue.
	if gold > 0 and not _is_claim_only:
		UISound.reward_gold()
	if _is_claim_only:
		# Nothing was "granted" — the rows ARE the stash contents, so build them
		# from the pile rather than from a reward ledger that is empty by design.
		_show_pile(summary.get("pending", []) as Array)
	elif (summary.get("items", []) as Array).is_empty() and gold <= 0:
		_empty_note()
	show()
	move_to_front()


func _on_pending_changed(pending: Array, free_slots: int) -> void:
	var stacks: int = pending.size()
	# "waiting" is transient-loot language. The Hunt Chest is permanent storage —
	# nothing there is waiting on the player, it is just stored.
	var verb: String = "stored" if _is_claim_only else "waiting"
	_slots_label.text = (
		("Your Hunt Chest is empty." if _is_claim_only else "Nothing left to claim.")
		if stacks == 0
		else "%d stack%s %s · %d free bag slot%s" % [
			stacks, "" if stacks == 1 else "s", verb,
			free_slots, "" if free_slots == 1 else "s"
		]
	)
	var has_pending: bool = stacks > 0
	_take_button.disabled = not has_pending
	_bank_button.disabled = not has_pending


func _on_claim_blocked(note: String) -> void:
	Toaster.toast(note)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

## Point the batch buttons at a chest stack. Called by whoever opened the window
## from an inventory slot; a pushed reward (boss drop, daily chest) leaves it 0
## and the batch row hides.
func set_target_chest(item_id: int, held: int) -> void:
	_target_chest_id = item_id
	_remaining = held
	_batch_row.visible = item_id > 0


func _on_batch_pressed(count: int) -> void:
	if _target_chest_id <= 0 or UniversalChestManager.is_busy():
		return
	UniversalChestManager.open(_target_chest_id, count)


func _on_claim_all() -> void:
	_set_claim_enabled(false)
	await UniversalChestManager.claim_all()
	_set_claim_enabled(true)


func _on_bank_all() -> void:
	_set_claim_enabled(false)
	await UniversalChestManager.bank_all()
	_set_claim_enabled(true)


## Closing is presentation only — staged loot lives server-side until claimed (or
## auto-banked at logout), so this can never lose a reward.
func _on_close() -> void:
	hide()


func _set_batch_enabled(enabled: bool) -> void:
	for child: Node in _batch_row.get_children():
		if child is Button:
			(child as Button).disabled = not enabled


func _set_claim_enabled(enabled: bool) -> void:
	_take_button.disabled = not enabled
	_bank_button.disabled = not enabled


# ---------------------------------------------------------------------------
# Rows + animation
# ---------------------------------------------------------------------------

func _build_row(entry: Dictionary) -> Control:
	var rarity: String = str(entry.get("rarity", "common"))
	var look: Array = PixelUI.RARITY_LOOK.get(rarity, PixelUI.RARITY_LOOK["common"])
	var frame_name: String = str(look[0])
	var tint: Color = look[1]

	var frame: PanelContainer = PanelContainer.new()
	# 4px inset, not the usual 6: a ledger row is a list line, and during an
	# Open All the value is in seeing more of the haul at once.
	frame.add_theme_stylebox_override(&"panel", PixelUI.frame(frame_name, 4))
	frame.set_meta(&"tint", tint)
	frame.set_meta(&"frame_name", frame_name)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	frame.add_child(row)

	# --- Item slot: a recessed square that a rare drop lights up from behind ---
	var slot: PanelContainer = PanelContainer.new()
	slot.custom_minimum_size = Vector2(28, 28)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_theme_stylebox_override(&"panel", PixelUI.slot_style())
	row.add_child(slot)

	# The shimmer is a sibling UNDER the icon, not a material on the icon: putting
	# the shader on the sprite would tint the artwork itself, and a gilded helm
	# washed out by its own celebration is worse than no effect at all.
	var shine: ColorRect = ColorRect.new()
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine.color = Color(1, 1, 1, 1)
	shine.visible = false
	slot.add_child(shine)
	frame.set_meta(&"shine", shine)

	var icon_host: CenterContainer = CenterContainer.new()
	slot.add_child(icon_host)
	var item: Item = ContentRegistryHub.load_by_id(&"items", int(entry.get("id", 0))) as Item
	if item != null and item.item_icon != null:
		PixelIcon.mount(icon_host, item.item_icon)

	var name_label: Label = PixelUI.text(
		str(entry.get("name", "Item")), PixelUI.SIZE_CAPTION, tint
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	var amount: Label = PixelUI.text(
		"x%s" % _fmt(int(entry.get("amount", 0))), PixelUI.SIZE_BODY, PixelUI.INK_GOLD
	)
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(amount)
	# The Label itself, not its NodePath: the row is built before it is added to
	# the tree, so get_path() has nothing to resolve against yet.
	frame.set_meta(&"amount_label", amount)

	return frame


func _update_row(row: Control, entry: Dictionary) -> void:
	var amount: Label = row.get_meta(&"amount_label", null) as Label
	if amount == null or not is_instance_valid(amount):
		return
	amount.text = "x%s" % _fmt(int(entry.get("amount", 0)))
	# A short scale bump on the count, so a row that keeps growing during an
	# Open All reads as live rather than as a static list that happens to change.
	amount.pivot_offset = amount.size / 2.0
	var tween: Tween = create_tween()
	tween.tween_property(amount, "scale", Vector2(1.25, 1.25), 0.06)
	tween.tween_property(amount, "scale", Vector2.ONE, 0.10)


## Fast pop-in for a newly added row.
func _pop(row: Control) -> void:
	row.modulate.a = 0.0
	row.scale = Vector2(0.94, 0.94)
	# pivot_offset needs a real size; rows are built and added in the same frame,
	# so wait one frame for layout before pivoting or the scale grows from (0,0).
	await get_tree().process_frame
	if not is_instance_valid(row):
		return
	row.pivot_offset = row.size / 2.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(row, "modulate:a", 1.0, POP_TIME)
	tween.tween_property(row, "scale", Vector2.ONE, POP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Keep the newest arrival in view during a long run.
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.ensure_control_visible(row)


## The full treatment for a drop the SERVER tiered as celebrated, in three parts
## that read at different distances:
##   the shimmering slot background catches the eye in peripheral vision,
##   the pulsing frame says WHICH row,
##   the burst says it just happened.
## Any one alone is a recoloured box; together they are a drop worth a screenshot.
func _celebrate(row: Control, rarity: String) -> void:
	var look: Array = PixelUI.RARITY_LOOK.get(rarity, PixelUI.RARITY_LOOK["common"])
	var tint: Color = look[1]
	var frame_name: String = str(look[0])

	# Fired here, at the top of _celebrate, so the sting lands on the SAME frame
	# the shimmer switches on and the burst is queued. Playing it from the signal
	# handler instead would drift ahead of the visual by however long the row
	# build takes.
	if rarity == "ultra":
		UISound.reward_ultra()
	else:
		UISound.reward_rare()

	# 1. Shimmer behind the item.
	var shine: ColorRect = row.get_meta(&"shine", null) as ColorRect
	if shine != null and is_instance_valid(shine):
		shine.material = PixelUI.shimmer_material(tint)
		shine.visible = true

	# 2. Frame pulse. The stylebox's modulate_color is tweened rather than
	# swapping styleboxes per step — one object, and the tween drives it directly.
	var glow: StyleBoxTexture = PixelUI.frame(frame_name, 4)
	row.add_theme_stylebox_override(&"panel", glow)
	var tween: Tween = create_tween().set_loops(GLOW_CYCLES)
	tween.tween_method(
		func(v: float) -> void:
			glow.modulate_color = Color(v, v, v, 1.0),
		1.0, 1.9, GLOW_TIME * 0.5
	)
	tween.tween_method(
		func(v: float) -> void:
			glow.modulate_color = Color(v, v, v, 1.0),
		1.9, 1.0, GLOW_TIME * 0.5
	)

	# 3. Burst.
	_burst(row, tint)


## One-shot particle explosion centred on [param row]. CPUParticles2D rather than
## GPU: a handful of short-lived bursts in a UI layer, where the GPU variant's
## setup cost is not worth it and would need its own material per colour.
##
## Square, unsmoothed particles on purpose — a soft round default sprite is the
## same vector tell as a rounded panel corner.
func _burst(row: Control, tint: Color) -> void:
	await get_tree().process_frame
	if not is_instance_valid(row):
		return
	var fx: CPUParticles2D = CPUParticles2D.new()
	fx.texture = load(PixelUI.FRAMES + "slot.png") as Texture2D
	fx.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fx.emitting = false
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.amount = 24
	fx.lifetime = 0.65
	fx.direction = Vector2.UP
	fx.spread = 180.0
	fx.gravity = Vector2(0, 260)
	fx.initial_velocity_min = 90.0
	fx.initial_velocity_max = 230.0
	# Small integer-ish scales keep the sparks reading as chunky pixels.
	fx.scale_amount_min = 0.10
	fx.scale_amount_max = 0.22
	fx.color = tint
	fx.position = row.size / 2.0
	fx.z_index = 4
	row.add_child(fx)
	fx.emitting = true
	# Self-cleanup: one-shot particles would otherwise pile up on a long run.
	await get_tree().create_timer(fx.lifetime + 0.2).timeout
	if is_instance_valid(fx):
		fx.queue_free()


## Render a standing pile (the Boss Hunt stash) as reward rows.
##
## The pile arrives in the storage shape [{id, a}] rather than the reward-ledger
## shape [{id, amount, name, rarity}], so it is translated here. No rarity is
## claimed for stored items: rarity is a property of the ROLL that produced a
## drop, and by the time loot is sitting in a stash that roll is long past —
## painting a stored helm gold would be inventing a fact the server never sent.
func _show_pile(stacks: Array) -> void:
	_clear_rows()
	if stacks.is_empty():
		_empty_note()
		return
	for entry_v: Variant in stacks:
		if entry_v is not Dictionary:
			continue
		var entry: Dictionary = entry_v
		var id: int = int(entry.get("id", 0))
		if id <= 0:
			continue
		var item: Item = ContentRegistryHub.load_by_id(&"items", id) as Item
		var row: Control = _build_row({
			"id": id,
			# Storage uses "a"; the reward ledger uses "amount".
			"amount": int(entry.get("a", entry.get("amount", 0))),
			"name": str(item.item_name) if item != null else "Item",
			"rarity": "common",
		})
		_rows[id] = row
		_ledger_box.add_child(row)


func _clear_rows() -> void:
	_rows.clear()
	for child: Node in _ledger_box.get_children():
		child.queue_free()


func _empty_note() -> void:
	var note: Label = PixelUI.text("Nothing this time.", PixelUI.SIZE_BODY, PixelUI.INK_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ledger_box.add_child(note)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _fmt(value: int) -> String:
	return NumberFormat.with_commas(value)
