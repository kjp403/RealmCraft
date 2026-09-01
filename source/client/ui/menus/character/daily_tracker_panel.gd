extends PanelContainer
## Character > Jobs "Today" tracker — the left column of the Jobs tab.
##
## ONE READ, THREE ANSWERS. Everything on this panel resets on the same 00:00 UTC
## boundary, so it is one question ("what have I still got today?") rather than
## three widgets: the skilling tasks you committed to, the dungeon clears you can
## still be paid for, and how long is left to do either. All three arrive on a
## single `quest.board.info` payload and refresh on a single `daily.progress`
## push, so they cannot drift apart or update at different times.
##
## READ-ONLY BY DESIGN. Accepting, claiming and difficulty choice all live on the
## Daily Skilling Board (the real screen for those decisions, where the payouts
## are spelled out). Duplicating a Claim button here would mean two places that
## can commit the day, and the smaller one would be the one with less context.
## This panel reports; it never commits.
##
## ZERO GAMEPLAY MATH, the same rule the board itself follows: targets, progress,
## nouns, charge counts and the reset timestamp are all server-authored. If a
## number is not on the payload it does not get shown.
##
## DRESSED BY ITS NEIGHBOUR, NOT BY ITS SOURCE. The data here comes from the
## Daily Skilling Board, which is a [PixelUI] screen — pixel font, carved
## 9-slice frames. This panel deliberately does NOT copy that. It shares a tab
## with the skills grid, two feet away, and a panel in a different typeface
## beside one in the theme font reads as two applications rather than one
## screen. So the frame and row tiles come from jobs_panel.gd's own
## make_panel_style() / make_tile_style() — the grid's OWN styles, called rather
## than copied so a retouch of one moves both — and type is left to the project
## theme rather than overridden with the pixel font.
## What carries over from PixelUI is the pixel-art discipline that is not
## typographic: square corners, NEAREST filtering on every texture, and the
## shared recessed item slot behind each icon.

const _JobsPanel = preload("res://source/client/ui/menus/character/jobs_panel.gd")

## Below this many seconds the countdown turns amber and starts showing seconds —
## the last hour is when "later today" becomes "now".
const URGENT_SECONDS: int = 3600

# --- Palette, borrowed from the skills grid sharing this tab -----------------
## The grid's "Skills" heading colour, so "Today" and "Skills" read as a pair.
const INK_HEADING: Color = Color(0.98, 0.92, 0.35)
const INK_BODY: Color = Color(0.92, 0.90, 0.85)
const INK_DIM: Color = Color(0.70, 0.68, 0.63)
## Charge count colour when the day's rewarded clears are gone.
const INK_SPENT: Color = Color(0.92, 0.55, 0.45)
const INK_DONE: Color = Color(0.50, 0.86, 0.45)

## BAR COLOUR IS STATUS, NOT DIFFICULTY. The board tints its bars by difficulty,
## which works there because each card is labelled Easy/Medium/Hard right beside
## it. Stripped of that label the tint is read as state instead — a Hard task at
## 188/300 came out BLOOD RED, which reads as failing, and an Easy one came out
## green, which reads as already done. Here the bar answers "how far am I", and
## difficulty is text.
const BAR_ACTIVE: Color = Color(0.92, 0.82, 0.35)
const BAR_DONE: Color = Color(0.45, 0.85, 0.42)
## A claimed row is dimmed WHOLE (icon, type and bar together) rather than
## recoloured piece by piece — the board dims claimed cards the same way.
const CLAIMED_DIM: Color = Color(0.55, 0.55, 0.58)

# --- Type sizes, matched to the grid ----------------------------------------
const SIZE_HEADING: int = 16
const SIZE_BODY: int = 13
const SIZE_CAPTION: int = 12
const SIZE_TINY: int = 11

@onready var _body: VBoxContainer = %TrackerBody
@onready var _title: Label = %TrackerTitle
@onready var _reset_pill: Label = %TrackerResetPill
@onready var _tasks_heading: Label = %TrackerTasksHeading
@onready var _task_list: VBoxContainer = %TrackerTaskList
@onready var _charges_label: Label = %TrackerChargesLabel
@onready var _spacer: Control = %TrackerSpacer

