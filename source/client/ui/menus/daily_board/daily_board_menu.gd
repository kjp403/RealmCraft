extends MenuShell
## Daily quest board. Themed cards (type icon + objective + progress bar + reward
## chips + a per-state claim/skip button), a completion-bonus track, a skip budget
## and a reset countdown. Built on MenuShell so it gets the shared dim modal
## backdrop (no more click-through to the HUD) + themed card + Close chrome for
## free. Auto-fetches on open and updates live from the server's daily.progress push.
##
## Reward chips name their DESTINATION, not just a number. "+12,000 XP" on its own
## was unanswerable — character level is derived from weapon masteries, so the XP
## that matters is mastery XP and it lands in whatever weapon you are holding. The
## footnote under the bonus track says exactly that, once, rather than repeating it
## on every card.

const COLOR_GOLD: Color = Color(1.0, 0.92, 0.72)
const COLOR_ACCENT: Color = Color(0.96, 0.74, 0.16)
const COLOR_GREEN: Color = Color(0.52, 0.79, 0.42)
const COLOR_MUTED: Color = Color(0.7, 0.72, 0.78)
const COLOR_CARD: Color = Color(0.11, 0.13, 0.18)
const COLOR_TILE: Color = Color(0.06, 0.075, 0.11)
const COLOR_TRACK: Color = Color(0.04, 0.05, 0.08)
const COLOR_ICON: Color = Color(0.9, 0.85, 0.7)
const COLOR_XP: Color = Color(0.62, 0.79, 1.0)   # experience — cool blue
const COLOR_COIN: Color = Color(1.0, 0.82, 0.42) # gold currency — amber

## Indexed by DailyQuestTemplate.Kind (KILL, COLLECT, SPAR, DUNGEON, CRAFT).
const KIND_ICON_NAMES: PackedStringArray = ["kill", "collect", "spar", "dungeon", "craft"]

var _reset_pill: Label
var _entries_box: VBoxContainer
## Skips left today, from the last board payload. Drives the per-card Skip button's
## enabled state without a second round trip.
var _skips_left: int = 0
var _skips_per_day: int = 0


func _ready() -> void:
	build_shell("Daily quests", null, true)
	visibility_changed.connect(_on_visibility_changed)

	# Reset countdown sits in the header's centre slot as a pill.
	_reset_pill = Label.new()
	_reset_pill.add_theme_stylebox_override(&"normal", _flat(COLOR_TILE, 999, Color(1, 1, 1, 0.08), 1))
	_reset_pill.add_theme_color_override(&"font_color", COLOR_MUTED)
	_reset_pill.add_theme_font_size_override(&"font_size", 12)
	header_center.add_child(_reset_pill)

	# Body: a scrolling column so a longer set never overflows the card.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	_entries_box = VBoxContainer.new()
	_entries_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries_box.add_theme_constant_override(&"separation", 10)
	scroll.add_child(_entries_box)

	# Live progress: the server pushes the full board whenever a daily counter
	# advances, so an open board updates without reopening.
	Client.subscribe(&"daily.progress", _on_progress)


func _on_visibility_changed() -> void:
	if visible:
		_refresh()


## Live board push (daily.progress) — only reflow if the board is on screen.
func _on_progress(payload: Dictionary) -> void:
	if visible:
		_apply(payload)


## Called by HUD.display_menu when opened with an arg (unused — one set per player).
func open(_unused: int) -> void:
	_refresh()


