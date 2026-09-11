class_name FishingComboHud
extends PanelContainer
## The fishing combo meter: a row of pips that fills as consecutive baited
## catches stack up, the XP bonus they are currently paying, and how much bait is
## left to pay for the next one.
##
## WHY THIS EXISTS
## [FishingComboManager] has shipped the whole mechanic — streak, multiplier,
## bait spend, three break conditions — with no readout at all. Everything it did
## was carried by the XP drop warming from sea-blue toward gold ([XpTrackerHud]),
## plus two toasts at the extremes. That is feedback you can only read by
## remembering what the last number looked like, so the combo was invisible: the
## number was bigger, and nothing said why, or that standing still was the reason.
##
## WHY IT IS BOTTOM-CENTRE AND NOT IN THE UPPER-RIGHT RAIL
## Measured at the 960x540 base viewport, which is the FLOOR for the HUD rect
## (a taller window only makes it taller), the upper-right column is full:
##   minimap   y   8..120
##   open bag  y 162..492, x 724..948
## That leaves one clear slot, y 120..162, and the XP orb already sits in it at
## y 128..176 — overflowing 14px into the bag as it is. Stacking a 24px pill
## above the orb pushes it to y 160..208, entirely under an open bag, and drags
## the XP floating numbers with it: their anchor is tuned to top out at y 132,
## and they would top out at y 164. The orb cannot move, and the space directly
## left of it belongs to those same floating numbers.
##
## So the meter goes where a combo meter goes in any action game: bottom-centre,
## directly above the ability bar, in the cluster the player is already watching.
## That band is clear of the bag (x 724..), the chat/loot column (x ..268) and
## the minimap. It wears run_clock_chip's pill so it still reads as one family
## with the run clocks, via [method RunClockChip.style_only] — it takes the LOOK
## and does its own anchoring.
##
## WHY THE CHIP OUTLIVES THE STREAK
## Visibility is keyed to FISHING, not to the streak. A streak breaks every time
## you finish a spot and step to the next one, and a chip that blinked out on
## each break would flicker through a whole session — and the rebuild is the
## thing worth watching. So it stays up for the lapse window after the last
## catch, showing the streak at zero and climbing again in place.
##
## SERVER-FED, NEVER DERIVED. The streak, the multiplier and the bait count all
## ride the gather push ([MineableNode] builds it); PlayerResource is server-only,
## so there is nothing here to compute locally even if it were worth the drift.

const CHIP: GDScript = preload("res://source/client/ui/hud/run_clock_chip.gd")

const PIP_WIDTH: float = 3.0
const PIP_GAP: float = 1.0
const PIP_HEIGHT: float = 8.0

## Unlit pip — present enough to show how far there is left to go.
const PIP_EMPTY: Color = Color(1.0, 1.0, 1.0, 0.14)
## The break flash. Held briefly so a streak that ends between two frames is
## still seen ending.
const PIP_BROKEN: Color = Color(1.0, 0.42, 0.38)
const BREAK_FLASH_MS: int = 900

## The chip starts dimming this long before the streak lapses, so "your combo is
## about to expire" is visible ON the meter instead of arriving as a surprise.
const FADE_LEAD_MS: int = 12_000
## Floor for that fade — the chip goes quiet, never unreadable, before it leaves.
const FADE_FLOOR: float = 0.35

## The ability bar's own top offset from the bottom of the screen (hud.tscn,
## AbilityBar: anchors bottom, offset_top -104). The meter sits above it.
const ABILITY_BAR_TOP: float = -104.0
const GAP_ABOVE_BAR: float = 8.0

## One pip per catch of headroom. Asked of the manager that owns the ramp rather
## than re-derived here: a balance pass that halves [constant
## FishingComboManager.STEP] must lengthen the meter, not silently cap it at half
## fill — and the division has a float-truncation trap in it that this widget has
## no business owning twice (see [method FishingComboManager.steps_to_cap]).
##
## A member var and not a const: a const initialiser is folded at PARSE time,
## which would make this HUD's parse depend on FishingComboManager and, through
## it, on PlayerResource. That kind of edge takes a world down on a cold load
## while passing CI. Instantiation-time costs one call, once, per client.
var _pips_max: int = FishingComboManager.steps_to_cap()

var _streak: int = 0
var _multiplier: float = 1.0
var _bait: int = 0
var _has_bucket: bool = false
## Ticks at the last FISHING catch. Drives both the dim-out and the auto-hide.
var _last_catch_ms: int = 0
var _break_flash_until_ms: int = 0

var _pips: Control
var _multiplier_label: Label
var _bait_label: Label


func _ready() -> void:
	_build_ui()
	visible = false
	set_process(false)
	ClientState.gather_succeeded.connect(_on_gather)
	# The bucket can also change while the chip is up without a catch behind it
	# (a Fill mid-session), and "out of bait" is the one line on here that has to
	# stop being true the moment it stops being true.
	ClientState.stored_bait_changed.connect(_on_bait_changed)


# ---------------------------------------------------------------------------
# Intake
# ---------------------------------------------------------------------------

## Read the combo off the gather push. Non-fishing nodes are ignored outright
## rather than treated as a break: a player who mines one rock between casts has
## not lost their streak, and the server has not said they have.
func _on_gather(result: Dictionary) -> void:
	if str(result.get("job", "")) != "fishing":
		return

	var streak: int = int(result.get("combo_streak", 0))
	if _streak > 0 and streak == 0:
		_break_flash_until_ms = Time.get_ticks_msec() + BREAK_FLASH_MS

	_streak = streak
	_multiplier = float(result.get("combo_multiplier", 1.0))
	_last_catch_ms = Time.get_ticks_msec()
	_read_bucket()
	_refresh()

	modulate.a = 1.0
	visible = true
	set_process(true)


