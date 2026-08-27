extends RefCounted
## Visual language for the Trading Post.
##
## The house theme is soft on purpose — rounded, translucent, floaty — which is
## right for a skills panel and wrong for a market. Money screens have to read as
## instruments: square edges, one hairline per boundary, solid fills you can tell
## apart, and a single gold accent that only ever means "this is about gold".
## Players hand real hours of grinding to this UI; it should look like a ledger,
## not a bubble.
##
## Everything here is a local override applied to widgets the market builds
## itself — no theme edits — so the rest of the game is untouched.
##
## Preloaded, not `class_name`d: it is only ever used by this one menu, and a
## global class would need an import pass before any tool script could load it.

# --- Tokens -----------------------------------------------------------------
## Solid surfaces, darkest (page) to lightest (hover). Alpha stays at 1 on the
## panels: a translucent frame over a lit game world is what made the old panels
## read as murky voids instead of surfaces.
const BG_PANEL: Color = Color(0.063, 0.074, 0.098, 1.0)
const BG_STRIP: Color = Color(0.098, 0.114, 0.148, 1.0)
const BG_ROW: Color = Color(0.075, 0.086, 0.112, 1.0)
const BG_ROW_ALT: Color = Color(0.090, 0.103, 0.132, 1.0)
const BG_HOVER: Color = Color(0.145, 0.170, 0.215, 1.0)
const BG_FIELD: Color = Color(0.035, 0.042, 0.058, 1.0)
const BG_SUNK: Color = Color(0.030, 0.036, 0.050, 1.0)

## One border colour for every frame, one hairline for every divider inside one.
## Two weights is all a bordered interface needs; a third starts to look busy.
const EDGE: Color = Color(0.255, 0.310, 0.400, 1.0)
const EDGE_SOFT: Color = Color(1.0, 1.0, 1.0, 0.055)

const ACCENT: Color = Color(1.00, 0.85, 0.45)
const ACCENT_DIM: Color = Color(0.62, 0.52, 0.28, 1.0)
const ACCENT_FILL: Color = Color(0.180, 0.148, 0.078, 1.0)
const ACCENT_FILL_HI: Color = Color(0.245, 0.200, 0.098, 1.0)
const DANGER: Color = Color(0.90, 0.47, 0.45)
const DANGER_FILL: Color = Color(0.150, 0.070, 0.070, 1.0)

const TEXT: Color = Color(0.88, 0.91, 0.96)
const TEXT_DIM: Color = Color(0.58, 0.63, 0.74)
const TEXT_OFF: Color = Color(0.42, 0.46, 0.55)

## Button roles. DEFAULT is the neutral action, PRIMARY the one that spends or
## commits (exactly one per panel), GHOST a quiet inline control, CHIP a preset.
enum Kind { DEFAULT, PRIMARY, DANGER, GHOST, CHIP, TAB }


# --- Styleboxes -------------------------------------------------------------

## The frame every surface in the Trading Post is drawn in: solid fill, single
## hairline border, square corners.
static func frame(fill: Color = BG_PANEL, border: Color = EDGE) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	return style


## Title bar of a framed panel / header row of a table. Sits inside a frame, so
## it draws only its own bottom edge — no doubled border down the sides.
static func strip() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BG_STRIP
	style.border_color = EDGE
	style.border_width_bottom = 1
	style.set_corner_radius_all(0)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


## Recessed block for a stat readout inside a panel — a step DOWN from the panel
## fill, so data reads as inset rather than as another card stacked on top.
static func sunken() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BG_SUNK
	style.border_color = EDGE_SOFT
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	return style


