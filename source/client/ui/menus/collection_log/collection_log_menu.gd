extends MenuShell
## The Boss Collection Log. Opened from the bottom-right nav panel, or with
## ClientState.open_menu_requested(&"collection_log", null).
##
## LEFT: one row per boss with a progress bar — the ladder, so a player can see
## at a glance which log is closest to green.
## RIGHT: the selected boss's items as a slot grid. Obtained entries show the
## real icon; missing ones show a dimmed silhouette, because a collection log
## that hides what you have not found yet is not a checklist, it is a surprise.
##
## PURE VIEW. It asks the server for a payload and draws it. It never writes:
## nothing on the client may credit a log (see collection_log.state.gd), so
## there is no button here that could.
##
## Item names and icons are resolved CLIENT-SIDE from the slug, through
## ContentRegistryHub — the same lookup loot_feed and the chest window use. The
## server sends slugs rather than names so the payload stays small and the client
## keeps using the localised/authored item data it already has.

## Seven 64px cells fit the right pane at the narrowest supported window. Was
## six, raised when tier materials took the biggest log to 21 items: seven
## columns lands that at three full rows, where six would have left a fourth row
## holding three cells and made the common case scroll for almost nothing.
const GRID_COLUMNS: int = 7
const CELL_SIZE: Vector2 = Vector2(64, 64)
## Headroom for the title itself. The VIP emitter stack is mounted ON the title
## label and fitted to its rect, so this is the room those particles get to
## travel in — a label sized to its glyphs alone gives the emitters a few pixels
## and the effect reads as a smudge on the text.
##
## The plaque takes its height from THIS plus the margins, rather than carrying a
## fixed height of its own. A hardcoded banner height either starves the emitters
## or, once it is tall enough for them, stops being a number anyone can reason
## about — and it is the spacer above that controls where the plaque sits, not
## how tall it is.
const PLAQUE_TITLE_HEIGHT: float = 44.0
## Breathing room between the plaque border and its text.
const PLAQUE_MARGIN: int = 12

const COLOR_MUTED: Color = Color(0.75, 0.78, 0.85)
## Locked cells keep the icon but drop to near-silhouette. Not fully black: the
## shape is the hint that makes a collection log worth opening twice.
const LOCKED_MODULATE: Color = Color(0.12, 0.13, 0.17, 0.92)

var _logs: Array = []
var _selected: String = ""

var _list_host: VBoxContainer
var _detail_host: VBoxContainer
## Rebuilt per refresh; kept so selection can restyle rows without a full redraw.
var _rows: Dictionary = {}


func _ready() -> void:
	build_shell("Collection Log", null, true)
	_build_layout()
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())


# --- layout ------------------------------------------------------------------

func _build_layout() -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override(&"separation", 14)
	content.add_child(hbox)

	var left_scroll: ScrollContainer = ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_stretch_ratio = 1.0
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(left_scroll)

	_list_host = VBoxContainer.new()
	_list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_host.add_theme_constant_override(&"separation", 8)
	left_scroll.add_child(_list_host)

	var right_panel: PanelContainer = PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.5
	PixelUI.panel(right_panel, "frame_stone", 12)
	hbox.add_child(right_panel)

	# No ScrollContainer around THIS. A ScrollContainer sizes itself to its
	# CONTENT, so a SIZE_EXPAND_FILL child inside one resolves to zero height and
	# cannot push anything to the bottom — the reward plaque would float directly
	# under the grid again. The scrolling in this panel is one level deeper, around
	# the item grid alone (see _build_detail), where the container it sits in has a
	# height to constrain it.
	var pad: MarginContainer = MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override(StringName("margin_" + side), 10)
	for side: String in ["top", "bottom"]:
		pad.add_theme_constant_override(StringName("margin_" + side), 8)
	right_panel.add_child(pad)

	# INVARIANT: exactly one CHILD of this box expands vertically — the grid's
	# ScrollContainer in _build_detail. Everything above it hugs its content and
	# the plaque below it is SHRINK_BEGIN, which is what pins the plaque to the
	# bottom margin. A second expanding child anywhere in here splits the leftover
	# space with the scroll and the plaque drifts back up into the middle.
	#
	# That one node is doing two jobs: it absorbs the slack under a short grid
	# (what a bare spacer used to do) AND it is what stops a 21-item log running
	# off the bottom of the panel.
	#
	# The chain ABOVE this node (hbox -> right_panel -> pad -> here) expands on
	# purpose and must keep doing so: those are ancestors passing the panel's
	# height down, not siblings competing for it.
	_detail_host = VBoxContainer.new()
	_detail_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_host.add_theme_constant_override(&"separation", 8)
	pad.add_child(_detail_host)