## Absolute UTC epoch ms of the next reset, straight off the payload. The
## countdown is recomputed from THIS against the wall clock every tick rather
## than decremented, so a machine that slept through six hours shows the right
## number on the next frame instead of resuming six hours behind.
var _reset_at_ms: int = 0
## Last whole second rendered, so _process touches the label ~1x/second instead
## of every frame.
var _last_rendered_seconds: int = -1
## Set once the countdown crosses zero so the "reset happened, refetch" request
## fires once rather than on every frame until the new board lands.
var _reset_refetch_sent: bool = false
## slot -> {"bar": ProgressBar, "value": Label, "title": Label, "icon": TextureRect}
## so a live progress push updates rows IN PLACE. Rebuilding on every gather
## would restart the bars and drop any row the player is mid-read of.
var _rows: Dictionary[int, Dictionary] = {}
## The slot set the current rows were built for. A rebuild is only needed when
## WHICH slots are shown changes (a task accepted, or the board rolled over) —
## not when their numbers move.
var _built_slots: PackedInt32Array = PackedInt32Array()
## Shown instead of the list when nothing is accepted yet.
var _empty_hint: Label
## Centring host for [member _empty_hint]; this is what actually gets shown or
## hidden, so the hint lands in the middle of the empty area rather than at the top.
var _empty_slot: CenterContainer


func _ready() -> void:
	# The grid's own panel style, called rather than copied.
	add_theme_stylebox_override(&"panel", _JobsPanel.make_panel_style())

	_style_label(_title, SIZE_HEADING, INK_HEADING)
	_style_label(_tasks_heading, SIZE_CAPTION, INK_DIM)
	_style_label(_charges_label, SIZE_BODY, INK_HEADING)
	_style_label(_reset_pill, SIZE_CAPTION, INK_DIM)
	# The countdown sits in its own recessed chip so it reads as a readout rather
	# than a second heading competing with "Today".
	_reset_pill.add_theme_stylebox_override(&"normal", _JobsPanel.make_tile_style())

	_empty_hint = _make_label(
		"No tasks accepted yet.
Pick today's three at the Daily Skilling Board.",
		SIZE_CAPTION, INK_DIM
	)
	_empty_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# A CenterContainer hands a child its MINIMUM size, and an autowrapping label's
	# minimum is its longest word — without a floor the hint wraps to one word per
	# line down the middle of the panel.
	_empty_hint.custom_minimum_size = Vector2(340, 0)
	# CENTRED IN THE HOLE, not stacked under the heading. With nothing accepted
	# this panel is mostly empty space, and a hint pinned to the top of it left a
	# void the size of the panel underneath.
	_empty_slot = CenterContainer.new()
	_empty_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_slot.visible = false
	_empty_slot.add_child(_empty_hint)
	_body.add_child(_empty_slot)
	_body.move_child(_empty_slot, _task_list.get_index() + 1)

	# The server re-pushes the whole board whenever a counter moves, a charge is
	# spent, or a key is banked — so an open tracker follows a gather or a
	# dungeon clear live, with no polling and no reopen.
	Client.subscribe(&"daily.progress", _on_board_pushed)
	visibility_changed.connect(_on_visibility_changed)

	_set_charges_text({})
	_render_countdown(true)
	_on_visibility_changed()


func _exit_tree() -> void:
	# Autoloads are torn down before the menu tree on quit, so by the time this
	# runs on shutdown Client is already freed — same guard the Ossuran
	# environment manager uses for the same reason.
	if is_instance_valid(Client):
		Client.unsubscribe(&"daily.progress", _on_board_pushed)


func _on_visibility_changed() -> void:
	var showing: bool = is_visible_in_tree()
	# The countdown is the only thing here that needs a frame loop, and it is
	# unreadable while the tab is hidden — so the loop follows visibility.
	set_process(showing)
	if showing:
		_last_rendered_seconds = -1
		_render_countdown(true)
		_refresh()


func _process(_delta: float) -> void:
	_render_countdown(false)


# ---------------------------------------------------------------------------
# Data
# ---------------------------------------------------------------------------

func _refresh() -> void:
	Client.request_data(
		&"quest.board.info",
		_apply,
		{},
		String(InstanceClient.current.name) if InstanceClient.current != null else ""
	)


## Live push. Only worth applying while the tab is actually on screen; a hidden
## tab re-requests on the way back in anyway.
func _on_board_pushed(payload: Dictionary) -> void:
	if is_visible_in_tree():
		_apply(payload)


