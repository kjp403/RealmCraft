extends MenuShell
## The Daily Skilling Board: three cards, one per rolled skill slot.
##
## A card is in one of two states, and the whole layout follows from that:
##   OFFERED  — the skill is known but the player has not committed. The card
##              shows the three difficulty choices side by side with the exact
##              target and the chest each one pays, so the decision is made with
##              real numbers rather than after the fact.
##   ACCEPTED — the choice is locked. The picker is replaced by a progress bar
##              reading "145 / 300 logs cut", and a Claim button once it fills.
##
## THREE ACROSS, NOT A LIST. The old board was a vertical list because its
## entries were unrelated errands. These three are a choice set — you weigh them
## against each other and decide where the day goes — and that comparison only
## works if they are side by side.
##
## ZERO GAMEPLAY MATH. Targets, rewards, chest tiers, outfit chances, the unit
## noun and the reset time all arrive on the board payload from
## DailyQuestManager. This file decides layout and nothing else; if a number is
## not on the payload it does not get shown.
##
## PIXEL-ART CHROME. Panels are 9-slice frames from [PixelUI], not StyleBoxFlat
## with rounded corners — a rounded, anti-aliased panel is the single loudest
## "this is a web app" tell in a 2D pixel game. Type is the pixel font with
## filtering off, and the root sets NEAREST once so every child inherits it.

## Colours, frames, chest art and type all come from [PixelUI] so this screen and
## the reward window cannot drift apart.

## How long a progress bar takes to slide to its new value on a live push. Short
## enough to keep up with rapid gathering, long enough to read as motion.
const BAR_FILL_TIME: float = 0.35

var _reset_pill: Label
## slot -> the ProgressBar on that card, so a live daily.progress push can tween
## the bar instead of rebuilding the whole board and snapping it.
var _bars: Dictionary[int, ProgressBar] = {}
## slot -> progress as of the last build, so a rebuild triggered by a live push
## can animate the bar from where the player last saw it instead of snapping.
var _last_progress: Dictionary[int, int] = {}
## Slots already seen complete. The board is re-pushed on every gather, so
## without this the completion cue would fire on every swing after the target is
## hit rather than once, on the swing that hit it.
var _completed_slots: Dictionary[int, bool] = {}
var _cards_row: HBoxContainer
var _body: VBoxContainer
## Slot currently awaiting a server answer, so a double-click cannot commit twice.
var _pending_slot: int = -1


func _ready() -> void:
	build_shell("Daily Skilling Board", null, true)
	# One call, before anything is built: texture_filter inherits, so every frame,
	# chest sprite and glyph created below is drawn NEAREST.
	PixelUI.make_pixel_perfect(self)
	visibility_changed.connect(_on_visibility_changed)

	_reset_pill = PixelUI.text("", PixelUI.SIZE_CAPTION, PixelUI.INK_DIM)
	_reset_pill.add_theme_stylebox_override(&"normal", PixelUI.frame("frame_iron", 8))
	header_center.add_child(_reset_pill)


	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override(&"separation", 12)
	scroll.add_child(_body)

	_cards_row = HBoxContainer.new()
	_cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_row.add_theme_constant_override(&"separation", 12)
	_body.add_child(_cards_row)

	# Live progress: the server pushes the whole board whenever a counter moves,
	# so an open board tracks a gather in real time without reopening.
	Client.subscribe(&"daily.progress", _on_progress)


func _on_visibility_changed() -> void:
	if visible:
		_refresh()


func _on_progress(payload: Dictionary) -> void:
	if visible:
		_apply(payload)


## Entry point from HUD.display_menu (one board per player, so the arg is unused).
func open(_unused: Variant = null) -> void:
	_refresh()