func _refresh() -> void:
	_message("Loading...")
	Client.request_data(
		&"quest.board.info",
		_apply,
		{},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _apply(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		_message("Couldn't load dailies: %s" % response.get("reason", "unknown"))
		return
	var entries: Array = response.get("entries", [])
	if entries.is_empty():
		_message("No dailies available at your level yet.")
		return

	for child: Node in _entries_box.get_children():
		child.queue_free()

	_skips_left = int(response.get("skips_left", 0))
	_skips_per_day = int(response.get("skips_per_day", 0))

	var refresh_at_ms: int = int(response.get("refresh_at_ms", 0))
	var seconds_left: int = maxi(0, int((refresh_at_ms - Time.get_unix_time_from_system() * 1000.0) / 1000.0))
	_reset_pill.text = "  Resets in %s  ·  %d/%d skips left  " % [
		_fmt_duration(seconds_left), _skips_left, _skips_per_day
	]

	_entries_box.add_child(_build_bonus_track(response, entries))
	for entry: Dictionary in entries:
		_entries_box.add_child(_build_row(entry))
	_entries_box.add_child(_build_footnote())


## The one place the board explains where its XP goes. A block, not a chip on every
## card - the answer is the same for all three.
func _build_footnote() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 3)
	col.add_child(_footnote_line(
		"Mastery XP trains the weapon in your hands — the same bar your kills fill, "
		+ "and what your combat level is built from."
	))
	col.add_child(_footnote_line(
		"Can't reach one of these? Skip it for a different task (%d left today)."
		% _skips_left
	))
	return col


func _footnote_line(text: String) -> Label:
	var note: Label = Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override(&"font_color", COLOR_MUTED)
	note.add_theme_font_size_override(&"font_size", 11)
	return note


# ---------------------------------------------------------------------------
# Completion-bonus track
# ---------------------------------------------------------------------------

func _build_bonus_track(response: Dictionary, entries: Array) -> Control:
	var total: int = entries.size()
	var claimed: int = 0
	for e: Variant in entries:
		if bool((e as Dictionary).get("claimed", false)):
			claimed += 1
	var done: bool = bool(response.get("all_claimed", false))
	var bonus_mastery_xp: int = int(response.get("bonus_mastery_xp", 0))
	var bonus_gold: int = int(response.get("bonus_gold", 0))

	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override(&"panel", _flat(COLOR_TILE, 10, COLOR_ACCENT, 1 if done else 0))
	var row: HBoxContainer = _padded_row(panel, 10)
	row.add_theme_constant_override(&"separation", 12)

	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override(&"separation", 6)
	row.add_child(col)

	var head: Label = Label.new()
	head.text = "Daily bonus earned" if done else "Complete all %d for a bonus" % total
	head.add_theme_color_override(&"font_color", COLOR_ACCENT if done else COLOR_GOLD)
	head.add_theme_font_size_override(&"font_size", 13)
	col.add_child(head)

	var seg: HBoxContainer = HBoxContainer.new()
	seg.add_theme_constant_override(&"separation", 5)
	col.add_child(seg)
	for i: int in total:
		var pip: PanelContainer = PanelContainer.new()
		pip.custom_minimum_size = Vector2(0, 5)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.add_theme_stylebox_override(&"panel", _flat(COLOR_ACCENT if i < claimed else COLOR_TRACK, 3))
		seg.add_child(pip)

	var reward: Label = Label.new()
	reward.text = "+%s Mastery XP  ·  %s g" % [
		_fmt_amount(bonus_mastery_xp), _fmt_amount(bonus_gold)
	]
	reward.add_theme_color_override(&"font_color", COLOR_ACCENT if done else COLOR_MUTED)
	reward.add_theme_font_size_override(&"font_size", 13)
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(reward)
	return panel


# ---------------------------------------------------------------------------
# Quest card
# ---------------------------------------------------------------------------

func _build_row(entry: Dictionary) -> Control:
	var complete: bool = bool(entry.get("complete", false))
	var claimed: bool = bool(entry.get("claimed", false))
	var progress: int = int(entry.get("progress", 0))
	var required: int = maxi(1, int(entry.get("required", 1)))

	var card: PanelContainer = PanelContainer.new()
	card.add_theme_stylebox_override(&"panel", _flat(COLOR_CARD, 12, COLOR_ACCENT if (complete and not claimed) else Color(1, 1, 1, 0.06), 1))
	var row: HBoxContainer = _padded_row(card, 14)
	row.add_theme_constant_override(&"separation", 14)

	var tile: PanelContainer = PanelContainer.new()
	tile.custom_minimum_size = Vector2(46, 46)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.add_theme_stylebox_override(&"panel", _flat(COLOR_TILE, 10))
	var tile_pad: MarginContainer = MarginContainer.new()
	for s: String in ["left", "right", "top", "bottom"]:
		tile_pad.add_theme_constant_override("margin_" + s, 10)
	tile.add_child(tile_pad)
	var icon: TextureRect = TextureRect.new()
	icon.texture = _icon_for(int(entry.get("kind", 0)))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = COLOR_MUTED if claimed else COLOR_ICON
	tile_pad.add_child(icon)
	row.add_child(tile)

	var mid: VBoxContainer = VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override(&"separation", 7)
	row.add_child(mid)

	var desc: Label = Label.new()
	desc.text = str(entry.get("description", "?"))
	desc.add_theme_color_override(&"font_color", COLOR_MUTED if claimed else COLOR_GOLD)
	desc.add_theme_font_size_override(&"font_size", 15)
	mid.add_child(desc)

	# Where to go. A daily naming a monster the player has never met is only
	# actionable with this line — it's the other half of the Skip button.
	var where: String = str(entry.get("location_hint", ""))
	if not where.is_empty():
		var hint: Label = Label.new()
		hint.text = where
		hint.add_theme_color_override(&"font_color", COLOR_MUTED)
		hint.add_theme_font_size_override(&"font_size", 11)
		mid.add_child(hint)

	var prow: HBoxContainer = HBoxContainer.new()
	prow.add_theme_constant_override(&"separation", 10)
	mid.add_child(prow)
	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = required
	bar.value = progress
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override(&"background", _flat(COLOR_TRACK, 4))
	bar.add_theme_stylebox_override(&"fill", _flat(COLOR_GREEN if complete else COLOR_ACCENT, 4))
	prow.add_child(bar)
	var count: Label = Label.new()
	count.text = "%d / %d" % [progress, required]
	count.add_theme_color_override(&"font_color", COLOR_GREEN if complete else COLOR_MUTED)
	count.add_theme_font_size_override(&"font_size", 12)
	prow.add_child(count)

	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override(&"separation", 6)
	mid.add_child(chips)
	chips.add_child(_chip(
		"%s Mastery XP" % _fmt_amount(int(entry.get("reward_mastery_xp", 0))), COLOR_XP
	))
	chips.add_child(_chip("%s g" % _fmt_amount(int(entry.get("reward_gold", 0))), COLOR_COIN))

	# Right side: claim it, or mark it claimed, or — while it's still in progress —
	# offer the way out for a daily this player can't actually reach.
	if claimed or complete:
		row.add_child(_build_claim(entry, claimed))
	else:
		row.add_child(_build_skip(entry))
	return card


## The Skip button for an in-progress daily. Always shown (so the option is
## discoverable before you need it) but disabled once the day's budget is spent,
## with the reason on the button itself rather than in a toast after the click.
func _build_skip(entry: Dictionary) -> Control:
	var skip: Button = Button.new()
	var spent: bool = _skips_left <= 0
	skip.text = "Skip" if not spent else "No skips"
	skip.disabled = spent
	skip.tooltip_text = (
		"Swap this for a different daily. %d of %d skips left today."
		% [_skips_left, _skips_per_day]
	) if not spent else "You've used all %d skips today." % _skips_per_day
	skip.custom_minimum_size = Vector2(84, 38)
	skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skip.add_theme_stylebox_override(&"normal", _flat(COLOR_TILE, 8, COLOR_MUTED, 1))
	skip.add_theme_stylebox_override(&"hover", _flat(COLOR_TILE.lightened(0.1), 8, COLOR_GOLD, 1))
	skip.add_theme_stylebox_override(&"pressed", _flat(COLOR_TILE.darkened(0.1), 8, COLOR_GOLD, 1))
	skip.add_theme_stylebox_override(&"disabled", _flat(COLOR_TILE, 8))
	skip.add_theme_color_override(&"font_color", COLOR_MUTED)
	skip.add_theme_color_override(&"font_hover_color", COLOR_GOLD)
	skip.add_theme_color_override(&"font_disabled_color", Color(COLOR_MUTED, 0.4))
	skip.pressed.connect(_skip.bind(int(entry.get("template_id", 0))))
	return skip


func _skip(template_id: int) -> void:
	Client.request_data(
		&"quest.board.skip",
		_on_skipped,
		{"template_id": template_id},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


## The skip handler hands back the whole refreshed board, so re-render straight
## from it — no follow-up fetch, no flicker through the pre-skip card.
func _on_skipped(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		_message("Couldn't skip: %s" % response.get("reason", "unknown"))
		return
	_apply(response)


func _build_claim(entry: Dictionary, claimed: bool) -> Control:
	if claimed:
		var done: Label = Label.new()
		done.text = "Claimed ✓"
		done.add_theme_color_override(&"font_color", COLOR_GREEN)
		done.add_theme_font_size_override(&"font_size", 13)
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return done
	# Reached only when the objective is complete (see _build_row): offer the claim.
	var claim: Button = Button.new()
	claim.text = "Claim"
	claim.custom_minimum_size = Vector2(84, 38)
	claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	claim.add_theme_stylebox_override(&"normal", _flat(COLOR_ACCENT, 8))
	claim.add_theme_stylebox_override(&"hover", _flat(COLOR_ACCENT.lightened(0.08), 8))
	claim.add_theme_stylebox_override(&"pressed", _flat(COLOR_ACCENT.darkened(0.1), 8))
	claim.add_theme_color_override(&"font_color", Color(0.15, 0.11, 0.03))
	claim.add_theme_color_override(&"font_hover_color", Color(0.15, 0.11, 0.03))
	claim.pressed.connect(_claim.bind(int(entry.get("template_id", 0))))
	return claim


func _claim(template_id: int) -> void:
	Client.request_data(
		&"quest.board.claim",
		_on_claimed,
		{"template_id": template_id},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _on_claimed(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		_message("Claim failed: %s" % response.get("reason", "unknown"))
		return
	_refresh()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## Replace the board body with a single centered message (loading / error / empty).
func _message(text: String) -> void:
	for child: Node in _entries_box.get_children():
		child.queue_free()
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", COLOR_MUTED)
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_entries_box.add_child(label)


## A card/panel + inner MarginContainer + HBox, returning the HBox for content.
func _padded_row(parent: PanelContainer, margin: int) -> HBoxContainer:
	var pad: MarginContainer = MarginContainer.new()
	for s: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, margin)
	parent.add_child(pad)
	var row: HBoxContainer = HBoxContainer.new()
	pad.add_child(row)
	return row


func _chip(text: String, text_color: Color) -> Control:
	var lbl: Label = Label.new()
	lbl.text = " " + text + " "
	lbl.add_theme_stylebox_override(&"normal", _flat(COLOR_TILE, 999))
	lbl.add_theme_color_override(&"font_color", text_color)
	lbl.add_theme_font_size_override(&"font_size", 12)
	return lbl


## A flat rounded StyleBox. [param border_w] 0 = no border.
func _flat(bg: Color, radius: int, border_col: Color = Color.BLACK, border_w: int = 0) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border_w > 0:
		sb.set_border_width_all(border_w)
		sb.border_color = border_col
	return sb


func _icon_for(kind: int) -> Texture2D:
	if kind < 0 or kind >= KIND_ICON_NAMES.size():
		return null
	return load("res://assets/sprites/ui/daily/%s.png" % KIND_ICON_NAMES[kind]) as Texture2D


## 12000 -> "12,000". Reward numbers here run to five figures now; unseparated
## they read as noise and a misplaced digit is invisible.
func _fmt_amount(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" + out) if value < 0 else out


func _fmt_duration(seconds: int) -> String:
	if seconds <= 0:
		return "now"
	@warning_ignore("integer_division")
	var h: int = seconds / 3600
	@warning_ignore("integer_division")
	var m: int = (seconds % 3600) / 60
	if h > 0:
		return "%dh %dm" % [h, m]
	return "%dm" % m
