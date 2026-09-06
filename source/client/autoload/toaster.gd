extends CanvasLayer
## Lightweight transient toasts (client only). Call from anywhere:
##   Toaster.toast("Saved!")
##   Toaster.toast("Mining — Level 2!", 3.0)
## Cards stack in a left-edge lane, newest at the bottom, and each slides in from
## the screen edge, dwells, then floats up and frees itself.
## Purely cosmetic feedback — never gameplay-authoritative.
##
## LANE GEOMETRY — the margins below are not taste. The RIGHT half of the screen is
## unusable: every compact menu (inventory, equipment, skills, mastery, quests,
## friends, settings) places itself bottom-right with
##   position = (hud.size.x - PANEL_SIZE.x - 12, hud.size.y - PANEL_SIZE.y - 48)
## which on 960x540 is a union footprint of x 700..948, y 152..492 the moment the
## player opens a bag. Anchoring toasts there buries them.
##
## What the LEFT half holds (hud.tscn, chat_menu.tscn, loot_feed.gd):
##   ButtonRail       x  10..50   y  10..146   always visible
##   SlayerTracker    x   6..     y   6..      only while on a slayer task
##   Chat full feed   x   8..268  y 192..532   opens on demand, auto-hides
##   LootFeed column  x  58..260  y 216..      the pickup pills (shares MARGIN_LEFT)
## That leaves exactly one clear band: right of the button rail, above the chat box
## and the loot feed. MARGIN_LEFT clears ButtonRail, MARGIN_TOP clears a visible
## SlayerTracker, MARGIN_BOTTOM keeps the stack off the chat box. Move one and the
## lane starts overlapping live HUD again — tools/render_toast_lane.gd measures it.
##
## MARGIN_RIGHT is nearly inert here: cards are SIZE_SHRINK_BEGIN and size to their
## own content, so they grow rightward from MARGIN_LEFT. Measured real toasts run
## 111..229px wide, nowhere near the compact-panel zone.

## How many toasts can be on screen at once (oldest is retired past this).
##
## THREE, not four, because the left lane is short: the clear band between the
## slayer tracker and the chat box is 160px, and a two-line card is 37px. Four
## would overflow the band and paint over the chat box — measured, not guessed.
## The cap costs less than it looks: toast_feed() coalesces, so a pack of mobs is
## still one card, and it is only genuinely distinct events that compete.
const MAX_TOASTS: int = 3

## Hard ceiling including cards already playing their exit. Past this the oldest is
## freed outright rather than animated — a burst can never grow the column forever.
const HARD_CAP: int = MAX_TOASTS + 3

## A repeat of the same coalesce key within this window merges into the existing
## card (bumps a ×N counter + pulses it) instead of spawning a new one. After this
## much silence the next event opens a fresh card.
const COALESCE_WINDOW_MS: int = 6000

## Sentinel for toast()'s optional font color — alpha 0 means "leave the theme
## default", any opaque color tints the label.
const NO_TINT: Color = Color(0, 0, 0, 0)

const MARGIN_LEFT: int = 58   # right of ButtonRail (x 10..50)
const MARGIN_TOP: int = 26    # headroom for a 3-deep stack of multi-line cards
const MARGIN_RIGHT: int = 8   # see the note above — cards size to content
const MARGIN_BOTTOM: int = 354 # lane bottom lands at y 186, above the chat box

## Card look. Translucent near-black so the world reads through it, hairline border
## in the theme's accent hue at low alpha so it separates from bright ground tiles
## without looking like a menu panel.
##
## These values now live in [PixelUI] as the shared HUD-overlay standard — the
## loot feed, quest tracker and party roster draw from the same constants, so a
## tweak here reaches all four surfaces instead of leaving three behind. The
## aliases are kept because the geometry notes above are written in terms of them.
const CARD_BG: Color = PixelUI.HUD_CARD_BG
const CARD_BORDER: Color = PixelUI.HUD_CARD_BORDER
const CARD_RADIUS: int = PixelUI.HUD_CARD_RADIUS
const PAD_X: int = PixelUI.HUD_CARD_PAD_X
const PAD_Y: int = PixelUI.HUD_CARD_PAD_Y

const SIZE_TITLE: int = PixelUI.SIZE_CAPTION # 12
const SIZE_LINE: int = PixelUI.SIZE_TINY     # 10