func _refresh() -> void:
	_message("Loading...")
	Client.request_data(
		&"quest.board.info",
		_apply,
		{},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


# ---------------------------------------------------------------------------
# Board
# ---------------------------------------------------------------------------

func _apply(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		_message("Couldn't load today's board: %s" % response.get("reason", "unknown"))
		return
	var entries: Array = response.get("entries", [])
	if entries.is_empty():
		_message("No skilling tasks available yet.")
		return

	for child: Node in _body.get_children():
		child.queue_free()
	# Bars are rebuilt with the cards; the VALUES they animate from survive in
	# _last_progress.
	_bars.clear()

	_cards_row = HBoxContainer.new()
	_cards_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_row.add_theme_constant_override(&"separation", 12)
	_body.add_child(_cards_row)
	for entry: Variant in entries:
		if entry is Dictionary:
			_cards_row.add_child(_build_card(entry as Dictionary))

	_body.add_child(_build_bonus_track(response, entries))
	_body.add_child(_build_footnote())

	var refresh_at_ms: int = int(response.get("refresh_at_ms", 0))
	var seconds_left: int = maxi(
		0, int((refresh_at_ms - Time.get_unix_time_from_system() * 1000.0) / 1000.0)
	)
	_reset_pill.text = "  New skills in %s  " % _fmt_duration(seconds_left)


# ---------------------------------------------------------------------------
# Card
# ---------------------------------------------------------------------------

func _build_card(entry: Dictionary) -> Control:
	var accepted: bool = bool(entry.get("accepted", false))
	var complete: bool = bool(entry.get("complete", false))
	var claimed: bool = bool(entry.get("claimed", false))

	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(260, 0)
	# Carved stone by default; a finished card switches to the gold frame so the
	# one you can claim is obvious from across the screen without reading it.
	var frame_name: String = "frame_stone"
	if complete and not claimed:
		frame_name = "frame_gold"
	PixelUI.panel(card, frame_name, 10)
	if claimed:
		card.modulate = Color(0.62, 0.62, 0.66)

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 6)
	card.add_child(col)

	col.add_child(_build_header(entry, claimed))
	col.add_child(HSeparator.new())

	if not accepted:
		col.add_child(_build_picker(entry))
	else:
		col.add_child(_build_tracker(entry))
		col.add_child(_build_reward_strip(entry))
		var spacer: Control = Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(spacer)
		col.add_child(_build_action(entry))
	return card


## Skill icon + name + level. The icon comes from the job's own JobPerks resource,
## so a new skill brings its art with it and this never needs a lookup table.
func _build_header(entry: Dictionary, claimed: bool) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)

	var tile: PanelContainer = PanelContainer.new()
	tile.custom_minimum_size = Vector2(44, 44)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.add_theme_stylebox_override(&"panel", PixelUI.slot_style())
	var host: CenterContainer = CenterContainer.new()
	tile.add_child(host)
	var perks: JobPerks = JobRegistry.perks_for(StringName(str(entry.get("skill", ""))))
	if perks != null and perks.icon != null:
		var icon: TextureRect = PixelIcon.mount(host, perks.icon)
		icon.modulate = PixelUI.INK_DIM if claimed else Color.WHITE
	row.add_child(tile)

	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override(&"separation", 2)
	row.add_child(col)

	col.add_child(PixelUI.text(
		str(entry.get("skill_name", "?")), PixelUI.SIZE_HEADING,
		PixelUI.INK_DIM if claimed else PixelUI.INK_GOLD
	))
	col.add_child(PixelUI.text(
		"Level %d" % int(entry.get("skill_level", 1)),
		PixelUI.SIZE_CAPTION, PixelUI.INK_DIM
	))
	return row


# --- OFFERED: difficulty picker ---------------------------------------------

## Three stacked choices. Each names its exact target, the chest it pays, and the
## outfit chance — everything needed to choose, before choosing.
func _build_picker(entry: Dictionary) -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 5)

	# No "pick a difficulty" prompt here: three labelled buttons are self-evident,
	# the "locks for the day" caveat is stated once in the footnote, and at
	# 960x540 the line costs exactly the vertical space the footnote needs.
	var slot: int = int(entry.get("slot", 0))
	var noun: String = str(entry.get("progress_noun", "actions"))
	for option_v: Variant in (entry.get("options", []) as Array):
		if option_v is Dictionary:
			col.add_child(_build_option(slot, option_v as Dictionary, noun))
	return col


