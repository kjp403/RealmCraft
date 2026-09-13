extends RefCounted
## One look for the whole Vault, so its four shelves read as one store.
##
## OPAQUE ON PURPOSE. The Vault used to be a fullscreen MenuShell over a half-alpha
## dim, and the Guild House's leaderboard text read straight through the item
## descriptions and the Buy price. A shop is the one screen where nothing may
## compete with the thing being sold.
##
## Flat, square tiles from [method PixelUI.flat_tile]: no corner radius, so every
## edge rasterises like the pixel art around it.

const BG: Color = Color(0.051, 0.058, 0.078, 1.0)
const PANEL: Color = Color(0.078, 0.086, 0.114, 1.0)
const ROW: Color = Color(0.106, 0.116, 0.151, 1.0)
const ROW_HOVER: Color = Color(0.145, 0.158, 0.204, 1.0)
const ROW_SELECTED: Color = Color(0.231, 0.184, 0.090, 1.0)
const LINE: Color = Color(0.231, 0.243, 0.302, 1.0)
const GOLD: Color = Color(1.0, 0.80, 0.34, 1.0)
const GOLD_FILL: Color = Color(0.851, 0.635, 0.216, 1.0)
const GOLD_DARK: Color = Color(0.620, 0.455, 0.141, 1.0)
const INK: Color = Color(0.93, 0.90, 0.82, 1.0)
const INK_DIM: Color = Color(0.62, 0.62, 0.68, 1.0)
const INK_ON_GOLD: Color = Color(0.09, 0.07, 0.03, 1.0)
const GOOD: Color = Color(0.55, 0.85, 0.45, 1.0)
const CLEAR: Color = Color(0, 0, 0, 0)

const COIN_ICON: Texture2D = preload("res://assets/sprites/ui/ark_coin.png")

const SIZE_NAME: int = 18
const SIZE_BODY: int = 13
const SIZE_BUTTON: int = 16


static func panel_box(pad: int = 8) -> StyleBoxFlat:
	return PixelUI.flat_tile(PANEL, LINE, pad, pad)


## A shelf row: quiet at rest, lifted on hover, gold-edged when selected.
static func style_row(button: Button) -> void:
	var selected: StyleBoxFlat = PixelUI.flat_tile(ROW_SELECTED, GOLD, 8, 4)
	button.add_theme_stylebox_override(&"normal", PixelUI.flat_tile(ROW, CLEAR, 8, 4))
	button.add_theme_stylebox_override(&"hover", PixelUI.flat_tile(ROW_HOVER, CLEAR, 8, 4))
	button.add_theme_stylebox_override(&"pressed", selected)
	button.add_theme_stylebox_override(&"hover_pressed", selected)
	button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	button.focus_mode = Control.FOCUS_NONE


## A category tab. The selected one is the same gold-edged tile as a selected
## row, so "where am I" reads the same way at every level of the store.
static func style_tab(button: Button) -> void:
	var selected: StyleBoxFlat = PixelUI.flat_tile(ROW_SELECTED, GOLD, 10, 4)
	button.add_theme_stylebox_override(&"normal", PixelUI.flat_tile(PANEL, LINE, 10, 4))
	button.add_theme_stylebox_override(&"hover", PixelUI.flat_tile(ROW_HOVER, LINE, 10, 4))
	button.add_theme_stylebox_override(&"pressed", selected)
	button.add_theme_stylebox_override(&"hover_pressed", selected)
	button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	button.add_theme_color_override(&"font_color", INK_DIM)
	button.add_theme_color_override(&"font_hover_color", INK)
	button.add_theme_color_override(&"font_pressed_color", GOLD)
	button.add_theme_color_override(&"font_hover_pressed_color", GOLD)
	button.focus_mode = Control.FOCUS_NONE


## Buy. The one filled button on the screen, so the eye lands on it.
static func style_primary(button: Button) -> void:
	button.add_theme_stylebox_override(&"normal", PixelUI.flat_tile(GOLD_FILL, GOLD, 10, 6))
	button.add_theme_stylebox_override(&"hover", PixelUI.flat_tile(GOLD, GOLD, 10, 6))
	button.add_theme_stylebox_override(&"pressed", PixelUI.flat_tile(GOLD_DARK, GOLD, 10, 6))
	button.add_theme_stylebox_override(&"disabled", PixelUI.flat_tile(ROW, LINE, 10, 6))
	button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	for state: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		button.add_theme_color_override(state, INK_ON_GOLD)
	button.add_theme_color_override(&"font_disabled_color", INK_DIM)
	button.add_theme_font_size_override(&"font_size", SIZE_BUTTON)
	button.focus_mode = Control.FOCUS_NONE


## Equip / Wear / Take off.
static func style_secondary(button: Button) -> void:
	button.add_theme_stylebox_override(&"normal", PixelUI.flat_tile(ROW, LINE, 10, 6))
	button.add_theme_stylebox_override(&"hover", PixelUI.flat_tile(ROW_HOVER, LINE, 10, 6))
	button.add_theme_stylebox_override(&"pressed", PixelUI.flat_tile(PANEL, LINE, 10, 6))
	button.add_theme_stylebox_override(&"disabled", PixelUI.flat_tile(PANEL, LINE, 10, 6))
	button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	button.add_theme_color_override(&"font_color", INK)
	button.add_theme_color_override(&"font_hover_color", INK)
	button.add_theme_color_override(&"font_disabled_color", INK_DIM)
	button.add_theme_font_size_override(&"font_size", SIZE_BUTTON)
	button.focus_mode = Control.FOCUS_NONE


## The selected item's name, over its description.
static func name_label() -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override(&"font_size", SIZE_NAME)
	label.add_theme_color_override(&"font_color", INK)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


## A line of description or status under the name.
static func note_label() -> Label:
	var label: Label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", SIZE_BODY)
	label.add_theme_color_override(&"font_color", INK_DIM)
	return label


## The two side-by-side buttons under a preview (Equip / Take off).
static func action_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	return row


static func action_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 36)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_secondary(button)
	return button


## The dark, opaque box every preview is drawn on.
static func stage_box() -> StyleBoxFlat:
	var box: StyleBoxFlat = PixelUI.flat_tile(BG, LINE, 0, 0)
	box.set_content_margin_all(0)
	return box


## The tag at the right of a shelf row: Equipped, Owned, or the price.
## [param token] is the VaultGrants token the Buy button prices; the catalog is
## asked through the Vault shell, so a panel running standalone gets no price
## rather than an error.
static func row_tag(from: Node, token: String, worn: bool, owned: bool) -> Dictionary:
	if worn:
		return {"text": "Equipped", "color": GOOD, "coin": false}
	var entry: Dictionary = catalog_entry(from, token)
	if owned or bool(entry.get("owned", false)):
		return {"text": "Owned", "color": INK_DIM, "coin": false}
	var cost: int = int(entry.get("cost", 0))
	if cost > 0:
		return {"text": str(cost), "color": GOLD, "coin": true}
	return {"text": "", "color": INK_DIM, "coin": false}


## The Vault shell's catalog row for [param token], or {} outside the Vault.
static func catalog_entry(from: Node, token: String) -> Dictionary:
	if from == null or token.is_empty():
		return {}
	var host: Node = from.get_parent()
	while host != null and not host.has_method("catalog_entry"):
		host = host.get_parent()
	if host == null:
		return {}
	return host.call("catalog_entry", token) as Dictionary
