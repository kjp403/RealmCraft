extends Control
## In-fight callout line — boss enrages, mechanic warnings, wave counts.
##
## Fights used to shout through Announcer: a 34px title with a 6px outline
## stretched across the middle of the screen, once per mechanic. In a Boss Hunt,
## where the target respawns until the clock runs out, that banner fires every
## few minutes and paints over the exact thing it is warning you about. This is
## the same message in the language the rest of the game already uses for
## feedback — the loot pill / toast card look: translucent near-black, pixel
## font, a hairline of colour and nothing else — parked in a reserved band at the
## very top of the screen, directly under the boss bar. The middle of the screen
## is the fight; nothing this small needs to sit in it.
##
## Self-contained like DungeonHud: it subscribes to its own pushes and shows
## itself, so nothing outside has to hold a reference. Ceremonies still belong to
## Announcer — the split is "the beat between fights" (entering a dungeon, a
## contract completing) vs "a line DURING one", and only the second kind repeats.
##
## ONE line at a time, on purpose. A mechanic callout is only ever about right
## now: "Arcane Ward — wand and book" replacing "Physical Ward" instantly is the
## correct read, and a queue would show the ward you are no longer fighting.

## Band the pill lives in. Only the pill is drawn; the band is the mouse-ignoring
## rect it is centred inside. Hud._reflow_top_center reads this to reserve the
## slot and to place the buff strip under it, and owns the band's own offsets.
const BAND_HEIGHT: float = 26.0

## Dwell before the line fades. An enrage holds a little longer — it is the one
## a player is allowed to miss the least.
const DWELL_S: float = 2.4
const DANGER_DWELL_S: float = 2.8
const FADE_IN_S: float = 0.16
const FADE_OUT_S: float = 0.4
## The pill drifts up this far as it fades — same exit as a toast card.
const RISE_PX: float = 6.0

## Card look, matching LootFeed's pickup pills exactly (they are the sleekest
## thing on the HUD and the thing players see most).
const CARD_BG: Color = Color(0.08, 0.09, 0.12, 0.82)
const PAD_X: int = 9
const PAD_Y: int = 3
const RADIUS: int = 4
## Left accent stripe — the only block of colour on the card, so severity reads
## at a glance without dyeing a whole line of text red.
const ACCENT_W: float = 3.0

## Severity tints. DANGER is the same red BossHuntHud reddens its last life in.
const DANGER: Color = Color(1.0, 0.42, 0.38)
const WARN: Color = Color(1.0, 0.86, 0.5)
const NAME_INK: Color = Color(0.93, 0.90, 0.82)

## Tag shown on an enrage. A label, not a sentence: "ENRAGED · Fungal Heart"
## carries the same news as "The Fungal Heart (Lv 42) enrages!" in half the
## width, and the level is already on the boss bar two inches above it.
const ENRAGED_TAG: String = "ENRAGED"

var _card: PanelContainer
var _accent: ColorRect
var _tag: Label
var _label: Label
## Text currently on screen, so a repeat of the same line just extends its dwell
## instead of restarting the fade (a wind-up that re-fires must not blink).
var _showing: String = ""


func _ready() -> void:
	_build()
	# The escalation beat: this pill plus local_player's camera shake. The shake
	# stays over there — it is gated with every other shake source.
	Client.subscribe(&"boss.enrage", func(payload: Dictionary) -> void:
		alert(_short_name(str(payload.get("name", "The boss"))), true, ENRAGED_TAG))
	# Mechanic callout — the wind-up naming itself, so a move with counterplay
	# can be learned instead of just killing people.
	Client.subscribe(&"boss.callout", func(payload: Dictionary) -> void:
		alert(str(payload.get("text", ""))))


## Show one line. [param danger] is the enrage / wipe-mechanic tier: red accent,
## longer dwell, its own cue. [param tag] is an optional short label ahead of the
## text. Anything already on screen is replaced in place — no fade between two
## callouts, because the new one is the true one.
func alert(text: String, danger: bool = false, tag: String = "") -> void:
	var line: String = text.strip_edges()
	if line.is_empty():
		return

	var accent: Color = DANGER if danger else WARN
	var fresh: bool = line != _showing
	_showing = line
	_accent.color = accent
	_tag.text = tag
	_tag.visible = not tag.is_empty()
	_tag.add_theme_color_override(&"font_color", accent)
	_label.text = line
	# A tagged line already carries its severity in the tag, so the text itself
	# stays plain ink and the card reads as a label rather than a wall of red.
	_label.add_theme_color_override(&"font_color", NAME_INK if _tag.visible else accent)
	_fit()

	if fresh:
		if danger:
			# Lower and quieter than a menu reveal: it reads as the fight
			# escalating, not as a button.
			UISound.play(UISound.REVEAL, 0.7, -3.0)
		_pulse()
	_restart_dwell(DANGER_DWELL_S if danger else DWELL_S)