## A table row. [param index] drives the zebra banding that keeps a long price
## table trackable across its columns; [param selected] gets the gold left edge,
## because the panel next to it has a button that spends real gold and which row
## it belongs to has to be unmistakable.
static func row(index: int, selected: bool, hover: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BG_ROW_ALT if index % 2 == 1 else BG_ROW
	style.border_color = EDGE_SOFT
	style.border_width_bottom = 1
	style.set_corner_radius_all(0)
	if hover:
		style.bg_color = BG_HOVER
	if selected:
		style.bg_color = ACCENT_FILL_HI if hover else ACCENT_FILL
		style.border_width_left = 3
		style.border_color = ACCENT
	return style


# --- Widgets ----------------------------------------------------------------

## Squares off a button and gives it the fill / border / text colour of its role.
## Godot resolves button states from four styleboxes, so all four are set here —
## leaving one to the theme is how a single rounded corner survives a restyle.
static func button(target: Button, kind: Kind = Kind.DEFAULT, height: int = 0) -> Button:
	var fill: Color = BG_ROW_ALT
	var border: Color = EDGE
	var text: Color = TEXT
	var pad_x: int = 12
	var pad_y: int = 6
	match kind:
		Kind.PRIMARY:
			fill = ACCENT_FILL
			border = ACCENT
			text = Color(1.0, 0.94, 0.78)
		Kind.DANGER:
			fill = DANGER_FILL
			border = DANGER
			text = Color(1.0, 0.82, 0.80)
		Kind.GHOST:
			fill = Color(1.0, 1.0, 1.0, 0.03)
			border = EDGE_SOFT
			text = TEXT_DIM
		Kind.CHIP:
			fill = Color(1.0, 1.0, 1.0, 0.04)
			border = EDGE_SOFT
			text = TEXT_DIM
			pad_x = 8
			pad_y = 3
		Kind.TAB:
			fill = Color(0.070, 0.082, 0.108, 1.0)
			border = EDGE
			text = TEXT_DIM
			pad_x = 14
			pad_y = 8

	var normal: StyleBoxFlat = _button_box(fill, border, pad_x, pad_y)
	var hover: StyleBoxFlat = _button_box(_lift(fill, 0.06), _lift(border, 0.25), pad_x, pad_y)
	var pressed: StyleBoxFlat = _button_box(_lift(fill, 0.10), border, pad_x, pad_y)
	var disabled: StyleBoxFlat = _button_box(
		Color(fill.r, fill.g, fill.b, 0.35), Color(border.r, border.g, border.b, 0.25), pad_x, pad_y
	)
	var focus: StyleBoxFlat = _button_box(Color(0, 0, 0, 0), ACCENT_DIM, pad_x, pad_y)

	if kind == Kind.TAB:
		# The active tab is the one piece of chrome that must be readable from
		# across the room: gold text over a lifted fill, with a 2px gold bar on
		# the bottom edge so the tab strip reads as a real segmented control.
		pressed = _button_box(Color(0.130, 0.150, 0.195, 1.0), EDGE, pad_x, pad_y)
		pressed.border_width_bottom = 2
		pressed.border_color = ACCENT
		target.add_theme_color_override(&"font_pressed_color", ACCENT)
		target.add_theme_color_override(&"font_hover_pressed_color", ACCENT)

	target.add_theme_stylebox_override(&"normal", normal)
	target.add_theme_stylebox_override(&"hover", hover)
	target.add_theme_stylebox_override(&"pressed", pressed)
	target.add_theme_stylebox_override(&"hover_pressed", pressed)
	target.add_theme_stylebox_override(&"disabled", disabled)
	target.add_theme_stylebox_override(&"focus", focus)
	target.add_theme_color_override(&"font_color", text)
	target.add_theme_color_override(&"font_hover_color", _lift(text, 0.12))
	target.add_theme_color_override(&"font_focus_color", text)
	target.add_theme_color_override(&"font_disabled_color", Color(text.r, text.g, text.b, 0.35))
	if kind != Kind.TAB:
		target.add_theme_color_override(&"font_pressed_color", text)
	if height > 0:
		target.custom_minimum_size.y = height
	return target


## Text fields, spinners and dropdowns share one look: sunken fill, hairline
## border, gold edge on focus. A SpinBox draws through its inner LineEdit.
static func field(target: Control) -> Control:
	var normal: StyleBoxFlat = _field_box(EDGE)
	var focus: StyleBoxFlat = _field_box(ACCENT_DIM)
	if target is SpinBox:
		var inner: LineEdit = (target as SpinBox).get_line_edit()
		inner.add_theme_stylebox_override(&"normal", normal)
		inner.add_theme_stylebox_override(&"focus", focus)
		inner.add_theme_color_override(&"font_color", TEXT)
		return target
	if target is LineEdit:
		target.add_theme_stylebox_override(&"normal", normal)
		target.add_theme_stylebox_override(&"focus", focus)
		target.add_theme_color_override(&"font_color", TEXT)
		target.add_theme_color_override(&"font_placeholder_color", TEXT_OFF)
		return target
	if target is OptionButton:
		var button_node: Button = target as Button
		for state: StringName in [&"normal", &"hover", &"pressed", &"disabled"]:
			button_node.add_theme_stylebox_override(state, _field_box(EDGE))
		button_node.add_theme_stylebox_override(&"hover", _field_box(_lift(EDGE, 0.25)))
		button_node.add_theme_stylebox_override(&"focus", focus)
		button_node.add_theme_color_override(&"font_color", TEXT)
	return target


## Small upper-case caption over a column or a block — the label a spreadsheet
## puts above a number. Deliberately quiet: it names the data, it is not the data.
static func caption(text: String, size: int = 10) -> Label:
	var label: Label = Label.new()
	label.text = text.to_upper()
	label.add_theme_color_override(&"font_color", TEXT_OFF)
	label.add_theme_font_size_override(&"font_size", size)
	return label


# --- Internals --------------------------------------------------------------

static func _button_box(fill: Color, border: Color, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.content_margin_left = pad_x
	style.content_margin_right = pad_x
	style.content_margin_top = pad_y
	style.content_margin_bottom = pad_y
	return style


static func _field_box(border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BG_FIELD
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


## Brighten toward white, keeping alpha — hover / pressed states derived from one
## base colour instead of a second hand-picked palette that drifts out of step.
static func _lift(base: Color, amount: float) -> Color:
	return Color(
		minf(1.0, base.r + amount),
		minf(1.0, base.g + amount),
		minf(1.0, base.b + amount),
		base.a
	)
