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

## Grid columns in the item panel. Six 64px cells fit the right-hand pane at the
## narrowest supported window without the grid scrolling sideways.
const GRID_COLUMNS: int = 6
const CELL_SIZE: Vector2 = Vector2(64, 64)
## Flat banner, not a box. One line of title plus its caption needs this and
## no more; the old preview was tall enough to leave a cavern under a short
## grid.
const PLAQUE_HEIGHT: float = 46.0

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

	# NO ScrollContainer here, deliberately. A ScrollContainer sizes itself to its
	# CONTENT, so a SIZE_EXPAND_FILL spacer inside one resolves to zero height and
	# cannot push anything to the bottom — the reward plaque would float directly
	# under the grid again. The panel is a fixed height and the largest log is ten
	# items (two rows), so there is nothing to scroll.
	var pad: MarginContainer = MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override(StringName("margin_" + side), 10)
	for side: String in ["top", "bottom"]:
		pad.add_theme_constant_override(StringName("margin_" + side), 8)
	right_panel.add_child(pad)

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
	if completed:
		sub += "  ·  %s" % str(row.get("title", ""))
	elif int(row.get("dry", 0)) > 0:
		sub += "  ·  %d dry" % int(row.get("dry", 0))
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
	_detail_host.add_child(_make_grid(row))

	# The dynamic spacer, and the whole layout fix: it eats every pixel the grid
	# does not, so a six-item log and a ten-item log both put the plaque on the
	# bottom margin instead of leaving a cavern under a short grid.
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_host.add_child(spacer)

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
	# Dry streak only while it means something — once green every kill is dry by
	# definition and the number is noise.
	if not bool(row.get("completed", false)) and int(row.get("dry", 0)) > 0:
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


## The reward plaque: a flat banner pinned to the bottom of the panel.
##
## Rendered through TitleVfx.apply_to_label — the SAME entry point the in-world
## nameplate uses — so the metal ramp, the specular sweep, Emberfrost's split and
## the bespoke emitter stack are exactly what will appear over the player's head.
## A hand-tinted reimplementation showed a plainer title than the one actually
## earned, which made the preview a lie in the direction that matters most.
##
## clip_contents stays OFF on purpose. The emitters are Node2Ds mounted on the
## label and several of them travel upward; clipping to the plaque would shear
## them off mid-flight. They spill into the spacer above, which is empty by
## construction, so there is nothing up there for them to collide with.
func _make_title_plaque(row: Dictionary) -> Control:
	var completed: bool = bool(row.get("completed", false))
	var title: String = str(row.get("title", ""))
	var edge: Color = PixelUI.INK_GOLD if completed else Color(0.34, 0.36, 0.42)

	var plaque: PanelContainer = PanelContainer.new()
	plaque.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plaque.custom_minimum_size = Vector2(0, PLAQUE_HEIGHT)
	plaque.add_theme_stylebox_override(&"panel", _plaque_style(edge))

	# PANELCONTAINER RESIZES EVERY CHILD to its content rect — it is a Container,
	# so anchors and offsets on a direct child are simply overwritten. A decorative
	# overlay added straight to the plaque gets stretched across the whole banner,
	# which is what turned a 1px bevel into a solid olive slab and, before it, a
	# subtle gradient into what looked like a rendering bug. So the plaque gets
	# exactly ONE child, and the decoration hangs off a plain Control inside it.
	var inner: Control = Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plaque.add_child(inner)

	# A 1px lip along the inside of the top edge, not a gradient wash. A bevel is
	# what reads as struck metal at this scale, it cannot band under the NEAREST
	# filtering build_shell applies to this whole menu, and it needs no filtering
	# exception to stay crisp.
	var lip: ColorRect = ColorRect.new()
	lip.color = Color(edge, 0.22)
	lip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	lip.offset_top = 0.0
	lip.offset_bottom = 1.0
	inner.add_child(lip)

	var stack: VBoxContainer = VBoxContainer.new()
	stack.add_theme_constant_override(&"separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.add_child(stack)

	var caption: Label = PixelUI.text(
		"EARNED TITLE" if completed else "COMPLETION REWARD",
		PixelUI.SIZE_TINY, PixelUI.INK_GREEN if completed else COLOR_MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(caption)

	var stage: Control = Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(stage)

	var label: Label = Label.new()
	label.text = "\u00ab %s \u00bb" % title
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", PixelUI.SIZE_BODY)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(label)

	# Applied after the label is in the tree AND laid out: TitleVfx feeds the
	# shader a rect_size uniform, and a zero rect there collapses the whole
	# gradient to one flat colour.
	var apply: Callable = func() -> void:
		if is_instance_valid(label):
			TitleVfx.apply_to_label(label, title)
	apply.call_deferred()
	return plaque


func _plaque_style(edge: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Color(0.055, 0.062, 0.085, 0.96)
	box.set_border_width_all(1)
	box.border_color = Color(edge, 0.85)
	# Square corners: everything else in this menu is 9-sliced pixel chrome, and
	# a rounded rectangle beside it reads as a different application.
	box.set_corner_radius_all(0)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 5.0
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