## "The Fungal Heart (Lv 42)" -> "The Fungal Heart". HostileNpc stamps the level
## into display_name for the over-head plate; on the pill it is noise, and the
## boss bar right above already prints it.
func _short_name(display_name: String) -> String:
	# Case-insensitive: the suffix is authored "(Lv %d)" but a boss whose own name
	# ends in a bracketed level from content should lose it just the same.
	var cut: int = display_name.to_lower().rfind(" (lv ")
	return display_name.left(cut) if cut > 0 else display_name


## Full-width, mouse-ignoring band at the top of the screen. The vertical slot is
## Hud._reflow_top_center's to set (it docks under the boss bar when one is up);
## the offsets here are only what the band wears until the first re-flow.
##
## The pill is a free child rather than a container-managed one so its
## rise-and-fade can be tweened — a container would snap it back to its resting
## spot mid-tween.
func _build() -> void:
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_top = 8.0
	offset_bottom = 8.0 + BAND_HEIGHT
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_card = PanelContainer.new()
	_card.name = "AlertCard"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.modulate.a = 0.0
	_card.add_theme_stylebox_override(&"panel", _card_style())
	add_child(_card)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 7)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)

	_accent = ColorRect.new()
	_accent.custom_minimum_size = Vector2(ACCENT_W, 0.0)
	_accent.color = WARN
	_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_accent)

	_tag = _line_label(PixelUI.SIZE_TINY, DANGER)
	_tag.visible = false
	row.add_child(_tag)

	_label = _line_label(PixelUI.SIZE_CAPTION, NAME_INK)
	row.add_child(_label)

	# A longer line re-measures itself without anyone calling _fit by hand.
	_card.minimum_size_changed.connect(_fit)
	resized.connect(_fit)


func _line_label(size: int, color: Color) -> Label:
	var label: Label = PixelUI.text("", size, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The theme's 2px label shadow is a smear under a 10-12px pixel font.
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	return label


## Size the free-floating pill to its text and centre it in the band.
func _fit() -> void:
	if _card == null or not is_instance_valid(_card):
		return
	var wanted: Vector2 = _card.get_combined_minimum_size()
	_card.size = wanted
	_card.pivot_offset = wanted * 0.5
	_card.position = Vector2(
		(size.x - wanted.x) * 0.5, (BAND_HEIGHT - wanted.y) * 0.5
	)


func _card_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = CARD_BG
	style.set_corner_radius_all(RADIUS)
	style.content_margin_left = PAD_X
	style.content_margin_right = PAD_X + 2
	style.content_margin_top = PAD_Y
	style.content_margin_bottom = PAD_Y
	return style


## Fade in (if hidden), hold, drift up and fade out. Restartable — a repeat of
## the same line just pushes the dismissal forward.
func _restart_dwell(dwell: float) -> void:
	# get_meta() errors on a missing key even with a default, so check first.
	if _card.has_meta(&"dwell"):
		var old: Tween = _card.get_meta(&"dwell") as Tween
		if old != null and old.is_valid():
			old.kill()

	var rest_y: float = (BAND_HEIGHT - _card.size.y) * 0.5
	_card.position.y = rest_y
	var tween: Tween = _card.create_tween()
	tween.tween_property(_card, ^"modulate:a", 1.0, FADE_IN_S)
	tween.tween_interval(dwell)
	var rise: PropertyTweener = tween.tween_property(
		_card, ^"position:y", rest_y - RISE_PX, FADE_OUT_S
	)
	rise.set_trans(Tween.TRANS_SINE)
	rise.set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_card, ^"modulate:a", 0.0, FADE_OUT_S)
	tween.tween_callback(func() -> void: _showing = "")
	_card.set_meta(&"dwell", tween)


## The "this is new" bump — scale only, so it never fights the dwell tween over
## modulate or position. Same gesture as a coalesced toast.
func _pulse() -> void:
	var tween: Tween = _card.create_tween()
	tween.tween_property(_card, ^"scale", Vector2(1.04, 1.04), 0.08)
	tween.tween_property(_card, ^"scale", Vector2.ONE, 0.10)