# --- data --------------------------------------------------------------------

func _refresh() -> void:
	if _list_host == null:
		return
	Client.request_data(
		&"collection_log.state", _apply_state, {},
		String(InstanceClient.current.name) if InstanceClient.current else ""
	)


func _apply_state(response: Dictionary) -> void:
	if not bool(response.get("ok", false)):
		Toaster.toast("Could not read your collection log.")
		return
	_logs = response.get("logs", [])
	# Closest to green first, so the log a player is actually chasing is the one
	# under the cursor. Completed logs sink to the bottom — they are trophies now,
	# not to-do items.
	_logs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_done: bool = bool(a.get("completed", false))
		var b_done: bool = bool(b.get("completed", false))
		if a_done != b_done:
			return b_done
		return _ratio(a) > _ratio(b)
	)
	if _selected.is_empty() or _find(_selected).is_empty():
		_selected = str(_logs[0].get("boss_id", "")) if not _logs.is_empty() else ""
	_build_list()
	_build_detail()


func _ratio(row: Dictionary) -> float:
	var total: int = int(row.get("total", 0))
	return 0.0 if total <= 0 else float(int(row.get("unlocked", 0))) / float(total)


func _find(boss_id: String) -> Dictionary:
	for row: Variant in _logs:
		if row is Dictionary and str((row as Dictionary).get("boss_id", "")) == boss_id:
			return row
	return {}


# --- boss list ---------------------------------------------------------------

func _build_list() -> void:
	for child: Node in _list_host.get_children():
		child.queue_free()
	_rows.clear()
	for row: Variant in _logs:
		if row is Dictionary:
			_add_list_row(row)


func _add_list_row(row: Dictionary) -> void:
	var boss_id: String = str(row.get("boss_id", ""))
	var completed: bool = bool(row.get("completed", false))

	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(0, 76)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The FRAME carries completion, not selection — a green log gets the gold
	# frame, the same visual promotion the rarity table gives an ultra drop, so
	# "finished" reads without any text.
	PixelUI.button_frame(button, "frame_gold" if completed else "frame_iron", 8)
	button.pressed.connect(func() -> void:
		_selected = boss_id
		_build_list()
		_build_detail())
	_list_host.add_child(button)
	_rows[boss_id] = button

	# SELECTION is a separate channel from completion, and it has to be: the two
	# coincide often enough (a finished log is the one you just clicked) that
	# folding them into the frame makes selection invisible on every row that is
	# not complete. An accent bar down the left edge reads at a glance and does
	# not fight the gold.
	if boss_id == _selected:
		var accent: ColorRect = ColorRect.new()
		accent.color = PixelUI.INK_GREEN if completed else PixelUI.INK_GOLD
		accent.custom_minimum_size = Vector2(4, 0)
		accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
		accent.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
		accent.offset_left = 5
		accent.offset_right = 9
		accent.offset_top = 9
		accent.offset_bottom = -9
		button.add_child(accent)

	# The label stack is a non-interactive child so the whole card stays one
	# click target — a row of separate Labels would eat the press.
	var pad: MarginContainer = MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override(StringName("margin_" + side), 12)
	for side: String in ["top", "bottom"]:
		pad.add_theme_constant_override(StringName("margin_" + side), 8)
	button.add_child(pad)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override(&"separation", 3)
	pad.add_child(vbox)

	var top: HBoxContainer = HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(top)

	var name_label: Label = PixelUI.text(
		str(row.get("boss_name", "?")), PixelUI.SIZE_BODY,
		PixelUI.INK_GOLD if completed else PixelUI.INK
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)

	var count: Label = PixelUI.text(
		"%d / %d" % [int(row.get("unlocked", 0)), int(row.get("total", 0))],
		PixelUI.SIZE_CAPTION, PixelUI.INK_GREEN if completed else COLOR_MUTED
	)
	top.add_child(count)

	var bar: ProgressBar = ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.max_value = maxf(1.0, float(int(row.get("total", 1))))
	bar.value = float(int(row.get("unlocked", 0)))
	PixelUI.progress_bar(bar, PixelUI.INK_GREEN if completed else PixelUI.INK_GOLD, 10)
	vbox.add_child(bar)

	# Kills and the dry streak are the reason the log tracks kills at all, so
	# they belong on the ladder row rather than buried in the detail pane.
	var kills: int = int(row.get("kills", 0))
	var sub: String = "%d kill%s" % [kills, "" if kills == 1 else "s"]
	if int(row.get("dry", 0)) > 0:
		sub += "  ·  %d dry" % int(row.get("dry", 0))
	if completed:
		sub += "  ·  %s" % str(row.get("title", ""))
	vbox.add_child(PixelUI.text(sub, PixelUI.SIZE_TINY, COLOR_MUTED))