## Motion. Cards enter from SLIDE_PX to the LEFT of their resting spot — they come
## in off the screen edge they are anchored to — and leave by drifting FLOAT_PX
## upward as they fade.
const SLIDE_PX: float = 26.0
const FLOAT_PX: float = 10.0
const ENTER_S: float = 0.18
const EXIT_S: float = 0.35
const RETIRE_S: float = 0.16

var _column: VBoxContainer

## Active coalescable toasts, keyed by a content-stable string (e.g. "kill:goblin",
## "mine:Iron Ore"). { key: { "card", "body", "count": int, "last_ms": int } }.
## Cleared when the card frees (tree_exited).
var _active: Dictionary = {}


func _ready() -> void:
	# Mirrors ClientState/Client: this is client-only UI.
	if not GameMode.is_client():
		queue_free()
		return

	layer = 128 # Above the HUD and menus.

	# Full-rect so the margins are measured off the screen edges. MOUSE_FILTER_IGNORE
	# on BOTH nodes is load-bearing: a full-rect Control on layer 128 that stopped
	# mouse input would swallow every click in the game.
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "ToastMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(&"margin_left", MARGIN_LEFT)
	margin.add_theme_constant_override(&"margin_top", MARGIN_TOP)
	margin.add_theme_constant_override(&"margin_right", MARGIN_RIGHT)
	margin.add_theme_constant_override(&"margin_bottom", MARGIN_BOTTOM)
	add_child(margin)

	_column = VBoxContainer.new()
	_column.name = "ToastColumn"
	_column.alignment = BoxContainer.ALIGNMENT_END # pin the stack to the bottom
	_column.add_theme_constant_override(&"separation", 4)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_column)


# --- Public API ---------------------------------------------------------------

func toast(text: String, duration: float = 2.0, font_color: Color = NO_TINT) -> void:
	if _column == null or text.is_empty():
		return
	_make_room()
	var card: PanelContainer = _spawn()
	var body: VBoxContainer = card.get_child(0)
	body.add_child(_line_label(text, font_color if font_color.a > 0.0 else PixelUI.INK))
	_fit(card)
	_restart_dwell(card, duration)


## Show a multi-line card: bold-ish title + a list of sub-lines. Use when
## one logical event produces several feedback strings (kill = "Defeated
## a Goblin" + "+15 XP" + "Looted 1 Tooth"; quest turn-in = title + XP +
## gold + level-up). Renders as ONE PanelContainer so the player reads it
## as one notification instead of a flood of 3-4 separate toasts.
func toast_group(title: String, lines: PackedStringArray, duration: float = 2.0) -> void:
	if _column == null:
		return
	if title.is_empty() and lines.is_empty():
		return
	_make_room()
	var card: PanelContainer = _spawn()
	_render(card.get_child(0), title, lines, 1)
	_fit(card)
	_restart_dwell(card, duration)


## Coalescing card for high-frequency events (kills, gather yields, quest
## progress). A repeat of [param key] within COALESCE_WINDOW_MS updates the SAME
## card — refreshes its lines, bumps a ×N counter into the title, and pulses it —
## instead of stacking another card. Empty key = no coalescing (falls back to a
## normal grouped card). This is what stops a pack of mobs / a vein of ore from
## flooding the screen: ten goblins are one card reading "×10", not ten cards.
func toast_feed(key: String, title: String, lines: PackedStringArray, duration: float = 2.0) -> void:
	if _column == null:
		return
	if key.is_empty():
		toast_group(title, lines, duration)
		return

	var now: int = Time.get_ticks_msec()
	if _active.has(key):
		var entry: Dictionary = _active[key]
		var existing: PanelContainer = entry.get("card")
		# Never merge into a card that is already playing its exit — it would bump a
		# counter the player is watching fade away.
		if (
			is_instance_valid(existing)
			and not bool(existing.get_meta(&"retiring", false))
			and now - int(entry.get("last_ms", 0)) <= COALESCE_WINDOW_MS
		):
			entry["count"] = int(entry.get("count", 1)) + 1
			entry["last_ms"] = now
			_render(entry["body"], title, lines, int(entry["count"]))
			_fit(existing)
			_pulse(existing)
			_restart_dwell(existing, duration)
			return
		_active.erase(key) # stale / freed — open a fresh card

	_make_room()
	var card: PanelContainer = _spawn()
	var body: VBoxContainer = card.get_child(0)
	_render(body, title, lines, 1)
	_fit(card)
	# Drop our registry entry when this card frees, so the next event opens fresh.
	card.tree_exited.connect(func() -> void:
		if (_active.get(key, {}) as Dictionary).get("card") == card:
			_active.erase(key))
	_active[key] = {"card": card, "body": body, "count": 1, "last_ms": now}
	_restart_dwell(card, duration)


