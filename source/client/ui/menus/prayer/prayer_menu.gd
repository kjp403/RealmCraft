extends Control
## The prayer book: every prayer, what it does, and a switch. Lives in the
## bottom dock beside the inventory, NOT as a fullscreen shell — prayers are
## flipped mid-fight, and a full-rect card with a dimming backdrop meant the
## player could neither see the fight nor click it.
##
## The server is authoritative on what is on — every toggle response carries a
## full status snapshot and this redraws from THAT, never from what it hoped
## would happen. A refused toggle therefore self-corrects instead of leaving a
## button stuck in the wrong state.

const GOLD: Color = Color(1.0, 0.95, 0.8)
const MUTED: Color = Color(0.72, 0.76, 0.84)
const CYAN: Color = Color(0.37, 0.83, 0.83)
const LOCKED: Color = Color(0.62, 0.45, 0.45)
const ON_TINT: Color = Color(0.55, 0.85, 0.55)
const QUICK_TINT: Color = Color(0.93, 0.80, 0.35)

## Dock geometry, matching CompactSkillsHost so the panels line up.
const PANEL_SIZE := Vector2(300.0, 340.0)
const RIGHT_MARGIN := 12.0
const BOTTOM_CLEARANCE := 48.0

var _content: VBoxContainer
var _busy: bool = false


func _ready() -> void:
	_place_panel()
	var hud: Control = get_parent() as Control
	if hud != null:
		hud.resized.connect(_place_panel)
	# Build on _ready like every other menu (see inventory_menu). Two traps here,
	# and hitting either leaves an EMPTY full-rect Control over the game that
	# swallows every click with no Close button — indistinguishable from a freeze:
	#
	#  1. hud.display_menu only calls open() for menus opened WITH an argument.
	#     The prayer book is opened without one (dock icon), so open() never runs.
	#  2. Menu scene roots ship visible = true, so display_menu's show() on a
	#     freshly instantiated menu is a NO-OP and visibility_changed does not
	#     fire on first open — a visibility hook alone is not enough.
	#
	# visibility_changed still refreshes the data on REOPEN (hide → show).
	visibility_changed.connect(_on_visibility_changed)
	_refresh()


func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		_refresh()


func open(_arg: Variant = null) -> void:
	_refresh()


func _refresh() -> void:
	# Draw a loading card with a live Close button BEFORE waiting on the server.
	# A full-screen Control with nothing in it blocks the whole game, so the
	# panel must always be escapable even if the request never comes back.
	_build_shell()
	var loading: Label = Label.new()
	loading.text = "Prayers"
	loading.add_theme_font_size_override(&"font_size", 15)
	loading.add_theme_color_override(&"font_color", GOLD)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(loading)
	_content.add_child(_button("Close", hide))

	# Never fire the request into a null peer — the card above is already
	# escapable, which is the part that matters.
	if not is_instance_valid(Client) or not Client.is_connected_to_server:
		return

	var result: Array = await Client.request_data_await(
		&"prayer.state", {}, _instance_name()
	)
	if not visible:
		return
	_build(result[0] if result.size() > 0 and result[0] is Dictionary else {})