# --- item grid ---------------------------------------------------------------

func _build_detail() -> void:
	for child: Node in _detail_host.get_children():
		child.queue_free()
	var row: Dictionary = _find(_selected)
	if row.is_empty():
		_detail_host.add_child(PixelUI.text(
			"No collection logs yet.", PixelUI.SIZE_BODY, COLOR_MUTED))
		return

	# TOP: who, how you are doing, and what you have — the three things a player
	# opened this panel to read, in that order and with nothing between them.
	var header: Label = PixelUI.text(
		str(row.get("boss_name", "?")), PixelUI.SIZE_HEADING, PixelUI.INK_GOLD)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_host.add_child(header)
	_detail_host.add_child(_make_stats(row))

	# THE GRID IS ALSO THE SPACER.
	#
	# This used to be a bare grid followed by an empty SIZE_EXPAND_FILL Control,
	# which pinned the plaque to the bottom on the assumption — written into the
	# old comment — that the largest log was ten items, two rows, always short
	# enough to fit. Adding tier materials took Ankhemet to 21 and the
	# Necromancer to 19, so that assumption is gone and a fixed grid now runs off
	# the bottom of the panel.
	#
	# One node solves both: a ScrollContainer holding the grid, expanding to take
	# every pixel the header and plaque do not. Short logs leave it part empty,
	# exactly as the spacer did; long ones scroll inside it. The plaque still
	# sits on the bottom margin either way, and there is still exactly ONE
	# expanding child in here — see the invariant on _detail_host.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.add_child(_make_grid(row))
	_detail_host.add_child(scroll)

	# BOTTOM: the reward, anchored to the floor of the panel.
	_detail_host.add_child(_make_title_plaque(row))


## The stat line as a centred row of value/label pairs rather than one long
## sentence: the numbers are what the player scans for, so they carry the bright
## ink and the words behind them stay muted.
func _make_stats(row: Dictionary) -> Control:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override(&"separation", 5)

	var kills: int = int(row.get("kills", 0))
	var pairs: Array = [
		["%d / %d" % [int(row.get("unlocked", 0)), int(row.get("total", 0))],
			"collected", PixelUI.INK_GOLD],
		["%d" % kills, "kill" if kills == 1 else "kills", PixelUI.INK],
	]
	# Dry streak stays visible AFTER the log is green. It used to be hidden there
	# on the grounds that a full log has nothing left to drop, so the number only
	# climbs — but people keep farming these bosses for the weapons and the
	# materials long after the log is done, and hiding it took the counter away
	# from exactly the players with the longest ones.
	if int(row.get("dry", 0)) > 0:
		pairs.append(["%d" % int(row.get("dry", 0)), "dry", COLOR_MUTED])

	for i: int in pairs.size():
		if i > 0:
			bar.add_child(PixelUI.text("\u00b7", PixelUI.SIZE_CAPTION, COLOR_MUTED))
		bar.add_child(PixelUI.text(str(pairs[i][0]), PixelUI.SIZE_CAPTION, pairs[i][2]))
		bar.add_child(PixelUI.text(str(pairs[i][1]), PixelUI.SIZE_CAPTION, COLOR_MUTED))
	return bar


## The item grid, shrink-centred so a partial last row sits under the middle of
## the panel rather than hugging the left edge.
func _make_grid(row: Dictionary) -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 6)
	for entry: Variant in row.get("items", []):
		if entry is Dictionary:
			grid.add_child(_make_cell(entry))
	return grid