func _apply(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		return

	_reset_at_ms = int(response.get("refresh_at_ms", 0))
	_reset_refetch_sent = false
	_last_rendered_seconds = -1
	_render_countdown(true)

	_set_charges_text(response.get("dungeon_charges", {}) as Dictionary)

	# Only ACCEPTED slots are tracked here. An un-accepted slot has no target and
	# no progress yet — it is a decision, and decisions belong on the board.
	var accepted: Array[Dictionary] = []
	for raw: Variant in (response.get("entries", []) as Array):
		if raw is Dictionary and bool((raw as Dictionary).get("accepted", false)):
			accepted.append(raw as Dictionary)

	var slots: PackedInt32Array = PackedInt32Array()
	for entry: Dictionary in accepted:
		slots.append(int(entry.get("slot", -1)))

	if slots != _built_slots:
		_rebuild_rows(accepted, slots)
	else:
		for entry: Dictionary in accepted:
			_apply_row_values(entry)

	_task_list.visible = not accepted.is_empty()
	_empty_slot.visible = accepted.is_empty()
	# The bottom spacer and the empty-state host both want the slack; only one of
	# them may have it or the hint drifts off centre.
	_spacer.visible = not accepted.is_empty()


# ---------------------------------------------------------------------------
# Task rows
# ---------------------------------------------------------------------------

func _rebuild_rows(entries: Array[Dictionary], slots: PackedInt32Array) -> void:
	for child: Node in _task_list.get_children():
		child.queue_free()
	_rows.clear()
	_built_slots = slots
	for entry: Dictionary in entries:
		_task_list.add_child(_build_row(entry))


## One task: skill glyph in a recessed slot, the skill name with its difficulty
## beside it, "45 / 100 logs cut", and a bar. The icon comes off the job's own
## [JobPerks], so a new skill brings its art with it and this file never needs a
## lookup table.
func _build_row(entry: Dictionary) -> Control:
	var row: PanelContainer = PanelContainer.new()
	row.add_theme_stylebox_override(&"panel", _JobsPanel.make_tile_style())

	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 8)
	row.add_child(line)

	var slot_tile: PanelContainer = PanelContainer.new()
	slot_tile.custom_minimum_size = Vector2(34, 34)
	slot_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The shared recessed item slot — pixel art, so it must not be resampled.
	slot_tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slot_tile.add_theme_stylebox_override(&"panel", PixelUI.slot_style())
	var host: CenterContainer = CenterContainer.new()
	slot_tile.add_child(host)
	var icon: TextureRect = PixelIcon.mount(host, _skill_icon(str(entry.get("skill", ""))))
	line.add_child(slot_tile)

	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override(&"separation", 3)
	line.add_child(col)

	var title_row: HBoxContainer = HBoxContainer.new()
	title_row.add_theme_constant_override(&"separation", 6)
	col.add_child(title_row)

	var title: Label = _make_label(
		str(entry.get("skill_name", "?")), SIZE_BODY, INK_BODY
	)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title_row.add_child(title)

	# Difficulty as TEXT, not as bar colour — see [constant BAR_ACTIVE].
	var difficulty: Label = _make_label(
		str(entry.get("difficulty_name", "")), SIZE_TINY, INK_DIM
	)
	difficulty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(difficulty)

	var value: Label = _make_label("", SIZE_TINY, INK_DIM)
	col.add_child(value)

	var bar: ProgressBar = ProgressBar.new()
	# 9-slice bar art, so NEAREST here too.
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	PixelUI.progress_bar(bar, BAR_ACTIVE, 8)
	bar.min_value = 0.0
	bar.max_value = 1.0
	col.add_child(bar)

	_rows[int(entry.get("slot", -1))] = {
		"row": row, "bar": bar, "value": value, "title": title, "icon": icon,
	}
	_apply_row_values(entry)
	return row


## The only place a row's numbers are written, so the build path and the live
## push path cannot format the same task differently.
func _apply_row_values(entry: Dictionary) -> void:
	var parts: Dictionary = _rows.get(int(entry.get("slot", -1)), {})
	if parts.is_empty():
		return
	var row: PanelContainer = parts["row"] as PanelContainer
	var bar: ProgressBar = parts["bar"] as ProgressBar
	var value: Label = parts["value"] as Label
	var title: Label = parts["title"] as Label
	if row == null or bar == null or value == null or title == null:
		return

	var progress: int = int(entry.get("progress", 0))
	var required: int = maxi(1, int(entry.get("required", 1)))
	var noun: String = str(entry.get("progress_noun", "actions"))
	var complete: bool = bool(entry.get("complete", false))
	var claimed: bool = bool(entry.get("claimed", false))

	bar.value = clampf(float(progress) / float(required), 0.0, 1.0)
	title.text = str(entry.get("skill_name", "?"))
	# One modulate for the whole row: a claimed task should recede as a unit
	# rather than have a dim title over a full-brightness bar.
	row.modulate = CLAIMED_DIM if claimed else Color.WHITE

	if claimed:
		value.text = "Claimed"
		_style_label(value, SIZE_TINY, INK_DIM)
		_retint_bar(bar, BAR_DONE)
	elif complete:
		# A finished task is the one actionable thing this panel can surface, so
		# it says what to do rather than just going green.
		value.text = "%d / %d — ready to claim" % [progress, required]
		_style_label(value, SIZE_TINY, INK_DONE)
		_retint_bar(bar, BAR_DONE)
	else:
		value.text = "%d / %d %s" % [progress, required, noun]
		_style_label(value, SIZE_TINY, INK_DIM)
		_retint_bar(bar, BAR_ACTIVE)