# --- Construction -------------------------------------------------------------

## Build one lane entry and append it to the column. Returns the card; its single
## child is always the VBoxContainer callers append text widgets into.
##
## Two nodes per entry, not one, on purpose. The VBoxContainer owns the layout of
## the SLOT, so the slot is what gets a container-managed position. The card is a
## free child of that slot, which is the only way its position can be tweened at
## all: a container re-sorts its children on every add/remove and would snap a
## container-managed card back to its resting spot mid-slide — exactly during the
## burst where the animation matters.
func _spawn() -> PanelContainer:
	var slot: Control = Control.new()
	slot.name = "ToastSlot"
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN # left-align the lane

	var card: PanelContainer = PanelContainer.new()
	card.name = "ToastCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.modulate.a = 0.0
	card.add_theme_stylebox_override(&"panel", _card_style())
	slot.add_child(card)
	card.set_meta(&"slot", slot)

	var body: VBoxContainer = VBoxContainer.new()
	body.name = "ToastBody"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override(&"separation", 1)
	card.add_child(body)

	# The card sizes itself from its content and the slot mirrors that, so a feed
	# card that re-renders with more lines re-measures without a manual call.
	card.minimum_size_changed.connect(_fit.bind(card))

	_column.add_child(slot)
	return card


## Size the free-floating card to its content and hand that height back to the
## container-managed slot, which is what actually reserves lane space.
func _fit(card: PanelContainer) -> void:
	if not is_instance_valid(card):
		return
	var wanted: Vector2 = card.get_combined_minimum_size()
	card.size = wanted
	var slot: Control = card.get_meta(&"slot") as Control
	if is_instance_valid(slot):
		slot.custom_minimum_size = wanted
	# Pulse grows the card rightward off its left edge, matching the lane anchor
	# (same convention as loot_feed.gd, which shares this edge).
	card.pivot_offset = Vector2(0.0, wanted.y * 0.5)


## (Re)render a card's content: a title carrying the ×N count (hidden at 1) plus the
## event's lines. Reused on create and on every coalesced repeat — the card node
## stays the same so its dwell + pulse tweens survive.
func _render(body: VBoxContainer, title: String, lines: PackedStringArray, count: int) -> void:
	for child: Node in body.get_children():
		body.remove_child(child)
		child.queue_free()

	if not title.is_empty():
		var title_label: Label = PixelUI.text(
			title + (" ×%d" % count if count > 1 else ""), SIZE_TITLE, PixelUI.INK_GOLD
		)
		_tighten(title_label)
		body.add_child(title_label)

	for line: String in lines:
		if line.is_empty():
			continue
		body.add_child(_line_label(line, PixelUI.INK))


func _line_label(text: String, color: Color) -> Label:
	var label: Label = PixelUI.text(text, SIZE_LINE, color)
	_tighten(label)
	return label


## Left-align (a corner lane reads as a list, not a banner) and pull the theme's
## 2px label shadow in to 1px — at 10-12px that shadow is otherwise a fat smear.
## Identical to the alignment+shadow half of [method PixelUI.hud_label]; kept as a
## local because the font, size and colour are already applied by PixelUI.text()
## at the call sites, and re-deriving them here just to hand them back would be
## indirection for its own sake.
func _tighten(label: Label) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override(&"shadow_offset_y", 1)


func _card_style() -> StyleBoxFlat:
	return PixelUI.hud_card(PAD_X, PAD_Y)


# --- Lifetime -----------------------------------------------------------------

## Slots not already playing an exit, oldest first.
func _live_slots() -> Array[Control]:
	var live: Array[Control] = []
	for slot: Node in _column.get_children():
		if slot.get_child_count() == 0:
			continue
		var card: Node = slot.get_child(0)
		if not bool(card.get_meta(&"retiring", false)):
			live.append(slot as Control)
	return live