func _build(state: Dictionary) -> void:
	# Toggling a prayer redraws the whole list (see the file header: the server
	# snapshot is the only source of truth), which used to also silently reset
	# the scroll to the top — flipping a prayer near the bottom of the book
	# bounced the view away from what you were looking at. Capture the OLD
	# scroll container's offset before _build_shell tears it down, then restore
	# it on the new one once the fresh rows have laid out.
	var prev_scroll: int = 0
	if _content != null and is_instance_valid(_content):
		var old_scroll: ScrollContainer = _content.get_parent() as ScrollContainer
		if old_scroll != null:
			prev_scroll = old_scroll.scroll_vertical

	_build_shell()

	var level: int = int(state.get("level", 1))
	var active: Array = state.get("active", [])

	var title: Label = Label.new()
	title.text = "Prayers"
	title.add_theme_font_size_override(&"font_size", 15)
	title.add_theme_color_override(&"font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)

	var points: Label = Label.new()
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	points.add_theme_font_size_override(&"font_size", 11)
	points.add_theme_color_override(&"font_color", CYAN)
	var drain: float = float(state.get("drain", 0.0))
	points.text = "%d / %d points" % [
		int(round(float(state.get("points", 0.0)))),
		int(round(float(state.get("max", 0.0)))),
	]
	if drain > 0.0:
		# The number players actually plan around: how long the pool lasts at
		# the current burn.
		var seconds_left: float = float(state.get("points", 0.0)) / (drain / 60.0)
		points.text += "   —   draining %s/min (%s left)" % [
			_trim(drain), _duration(seconds_left)
		]
	_content.add_child(points)

	# No nested ScrollContainer: _build_shell already scrolls, and a second one
	# with a fixed 340px minimum forced the rows wider than the dock panel.
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override(&"separation", 4)
	_content.add_child(list)

	# PrayerBook.PRAYERS is grouped by CATEGORY (book order), not by level — a
	# player reading top to bottom saw Defence/Offence/Protection/Gathering
	# blocks with required levels bouncing 1, 25, 60, 1, 15, 35... instead of
	# unlocking in the order they actually earn each one. Sort a copy for
	# display only; PrayerBook's own order stays intact for anything else that
	# reads it by category.
	var by_level: Array[PrayerResource] = PrayerBook.PRAYERS.duplicate()
	by_level.sort_custom(func(a: PrayerResource, b: PrayerResource) -> bool:
		return a.required_level < b.required_level)

	for prayer: PrayerResource in by_level:
		if prayer == null:
			continue
		list.add_child(_prayer_row(prayer, level, active.has(String(prayer.slug))))

	_content.add_child(_button("Close", hide))

	if prev_scroll > 0:
		var new_scroll: ScrollContainer = _content.get_parent() as ScrollContainer
		if new_scroll != null:
			new_scroll.set_deferred(&"scroll_vertical", prev_scroll)


func _prayer_row(prayer: PrayerResource, level: int, is_on: bool) -> Control:
	var unlocked: bool = level >= prayer.required_level
	var row: PanelContainer = PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right"]:
		pad.add_theme_constant_override(StringName("margin_" + side), 6)
	for side: String in ["top", "bottom"]:
		pad.add_theme_constant_override(StringName("margin_" + side), 4)
	row.add_child(pad)

	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override(&"separation", 6)
	line.alignment = BoxContainer.ALIGNMENT_BEGIN
	pad.add_child(line)

	# Prayer icon, if one is authored.
	if prayer.icon != null:
		var icon: TextureRect = TextureRect.new()
		icon.custom_minimum_size = Vector2(20, 20)
		icon.texture = prayer.icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color.WHITE if unlocked else Color(0.5, 0.5, 0.5)
		line.add_child(icon)

	var text: VBoxContainer = VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Long names ("Bulwark of the Mountain") must wrap inside the dock width
	# instead of pushing the toggle off the panel.
	text.custom_minimum_size = Vector2(0, 0)
	line.add_child(text)

	var name_label: Label = Label.new()
	name_label.text = prayer.display_name
	# One line per row. 11px is set by the longest name in the book — "Bulwark
	# of the Mountain" clipped at 12px in the 300px panel.
	name_label.add_theme_font_size_override(&"font_size", 11)
	name_label.clip_text = true
	name_label.add_theme_color_override(
		&"font_color", ON_TINT if is_on else (GOLD if unlocked else LOCKED)
	)
	text.add_child(name_label)

	var detail: Label = Label.new()
	detail.add_theme_color_override(&"font_color", MUTED)
	detail.add_theme_font_size_override(&"font_size", 10)
	detail.clip_text = true
	if unlocked:
		detail.text = "%s   ·   %s" % [prayer.describe_modifiers(), prayer.describe_drain()]
	else:
		detail.text = "Requires Prayer %d" % prayer.required_level
	text.add_child(detail)

	# Star: marks this prayer for the bar's Q button (see prayer_bar.gd). Purely
	# a local preference -- no server round trip, so it can't desync from a
	# refused toggle the way the On/Off button has to guard against. Locked
	# prayers can't be starred; there's nothing to bulk-activate yet.
	if unlocked:
		var star: Button = Button.new()
		star.custom_minimum_size = Vector2(24, 24)
		star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		star.add_theme_font_size_override(&"font_size", 13)
		star.flat = true
		var starred: bool = QuickPrayers.is_quick(prayer.slug)
		star.text = "★" if starred else "☆"
		star.add_theme_color_override(&"font_color", QUICK_TINT if starred else MUTED)
		star.tooltip_text = "Remove from quick prayers" if starred else "Add to quick prayers"
		star.pressed.connect(_on_star.bind(prayer.slug, star))
		line.add_child(star)

	var toggle: Button = Button.new()
	toggle.custom_minimum_size = Vector2(44, 24)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.add_theme_font_size_override(&"font_size", 11)
	toggle.text = "On" if is_on else "Off"
	toggle.disabled = not unlocked
	toggle.pressed.connect(_on_toggle.bind(prayer.slug, not is_on))
	line.add_child(toggle)
	return row


## Flip local quick-prayer membership and repaint just this star -- no need to
## re-fetch server state for a preference the server never sees.
func _on_star(slug: StringName, star: Button) -> void:
	var starred: bool = QuickPrayers.toggle_membership(slug)
	star.text = "★" if starred else "☆"
	star.add_theme_color_override(&"font_color", QUICK_TINT if starred else MUTED)
	star.tooltip_text = "Remove from quick prayers" if starred else "Add to quick prayers"


func _on_toggle(slug: StringName, want_on: bool) -> void:
	if _busy:
		return
	_busy = true
	var result: Array = await Client.request_data_await(
		&"prayer.toggle", {"prayer": String(slug), "on": want_on}, _instance_name()
	)
	_busy = false
	var payload: Dictionary = result[0] if result.size() > 0 and result[0] is Dictionary else {}
	if not bool(payload.get("ok", false)):
		match str(payload.get("reason", "")):
			"no_points":
				Toaster.toast("You have no prayer points left.")
			"prayer_level":
				Toaster.toast("Requires Prayer %d." % int(payload.get("required_level", 0)))
			"dead":
				Toaster.toast("You cannot pray while dead.")
			_:
				Toaster.toast("That prayer did not take.")
	# Redraw from the server's snapshot either way — it rides along on refusals
	# too, so the buttons always end up matching the server.
	if visible:
		_build(payload)


func _trim(value: float) -> String:
	return ("%d" % int(value)) if is_equal_approx(value, roundf(value)) else ("%.1f" % value)


func _duration(seconds: float) -> String:
	if seconds >= 60.0:
		return "%dm %ds" % [int(seconds / 60.0), int(seconds) % 60]
	return "%ds" % int(seconds)


func _instance_name() -> String:
	return String(InstanceClient.current.name) if InstanceClient.current else ""


## Bottom-right, above the dock, matching the compact hosts. No backdrop and no
## full-rect Control: the world behind stays visible AND clickable, so a prayer
## can be flipped without giving up the fight.
func _place_panel() -> void:
	var hud: Control = get_parent() as Control
	if hud == null:
		return
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	position = Vector2(
		hud.size.x - PANEL_SIZE.x - RIGHT_MARGIN,
		hud.size.y - PANEL_SIZE.y - BOTTOM_CLEARANCE
	)


func _build_shell() -> void:
	for child: Node in get_children():
		child.queue_free()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place_panel()

	var card: PanelContainer = PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)

	var pad: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	card.add_child(pad)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_content)


func _button(text: String, callback: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(84, 26)
	b.pressed.connect(callback)
	return b