func _on_bait_changed() -> void:
	if not visible:
		return
	_read_bucket()
	_refresh()


func _read_bucket() -> void:
	_bait = ClientState.stored_bait
	_has_bucket = ClientState.has_bait_bucket


# ---------------------------------------------------------------------------
# Lifetime
# ---------------------------------------------------------------------------

## Dim toward the lapse, then leave. Runs only while the chip is on screen, and
## the only per-frame work is one lerp.
func _process(_delta: float) -> void:
	var idle_ms: int = Time.get_ticks_msec() - _last_catch_ms
	if idle_ms >= FishingComboManager.LAPSE_MS:
		visible = false
		set_process(false)
		_streak = 0
		_multiplier = 1.0
		return
	var lead: int = mini(FADE_LEAD_MS, FishingComboManager.LAPSE_MS)
	var into_fade: int = idle_ms - (FishingComboManager.LAPSE_MS - lead)
	modulate.a = (
		1.0 if into_fade <= 0
		else lerpf(1.0, FADE_FLOOR, clampf(float(into_fade) / float(lead), 0.0, 1.0))
	)
	# The break flash is the one thing the pips draw that changes without a new
	# push, so it is the one thing that has to ask for its own redraw.
	if _break_flash_until_ms > 0 and Time.get_ticks_msec() >= _break_flash_until_ms:
		_break_flash_until_ms = 0
		_pips.queue_redraw()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _refresh() -> void:
	_pips.queue_redraw()

	_multiplier_label.text = "+%d%% XP" % roundi((_multiplier - 1.0) * 100.0)
	_multiplier_label.add_theme_color_override(&"font_color", _ramp_color())

	# Bait is the ONLY thing that can break a streak a player is otherwise
	# playing correctly for — standing still and staying on one spot are visible
	# to them, an empty bucket is not. So it gets the urgent ink, and the "no
	# bucket" case is named separately: the charge survives dropping the bucket,
	# so "out of bait" would be a lie for someone who left theirs in the bank.
	if not _has_bucket:
		_bait_label.text = "no bucket"
		_bait_label.add_theme_color_override(&"font_color", CHIP.URGENT)
	elif _bait <= 0:
		_bait_label.text = "out of bait"
		_bait_label.add_theme_color_override(&"font_color", CHIP.URGENT)
	else:
		_bait_label.text = "%s bait" % NumberFormat.with_commas(_bait)
		_bait_label.add_theme_color_override(&"font_color", CHIP.DETAIL)


## Sea-blue at rest, gold at the cap — the SAME ramp the XP drops are warmed
## along ([method XpTrackerHud._combo_tint]), so the meter and the number it
## explains move together instead of being two unrelated colour stories.
func _ramp_color() -> Color:
	var span: float = maxf(0.001, FishingComboManager.MAX_MULTIPLIER - 1.0)
	var t: float = clampf((_multiplier - 1.0) / span, 0.0, 1.0)
	return XpTrackerHud.tint_for(&"fishing").lerp(PixelUI.INK_GOLD, t)


func _draw_pips() -> void:
	var lit: int = clampi(_streak, 0, _pips_max)
	var broken: bool = _break_flash_until_ms > Time.get_ticks_msec()
	var on: Color = PIP_BROKEN if broken else _ramp_color()
	for i: int in _pips_max:
		# A broken streak lights the WHOLE meter red for the flash, then empties:
		# the point of the flash is that you see the thing you lost.
		var filled: bool = broken or i < lit
		_pips.draw_rect(
			Rect2(
				Vector2(float(i) * (PIP_WIDTH + PIP_GAP), 0.0),
				Vector2(PIP_WIDTH, PIP_HEIGHT)
			),
			on if filled else PIP_EMPTY
		)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

## Bottom-centre, riding directly above the ability bar.
##
## Anchored rather than placed by [method HUD._place_right_rail]: nothing else
## competes for this band, so there is no stack to take part in and no reason to
## make the HUD re-flow when a streak starts. ABILITY_BAR_TOP mirrors the offset
## hud.tscn gives that bar — if it moves, this follows it there by hand, which is
## why the number is named rather than inlined.
func _place() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_top = ABILITY_BAR_TOP - GAP_ABOVE_BAR
	offset_bottom = ABILITY_BAR_TOP - GAP_ABOVE_BAR


## One thin pill in the upper-right rail, wearing [constant CHIP] so it cannot
## drift from the dungeon / boss-hunt clocks it stacks with. Built in code for
## the same reason they are: hud.tscn's node table stays untouched.
func _build_ui() -> void:
	# The pill's look from the run clocks; its position is this widget's own —
	# see the class docs for why the rail could not take it.
	var row: HBoxContainer = CHIP.style_only(self)
	_place()

	_pips = Control.new()
	_pips.custom_minimum_size = Vector2(
		float(_pips_max) * (PIP_WIDTH + PIP_GAP) - PIP_GAP, PIP_HEIGHT
	)
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pips.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pips.draw.connect(_draw_pips)
	row.add_child(_pips)

	_multiplier_label = CHIP.timer_label()
	_multiplier_label.text = "+0% XP"
	row.add_child(_multiplier_label)

	_bait_label = CHIP.detail_label()
	_bait_label.text = "0 bait"
	row.add_child(_bait_label)