## Make space for one more card: push the oldest live cards out, and if exits are
## piling up faster than they finish, free the very oldest outright.
func _make_room() -> void:
	var live: Array[Control] = _live_slots()
	while live.size() >= MAX_TOASTS:
		var oldest: Control = live.pop_front()
		_retire(oldest.get_child(0) as PanelContainer)

	# >= not >: this runs BEFORE the caller adds its card, so trimming to HARD_CAP
	# here would leave HARD_CAP + 1 on screen a moment later.
	while _column.get_child_count() >= HARD_CAP:
		var stale: Node = _column.get_child(0)
		_column.remove_child(stale)
		stale.queue_free()


## Cancel any in-flight dwell on this card and start a fresh slide-in / dwell /
## float-out sequence. Idempotent — calling repeatedly just keeps shifting the
## dismissal forward, which is exactly the "burst keeps the stack alive" behaviour.
##
## The tween is created on the CARD, not on Toaster, so it is torn down with the
## card. A tween owned by the autoload would outlive a freed card and error.
func _restart_dwell(card: PanelContainer, dwell: float) -> void:
	if not is_instance_valid(card):
		return
	_kill_dwell(card)

	var tween: Tween = card.create_tween()
	if not bool(card.get_meta(&"shown", false)):
		card.set_meta(&"shown", true)
		card.position = Vector2(-SLIDE_PX, 0.0) # start off toward the left edge
		var slide: PropertyTweener = tween.tween_property(card, ^"position:x", 0.0, ENTER_S)
		slide.set_trans(Tween.TRANS_CUBIC)
		slide.set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(card, ^"modulate:a", 1.0, ENTER_S)
	else:
		tween.tween_property(card, ^"modulate:a", 1.0, 0.10)
		# Settle the card back to its resting spot. Without this, a repeat that
		# arrives while the entry slide is still running kills that tween and
		# strands the card at its half-slid offset for the rest of its life —
		# which is the common case for a kill feed, where the second goblin dies
		# in the same frame as the first.
		tween.parallel().tween_property(card, ^"position", Vector2.ZERO, 0.10)

	tween.tween_interval(dwell)
	tween.tween_callback(func() -> void: card.set_meta(&"retiring", true))
	var rise: PropertyTweener = tween.tween_property(card, ^"position:y", -FLOAT_PX, EXIT_S)
	rise.set_trans(Tween.TRANS_SINE)
	rise.set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(card, ^"modulate:a", 0.0, EXIT_S)
	tween.tween_callback(_free_card.bind(card))
	card.set_meta(&"dwell", tween)


## Push a card out early because a newer one needs its slot. Same exit as a natural
## expiry, just faster, and from wherever the card currently sits.
func _retire(card: PanelContainer) -> void:
	if not is_instance_valid(card) or bool(card.get_meta(&"retiring", false)):
		return
	_kill_dwell(card)
	card.set_meta(&"retiring", true)

	var tween: Tween = card.create_tween()
	var rise: PropertyTweener = tween.tween_property(
		card, ^"position:y", card.position.y - FLOAT_PX, RETIRE_S
	)
	rise.set_trans(Tween.TRANS_SINE)
	rise.set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(card, ^"modulate:a", 0.0, RETIRE_S)
	tween.tween_callback(_free_card.bind(card))
	card.set_meta(&"dwell", tween)


## get_meta() with a null default still errors when the key is absent (Godot only
## honours a non-null default), so the presence check has to be explicit.
func _kill_dwell(card: PanelContainer) -> void:
	if not card.has_meta(&"dwell"):
		return
	var old: Tween = card.get_meta(&"dwell") as Tween
	if old != null and old.is_valid():
		old.kill()


## Free the SLOT, not just the card — the slot is what holds lane height, so
## freeing only the card would leave a permanent gap in the column.
func _free_card(card: PanelContainer) -> void:
	if not is_instance_valid(card):
		return
	var slot: Control = card.get_meta(&"slot") as Control
	if is_instance_valid(slot):
		slot.queue_free()
	else:
		card.queue_free()


## A short scale bump — the "it happened again" feedback on a coalesced card.
## Independent of the dwell tween (touches scale only, never modulate:a or
## position), so the two never fight over the same property.
func _pulse(card: Control) -> void:
	var tween: Tween = card.create_tween()
	tween.tween_property(card, ^"scale", Vector2(1.06, 1.06), 0.08)
	tween.tween_property(card, ^"scale", Vector2.ONE, 0.08)