## Recolour a bar's fill in place. The fill is a StyleBoxTexture whose tint lives
## in modulate_color, so this never reloads the texture.
func _retint_bar(bar: ProgressBar, tint: Color) -> void:
	var fill: StyleBox = bar.get_theme_stylebox(&"fill")
	if fill is StyleBoxTexture:
		(fill as StyleBoxTexture).modulate_color = tint


func _skill_icon(slug: String) -> Texture2D:
	if slug.is_empty():
		return null
	var perks: JobPerks = JobRegistry.perks_for(StringName(slug))
	return perks.icon if perks != null else null


# ---------------------------------------------------------------------------
# Type
# ---------------------------------------------------------------------------

## Size + colour only, deliberately NO font override: the label then inherits the
## project theme, which is what the skills grid beside it is using.
func _style_label(target: Label, size: int, color: Color) -> void:
	target.add_theme_font_size_override(&"font_size", size)
	target.add_theme_color_override(&"font_color", color)


func _make_label(value: String, size: int, color: Color) -> Label:
	var out: Label = Label.new()
	out.text = value
	_style_label(out, size, color)
	return out


# ---------------------------------------------------------------------------
# Dungeon charges
# ---------------------------------------------------------------------------

## Banked Dungeon Keys are uncapped, so the total can legitimately exceed the
## daily free pool. Printing `total / free_max` alone would read "5 / 3", so the
## free pool is the fraction and keys are called out beside it.
func _set_charges_text(charges: Dictionary) -> void:
	if charges.is_empty():
		_charges_label.text = "Dungeon Charges: —"
		_charges_label.add_theme_color_override(&"font_color", INK_DIM)
		return

	var free_left: int = int(charges.get("free_left", 0))
	var free_max: int = maxi(1, int(charges.get("free_max", 3)))
	var bonus: int = int(charges.get("bonus", 0))
	var total: int = int(charges.get("total", free_left + bonus))

	var text: String = "Dungeon Charges: %d / %d" % [free_left, free_max]
	if bonus > 0:
		text += "  (+%d key%s)" % [bonus, "" if bonus == 1 else "s"]
	_charges_label.text = text
	_charges_label.add_theme_color_override(
		&"font_color", INK_HEADING if total > 0 else INK_SPENT
	)


# ---------------------------------------------------------------------------
# Countdown
# ---------------------------------------------------------------------------

## Recomputed from the server's absolute reset timestamp against the wall clock,
## never decremented from the last value: that is what keeps it right after the
## machine sleeps or the process is throttled, and what lets a mid-session
## re-push correct it. Both sides are UTC epoch — `refresh_at_ms` is
## `(utc_day + 1) * DAY_MS` and [method Time.get_unix_time_from_system] returns
## epoch seconds — so the local timezone never enters the arithmetic.
func _render_countdown(force: bool) -> void:
	if _reset_at_ms <= 0:
		if force:
			_reset_pill.text = "  Resets 00:00 UTC  "
		return

	var now_ms: int = int(Time.get_unix_time_from_system() * 1000.0)
	var seconds_left: int = maxi(0, int((_reset_at_ms - now_ms) / 1000.0))
	if not force and seconds_left == _last_rendered_seconds:
		return
	_last_rendered_seconds = seconds_left

	_reset_pill.text = "  Resets in %s  " % _format_countdown(seconds_left)
	_reset_pill.add_theme_color_override(
		&"font_color",
		Color(1.0, 0.72, 0.42) if seconds_left <= URGENT_SECONDS else INK_DIM
	)

	# The board rolled over while the panel was open: ask the server for the new
	# one rather than leaving yesterday's tasks on screen reading "moments".
	if seconds_left <= 0 and not _reset_refetch_sent:
		_reset_refetch_sent = true
		_refresh()


## Coarse far out, precise when it matters: "23h 14m" all day, "48m 09s" inside
## the last hour. A ticking seconds field 20 hours ahead is noise.
func _format_countdown(seconds: int) -> String:
	if seconds <= 0:
		return "moments"
	@warning_ignore("integer_division")
	var hours: int = seconds / 3600
	@warning_ignore("integer_division")
	var minutes: int = (seconds % 3600) / 60
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	return "%dm %02ds" % [minutes, seconds % 60]