## One difficulty as a QUEST BADGE: a difficulty-coloured 9-slice frame, the
## actual chest sprite the tier pays, the target in the skill's own unit, and
## the reward line. The colour and the chest do the reading before the words do.
func _build_option(slot: int, option: Dictionary, noun: String) -> Control:
	var difficulty: int = clampi(int(option.get("difficulty", 0)), 0, 2)
	var ink: Color = PixelUI.DIFFICULTY_INK[difficulty]

	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 54)
	button.disabled = _pending_slot == slot
	PixelUI.button_frame(button, PixelUI.DIFFICULTY_FRAME[difficulty], 6)
	button.pressed.connect(_on_difficulty_chosen.bind(slot, difficulty))

	# Contents are laid out as children so each line can carry its own colour and
	# the chest sprite can sit alongside; a Button's own text is a single style.
	# MOUSE_FILTER_IGNORE throughout keeps the whole badge one click target.
	var pad: MarginContainer = MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	for side: String in ["top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	button.add_child(pad)

	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 8)
	pad.add_child(row)

	# Chest sprite — 16x16 art at an exact 2x, never a fractional scale.
	var chest: TextureRect = TextureRect.new()
	chest.texture = PixelUI.chest_texture(difficulty)
	chest.custom_minimum_size = Vector2(32, 32)
	chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(chest)

	var col: VBoxContainer = VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override(&"separation", 1)
	row.add_child(col)

	var top: HBoxContainer = _option_header_row()
	col.add_child(top)
	var name_label: Label = PixelUI.text(str(option.get("name", "?")), PixelUI.SIZE_BODY, ink)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	top.add_child(PixelUI.text(
		"%s %s" % [_fmt_amount(int(option.get("target", 0))), noun],
		PixelUI.SIZE_BODY, PixelUI.INK
	))

	col.add_child(PixelUI.text(
		"T%d %s" % [int(option.get("chest_tier", 1)), str(option.get("chest_name", "Chest"))],
		PixelUI.SIZE_TINY, PixelUI.INK_DIM
	))
	col.add_child(PixelUI.text(
		"%s g   %s xp   %s outfit" % [
			_fmt_amount(int(option.get("reward_gold", 0))),
			_fmt_amount(int(option.get("reward_skill_xp", 0))),
			_fmt_percent(float(option.get("outfit_chance", 0.0))),
		],
		PixelUI.SIZE_TINY, PixelUI.INK_DIM
	))
	return button


## Header line inside a difficulty badge: name on the left, target on the right.
## MOUSE_FILTER_IGNORE throughout so the whole badge stays one clickable button
## rather than the labels stealing the press.
func _option_header_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 6)
	return row


# --- ACCEPTED: progress tracker ---------------------------------------------

func _build_tracker(entry: Dictionary) -> Control:
	var progress: int = int(entry.get("progress", 0))
	var required: int = maxi(1, int(entry.get("required", 1)))
	var complete: bool = bool(entry.get("complete", false))
	var slot: int = int(entry.get("slot", 0))
	var difficulty: int = clampi(int(entry.get("difficulty", 0)), 0, 2)
	var accent: Color = PixelUI.DIFFICULTY_INK[difficulty]

	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override(&"separation", 5)

	var head: HBoxContainer = HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 6)
	col.add_child(head)

	# The chest you are working toward, shown at the same 2x as on the badges.
	var chest: TextureRect = TextureRect.new()
	chest.texture = PixelUI.chest_texture(difficulty)
	chest.custom_minimum_size = Vector2(32, 32)
	chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(chest)

	var tier: Label = PixelUI.text("%s  T%d" % [
		str(entry.get("difficulty_name", "?")), int(entry.get("chest_tier", 1))
	], PixelUI.SIZE_BODY, accent)
	tier.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tier.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tier)

	var bar: ProgressBar = ProgressBar.new()
	bar.min_value = 0
	bar.max_value = required
	bar.value = progress
	PixelUI.progress_bar(bar, PixelUI.INK_GREEN if complete else accent, 12)
	col.add_child(bar)
	_bars[slot] = bar
	# Animate from the last value the player actually saw. A gather pushes the
	# whole board, so without this every ore mined would rebuild the card and
	# snap the fill — the one thing that makes a progress bar feel cheap.
	var previous: int = int(_last_progress.get(slot, progress))
	_last_progress[slot] = progress
	# Completion cue on the transition only. Checked here rather than in _apply
	# because this is the one place that knows BOTH the previous value and the
	# new one for this slot.
	if complete and not _completed_slots.has(slot):
		_completed_slots[slot] = true
		if previous < required:
			UISound.task_complete()
	elif not complete:
		_completed_slots.erase(slot)
	if previous != progress:
		bar.value = previous
		var tween: Tween = create_tween()
		tween.tween_property(bar, "value", float(progress), BAR_FILL_TIME) 			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	# "145 / 300 logs cut" — the noun is the server's, so the client never
	# claims the task tracks something narrower than it does.
	col.add_child(PixelUI.text(
		"%s / %s %s" % [
			_fmt_amount(progress), _fmt_amount(required),
			str(entry.get("progress_noun", "actions")),
		],
		PixelUI.SIZE_CAPTION, PixelUI.INK_GREEN if complete else PixelUI.INK_DIM
	))
	return col