## The reward plaque: a banner pinned to the bottom of the panel.
##
## Rendered through TitleVfx.apply_to_label — the SAME entry point the in-world
## nameplate uses — so the metal ramp, the specular sweep, Emberfrost's split and
## the bespoke emitter stack are exactly what will appear over the player's head.
## A hand-tinted reimplementation showed a plainer title than the one actually
## earned, which made the preview a lie in the direction that matters most.
##
## The plaque HUGS ITS CONTENT: size_flags_vertical is SHRINK_BEGIN, so it claims
## only the margins plus its two labels and the spacer above owns everything
## else. Give it SIZE_EXPAND_FILL and it splits the leftover space with the
## spacer instead of being pushed by it, which is what left the caption floating
## in the middle of an oversized banner with the title sunk to the floor.
##
## clip_contents stays OFF the whole way down — plaque, margin, stack, stage and
## label.
## The shader displaces vertices and the emitters are Node2Ds mounted on the
## label, several of which travel upward; any ancestor that clips shears the
## glyphs and kills the particles outright. It is already the Control default on
## all four, but it is pinned explicitly because a single stray clip anywhere on
## this chain silently guts the effect this whole panel exists to show off.
func _make_title_plaque(row: Dictionary) -> Control:
	var completed: bool = bool(row.get("completed", false))
	var title: String = str(row.get("title", ""))
	var edge: Color = PixelUI.INK_GOLD if completed else Color(0.34, 0.36, 0.42)

	var plaque: PanelContainer = PanelContainer.new()
	plaque.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plaque.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	plaque.clip_contents = false
	plaque.add_theme_stylebox_override(&"panel", _plaque_style(edge))

	# PANELCONTAINER RESIZES EVERY CHILD to its content rect — it is a Container,
	# so anchors and offsets on a direct child are simply overwritten, and a
	# decorative overlay added alongside the text gets stretched across the whole
	# banner. That turned a 1px bevel into a solid olive slab and, before it, a
	# subtle gradient into what looked like a rendering bug. So the plaque gets
	# exactly ONE child and the struck-metal top edge now comes from the stylebox
	# border instead of a node — which also means the child is a real container
	# and its minimum size reaches the plaque, letting the banner hug its content.
	var margin: MarginContainer = MarginContainer.new()
	margin.clip_contents = false
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override(
			StringName("margin_" + side), PLAQUE_MARGIN)
	plaque.add_child(margin)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.clip_contents = false
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override(&"separation", 2)
	margin.add_child(stack)

	# Left-aligned: this is a field label for the thing under it, not a heading
	# for the plaque. Centring it made two centred lines that competed.
	# The completion DATE rides the caption rather than the stat line above: the
	# stat line is live numbers a player watches move, and a date that will never
	# change again does not belong among them. It belongs on the trophy.
	var caption_text: String = "COMPLETION REWARD"
	if completed:
		var stamp: int = int(row.get("completed_at", 0))
		# A character who green-logged before the stamp shipped has no honest
		# date. Say "EARNED TITLE" for them rather than print a wrong one.
		caption_text = "EARNED TITLE" if stamp <= 0 \
			else "EARNED %s" % _local_date(stamp)
	var caption: Label = PixelUI.text(
		caption_text,
		PixelUI.SIZE_TINY, PixelUI.INK_GREEN if completed else COLOR_MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	caption.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stack.add_child(caption)

	# THE TITLE MUST NOT BE THE NODE THAT EXPANDS.
	#
	# TitleVfx.apply_to_label calls label.reset_size() \u2014 it has to, because a Label
	# whose text was just set still reports its PREVIOUS size, and both the
	# shader's rect_size uniform and the emitter fit_to() read label.size. That is
	# right for a nameplate, which is a free-floating Label. Inside a container it
	# is destructive: reset_size() shrinks the label to its own minimum and the
	# container does not re-sort afterwards, so an EXPAND_FILL title collapses to
	# its text width and strands itself at the top-left of its slot \u2014 glyphs
	# against the left margin, and the whole emitter stack piled up there with
	# them, because the emitters are centred on label.size * 0.5.
	#
	# So the CenterContainer expands and the label shrinks. reset_size() then
	# lands on the size the label already has and is harmless, the emitters wrap
	# the glyphs exactly as they do on a nameplate, and centring belongs to the
	# container rather than to an alignment flag a later reset_size can undo.
	var stage: CenterContainer = CenterContainer.new()
	stage.clip_contents = false
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(stage)

	var label: Label = Label.new()
	label.text = "\u00ab %s \u00bb" % title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", PixelUI.SIZE_BODY)
	label.clip_contents = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Survives reset_size(), which sets the label to its COMBINED minimum \u2014 so
	# this is the one way to guarantee the emitters keep their headroom.
	label.custom_minimum_size = Vector2(0, PLAQUE_TITLE_HEIGHT)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stage.add_child(label)

	# Applied only once the containers have SORTED, not merely once the label is
	# in the tree. TitleVfx feeds the shader a rect_size uniform and fits the
	# emitter stack to label.size, and container sizing is itself resolved in a
	# deferred pass — so a plain call_deferred here can land while the label is
	# still zero-sized, which collapses the gradient to one flat colour and piles
	# every particle on a single point.
	var apply: Callable = func() -> void:
		await get_tree().process_frame
		if is_instance_valid(label):
			# preview: a menu mount, so the emitters are not culled against the
			# world camera - see TitleVfx.apply_to_label.
			TitleVfx.apply_to_label(label, title, true)
	apply.call_deferred()
	return plaque


## "5 SEP 2026" from unix seconds, in the PLAYER's timezone.
##
## The server sends the raw stamp precisely so this conversion happens here: it
## knows when the log was filled, it does not know where the player is, and a
## UTC date shows the wrong day to anyone far enough east or west of it on the
## evenings this game is actually played.
func _local_date(unix_s: int) -> String:
	const MONTHS: PackedStringArray = [
		"JAN", "FEB", "MAR", "APR", "MAY", "JUN",
		"JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
	]
	var bias_s: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d: Dictionary = Time.get_datetime_dict_from_unix_time(unix_s + bias_s)
	var month: int = clampi(int(d.get("month", 1)), 1, 12)
	return "%d %s %d" % [int(d.get("day", 1)), MONTHS[month - 1], int(d.get("year", 0))]


func _plaque_style(edge: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.055, 0.062, 0.085, 0.96)
	box.set_border_width_all(1)
	# A heavier top edge is what reads as struck metal at this scale. It used to
	# be a 1px ColorRect anchored inside the plaque; as a border width it needs no
	# extra node, so it cannot be caught by PanelContainer's resize-every-child
	# rule and cannot band under the NEAREST filtering this menu runs under.
	box.border_width_top = 2
	box.border_color = Color(edge, 0.85)
	# Square corners: everything else in this menu is 9-sliced pixel chrome, and
	# a rounded rectangle beside it reads as a different application.
	box.set_corner_radius_all(0)
	# Zero: the MarginContainer inside owns the padding now, so that the plaque's
	# text inset is one number in one place instead of two that quietly add up.
	box.set_content_margin_all(0.0)
	return box


func _make_cell(entry: Dictionary) -> Control:
	var slug: StringName = StringName(str(entry.get("slug", "")))
	var owned: bool = bool(entry.get("owned", false))
	var item: Item = ContentRegistryHub.load_by_slug(&"items", slug) as Item

	var cell: PanelContainer = PanelContainer.new()
	cell.custom_minimum_size = CELL_SIZE
	cell.add_theme_stylebox_override(&"panel", PixelUI.slot_style())

	# Inset so the slot's carved frame stays visible around the art — an icon
	# stretched to the full cell covers the border and the grid reads as a
	# contact sheet rather than as a row of slots.
	var inset: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override(StringName("margin_" + side), 8)
	cell.add_child(inset)

	var icon: TextureRect = TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # pixel art: no smoothing
	if item != null:
		icon.texture = item.item_icon
	if not owned:
		icon.modulate = LOCKED_MODULATE
	inset.add_child(icon)

	# Quantity. Shown only past the first copy: an "x1" on every owned cell is
	# noise, and the number only starts meaning something once it is telling you
	# the boss has paid this out more than once.
	var count: int = int(entry.get("count", 0))
	if count > 1:
		var badge: Label = PixelUI.text("x%d" % count, PixelUI.SIZE_TINY, PixelUI.INK_GOLD)
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -28.0
		badge.offset_top = -15.0
		badge.offset_right = -3.0
		badge.offset_bottom = -2.0
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		badge.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override(&"outline_size", 4)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(badge)

	# An item the registry cannot resolve still gets a cell. Dropping it would
	# make a 9/10 log look like 9/9 and the missing title inexplicable.
	var display_name: String = str(item.item_name) if item != null \
		else "Unknown (%s)" % slug
	var qty: String = "" if count <= 1 else "  (x%d)" % count
	cell.tooltip_text = (display_name + qty) if owned \
		else "%s — not yet collected" % display_name
	return cell