func _build_reward_strip(entry: Dictionary) -> Control:
	var chips: HBoxContainer = HBoxContainer.new()
	chips.add_theme_constant_override(&"separation", 5)
	chips.add_child(_chip("%s g" % _fmt_amount(int(entry.get("reward_gold", 0))), PixelUI.INK_COIN))
	chips.add_child(_chip(
		"%s xp" % _fmt_amount(int(entry.get("reward_skill_xp", 0))), PixelUI.INK_XP
	))
	return chips


func _build_action(entry: Dictionary) -> Control:
	var complete: bool = bool(entry.get("complete", false))
	var claimed: bool = bool(entry.get("claimed", false))
	var slot: int = int(entry.get("slot", 0))

	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 38)
	if claimed:
		button.text = "Claimed"
		button.disabled = true
		PixelUI.button_frame(button, "frame_iron", 6)
		PixelUI.button_font(button, PixelUI.SIZE_BODY, PixelUI.INK_DIM)
	elif complete:
		button.text = "Open Chest"
		PixelUI.button_frame(button, "frame_gold", 6)
		PixelUI.button_font(button, PixelUI.SIZE_BODY, PixelUI.INK_GOLD)
		button.pressed.connect(_on_claim.bind(slot))
	else:
		button.text = "In progress"
		button.disabled = true
		PixelUI.button_frame(button, "frame_iron", 6)
		PixelUI.button_font(button, PixelUI.SIZE_BODY, PixelUI.INK_DIM)
	button.disabled = button.disabled or _pending_slot == slot
	return button


# ---------------------------------------------------------------------------
# Completion bonus + footnote
# ---------------------------------------------------------------------------

func _build_bonus_track(response: Dictionary, entries: Array) -> Control:
	var total: int = entries.size()
	var claimed: int = 0
	for e: Variant in entries:
		if bool((e as Dictionary).get("claimed", false)):
			claimed += 1
	var done: bool = bool(response.get("all_claimed", false))

	# Parchment: the completion bonus reads as the contract the three tasks are
	# written against, which is why it gets a different material from the cards.
	var panel: PanelContainer = PanelContainer.new()
	PixelUI.panel(panel, "frame_gold" if done else "frame_parchment", 10)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	panel.add_child(row)

	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override(&"separation", 6)
	row.add_child(col)

	col.add_child(PixelUI.text(
		"Daily bonus earned" if done else "Finish all %d for a bonus" % total,
		PixelUI.SIZE_BODY, PixelUI.INK_GOLD if done else PixelUI.INK_PARCHMENT
	))

	var seg: HBoxContainer = HBoxContainer.new()
	seg.add_theme_constant_override(&"separation", 5)
	col.add_child(seg)
	for i: int in total:
		var pip: PanelContainer = PanelContainer.new()
		pip.custom_minimum_size = Vector2(0, 5)
		pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pip.add_theme_stylebox_override(
			&"panel", PixelUI.tinted_frame("frame_iron", PixelUI.INK_GOLD if i < claimed else Color(0.5, 0.5, 0.55), 0)
		)
		seg.add_child(pip)

	var reward: Label = PixelUI.text(
		"%s g   %s xp into each skill" % [
			_fmt_amount(int(response.get("bonus_gold", 0))),
			_fmt_amount(int(response.get("bonus_skill_xp", 0))),
		],
		PixelUI.SIZE_BODY, PixelUI.INK_GOLD if done else PixelUI.INK_PARCHMENT
	)
	reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(reward)
	return panel


func _build_footnote() -> Control:
	var note: Label = Label.new()
	note.text = (
		"Progress counts actions you perform after accepting — banked materials "
		+ "don't count. Difficulty is locked once chosen, and the three skills "
		+ "reroll at reset."
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	PixelUI.label(note, PixelUI.SIZE_TINY, PixelUI.INK_DIM)
	return note


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

func _on_difficulty_chosen(slot: int, difficulty: int) -> void:
	if _pending_slot >= 0:
		return
	_pending_slot = slot
	# The press itself already clicks — the HUD auto-wires every Button under it.
	# This is the second half of the gesture: the choice is locked for the day,
	# and "sealed" says that in a way a click cannot.
	UISound.task_accepted()
	Client.request_data(
		&"quest.board.choose",
		_on_choose_response,
		{"slot": slot, "difficulty": difficulty},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _on_choose_response(response: Dictionary) -> void:
	_pending_slot = -1
	if not bool(response.get("ok", false)):
		Toaster.toast("Couldn't start that task: %s" % response.get("reason", "unknown"))
		_refresh()
		return
	# The handler returns the whole board, so the card flips from picker to
	# tracker without a second round trip.
	_apply(response)


func _on_claim(slot: int) -> void:
	if _pending_slot >= 0:
		return
	_pending_slot = slot
	Client.request_data(
		&"quest.board.claim",
		_on_claim_response,
		{"slot": slot},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _on_claim_response(response: Dictionary) -> void:
	_pending_slot = -1
	if not bool(response.get("ok", false)):
		Toaster.toast("Claim failed: %s" % response.get("reason", "unknown"))
		return
	# The chest rides back on the claim. Hand it to the one reward presentation in
	# the game rather than building a second one here.
	#
	# STAND DOWN WHILE THE CHEST IS ON SCREEN. The reward window now owns its own
	# CanvasLayer above every menu, so it is no longer trapped behind this board —
	# but a full-screen board under a reward readout is still just noise over the
	# one thing the player wants to look at, and its Close button sits a few pixels
	# from the window's. Hiding is not closing: the board is a display_menu submenu
	# and reopens from the dock with its state intact, and _refresh below keeps it
	# current for when it does.
	var chest: Variant = response.get("chest", {})
	if chest is Dictionary and bool((chest as Dictionary).get("ok", false)):
		hide()
		UniversalChestManager.present(chest as Dictionary)
	for grant_v: Variant in (response.get("skills", []) as Array):
		var grant: Dictionary = grant_v
		if bool(grant.get("leveled_up", false)):
			Announcer.announce("%s level %d!" % [
				str(grant.get("name", "Skill")), int(grant.get("level", 1))
			])
	_refresh()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _message(text: String) -> void:
	for child: Node in _body.get_children():
		child.queue_free()
	var label: Label = PixelUI.text(text, PixelUI.SIZE_BODY, PixelUI.INK_DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_body.add_child(label)


## A small framed value chip. Iron 9-slice, not a rounded pill — see the header.
func _chip(text: String, text_color: Color) -> Control:
	var lbl: Label = PixelUI.text(text, PixelUI.SIZE_TINY, text_color)
	lbl.add_theme_stylebox_override(&"normal", PixelUI.frame("frame_iron", 5))
	return lbl


func _fmt_amount(value: int) -> String:
	var digits: String = str(absi(value))
	var out: String = ""
	for i: int in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" + out) if value < 0 else out


## 0.005 -> "0.5%". Presentation of a number the SERVER computed — the client
## never derives a drop rate, it only formats one it was handed.
func _fmt_percent(value: float) -> String:
	var pct: float = value * 100.0
	if pct >= 1.0:
		return "%.0f%%" % pct
	return "%.1f%%" % pct


func _fmt_duration(seconds: int) -> String:
	if seconds <= 0:
		return "moments"
	@warning_ignore("integer_division")
	var h: int = seconds / 3600
	@warning_ignore("integer_division")
	var m: int = (seconds % 3600) / 60
	if h > 0:
		return "%dh %dm" % [h, m]
	return "%dm" % m
