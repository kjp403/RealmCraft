class_name PixelUI
## Shared pixel-art chrome for the Daily Skilling Board and the chest reward
## window: 9-slice frames, the pixel font, the palette, and the chest icons.
##
## WHY A HELPER AND NOT A Theme RESOURCE
## A [Theme] maps a CONTROL TYPE to a look ("every Button gets this stylebox").
## What these two screens need is the opposite — the same Button appears as a
## stone panel, a parchment quest badge and a gold claim button depending on what
## it means. That is per-widget intent, not per-type styling, so it belongs in
## code the widgets call. The project Theme still supplies everything generic.
##
## PIXEL DISCIPLINE
## Every texture here is authored at 1x on a 1px grid by tools/build_ui_frames.py
## and MUST be drawn with NEAREST filtering. Callers get that for free by calling
## [method make_pixel_perfect] on their root Control once — texture_filter
## inherits down the tree, so one call covers every child built afterwards.
## Nothing here should ever be scaled by a non-integer factor.

const FRAMES: String = "res://assets/sprites/ui/frames/"
const CHESTS: String = "res://assets/sprites/environment/chests/"
const FONT_PATH: String = "res://assets/fonts/kenney_mini.ttf"
const SHIMMER_SHADER: String = "res://source/client/ui/themes/rare_shimmer.gdshader"

## 9-slice margin baked into every frame texture by the generator. Corners and
## edges inside this margin never stretch.
const FRAME_MARGIN: float = 8.0

# --- Palette ---------------------------------------------------------------
# Deliberately small and shared. A pixel-art UI falls apart when each screen
# invents its own near-blacks and near-golds.

const INK: Color = Color(0.93, 0.90, 0.82)          # default text
const INK_DIM: Color = Color(0.62, 0.62, 0.68)      # secondary text
const INK_GOLD: Color = Color(1.0, 0.86, 0.50)      # headings, amounts
const INK_COIN: Color = Color(1.0, 0.80, 0.34)      # currency
const INK_XP: Color = Color(0.55, 0.78, 1.0)        # experience
const INK_GREEN: Color = Color(0.55, 0.85, 0.45)    # complete / success
const INK_PARCHMENT: Color = Color(0.16, 0.12, 0.07) # ink ON parchment

## Difficulty accents, indexed by DailyTaskResource.Difficulty.
const DIFFICULTY_INK: Array[Color] = [
	Color(0.60, 0.90, 0.50),
	Color(1.0, 0.82, 0.36),
	Color(1.0, 0.52, 0.46),
]
## Matching frame textures, same order.
const DIFFICULTY_FRAME: Array[String] = ["frame_easy", "frame_medium", "frame_hard"]

## Rarity tier name -> (frame texture, ink colour). Tier names come from the
## SERVER ([LootRarity]); this is only how each one looks.
const RARITY_LOOK: Dictionary[String, Array] = {
	"common": ["frame_iron", Color(0.80, 0.82, 0.86)],
	"uncommon": ["frame_easy", Color(0.60, 0.90, 0.50)],
	"rare": ["frame_rare", Color(0.52, 0.74, 1.0)],
	"ultra": ["frame_gold", Color(1.0, 0.80, 0.32)],
}

## Chest art per difficulty tier (T1/T2/T3). Real 16x16 sprites from the world
## chest set, so the icon on a reward badge is the chest the player will see.
const CHEST_ICON: Array[String] = [
	"wood_silver_small",    # T1 — small wooden chest, iron bands
	"wood_gold_large",      # T2 — larger chest, gold bands
	"gold_steel_masterwork" # T3 — ornate gilded strongbox
]

## One type scale for both screens. Three steps is enough hierarchy for a panel
## and keeps the UI from drifting into a dozen near-identical sizes.
const SIZE_HEADING: int = 20
const SIZE_BODY: int = 14
const SIZE_CAPTION: int = 12
const SIZE_TINY: int = 10

static var _font_cache: FontFile = null
static var _shader_cache: Shader = null


# --- Frames ------------------------------------------------------------------

## A 9-slice [StyleBoxTexture] for [param frame_name] (a file in [constant FRAMES],
## without extension). [param pad] is the content inset — how far text sits from
## the carved border.
static func frame(frame_name: String, pad: int = 10) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(FRAMES + frame_name + ".png") as Texture2D
	# The 8px margin is what makes this a 9-slice: corners are drawn 1:1, only
	# the 8x8 centre stretches. Without it the rivets would smear across the edge.
	sb.texture_margin_left = FRAME_MARGIN
	sb.texture_margin_right = FRAME_MARGIN
	sb.texture_margin_top = FRAME_MARGIN
	sb.texture_margin_bottom = FRAME_MARGIN
	sb.content_margin_left = float(pad)
	sb.content_margin_right = float(pad)
	sb.content_margin_top = float(pad)
	sb.content_margin_bottom = float(pad)
	return sb


## Frame tinted through modulate — for the pulsing outline on a rare reward.
## Returns the stylebox so the caller can animate `modulate_color` directly.
static func tinted_frame(frame_name: String, tint: Color, pad: int = 10) -> StyleBoxTexture:
	var sb: StyleBoxTexture = frame(frame_name, pad)
	sb.modulate_color = tint
	return sb


## Apply a 9-slice frame to any Control that takes a "panel" stylebox.
static func panel(target: Control, frame_name: String, pad: int = 10) -> void:
	target.add_theme_stylebox_override(&"panel", frame(frame_name, pad))


## Style a Button with one frame across all four states, brightened on hover and
## dimmed on press. One texture, three modulates — a pixel-art button should not
## change SHAPE between states, only value.
static func button_frame(target: Button, frame_name: String, pad: int = 8) -> void:
	target.add_theme_stylebox_override(&"normal", frame(frame_name, pad))
	target.add_theme_stylebox_override(&"hover", tinted_frame(frame_name, Color(1.22, 1.22, 1.22), pad))
	target.add_theme_stylebox_override(&"pressed", tinted_frame(frame_name, Color(0.80, 0.80, 0.80), pad))
	target.add_theme_stylebox_override(&"focus", tinted_frame(frame_name, Color(1.10, 1.10, 1.10), pad))
	target.add_theme_stylebox_override(&"disabled", tinted_frame(frame_name, Color(0.55, 0.55, 0.60), pad))


# --- Type --------------------------------------------------------------------

## The pixel font. Imported with antialiasing, hinting and subpixel positioning
## all OFF (see assets/fonts/kenney_mini.ttf.import) — any one of them left on
## resamples glyphs off the pixel grid and produces the grey fringing that reads
## as a blurry font over crisp art.
static func font() -> FontFile:
	if _font_cache == null:
		_font_cache = load(FONT_PATH) as FontFile
	return _font_cache


## Apply the pixel font at [param size] to a Label.
##
## kenney_mini is a scalable pixel-STYLE typeface, not a fixed-grid bitmap, so it
## rasterises cleanly at any integer size once antialiasing and hinting are off —
## verified 10 through 24. Sizes are chosen for hierarchy, not for a grid:
## [constant SIZE_HEADING] / [constant SIZE_BODY] / [constant SIZE_CAPTION].
## Do NOT feed it a fractional size; that reintroduces subpixel placement.
static func label(target: Label, size: int = 16, color: Color = INK) -> Label:
	target.add_theme_font_override(&"font", font())
	target.add_theme_font_size_override(&"font_size", size)
	target.add_theme_color_override(&"font_color", color)
	return target


## Build a pixel-font Label in one call.
static func text(value: String, size: int = 16, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = value
	return label(l, size, color)


## Same for a Button's own label.
static func button_font(target: Button, size: int = 16, color: Color = INK) -> void:
	target.add_theme_font_override(&"font", font())
	target.add_theme_font_size_override(&"font_size", size)
	target.add_theme_color_override(&"font_color", color)
	target.add_theme_color_override(&"font_hover_color", color.lightened(0.25))
	target.add_theme_color_override(&"font_pressed_color", color.darkened(0.15))
	target.add_theme_color_override(&"font_disabled_color", Color(color, 0.40))


# --- Bars --------------------------------------------------------------------

## A textured progress bar: recessed channel, lit fill with an inner highlight
## line. [param tint] recolours the neutral fill art, so every bar in the game
## shares one texture and one set of shading.
static func progress_bar(bar: ProgressBar, tint: Color, height: int = 12) -> void:
	var track := StyleBoxTexture.new()
	track.texture = load(FRAMES + "bar_track.png") as Texture2D
	track.texture_margin_left = 4.0
	track.texture_margin_right = 4.0
	track.texture_margin_top = 4.0
	track.texture_margin_bottom = 4.0
	bar.add_theme_stylebox_override(&"background", track)

	var fill := StyleBoxTexture.new()
	fill.texture = load(FRAMES + "bar_fill.png") as Texture2D
	fill.texture_margin_left = 4.0
	fill.texture_margin_right = 4.0
	fill.texture_margin_top = 2.0
	fill.texture_margin_bottom = 2.0
	fill.modulate_color = tint
	bar.add_theme_stylebox_override(&"fill", fill)

	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)


# --- Slots + icons -----------------------------------------------------------

## Flat square tile: 1px crisp border, flat interior, no texture.
##
## THE LIGHT HALF OF THE HIERARCHY. A carved 9-slice frame is a heavy object; a
## UI where every tab, row and chip is carved reads as clutter, not craft. So the
## chrome has two weights:
##   [method frame] / [method panel] — carved, for WINDOWS and major panels.
##   this — flat and square, for the small repeated furniture inside them.
## What makes it pixel-correct is not a texture, it is the absence of a corner
## radius: a 1px square border has no curve to anti-alias, so it rasterises
## identically to drawn pixel art. (market_style.gd reached the same conclusion
## independently — every radius in it is explicitly 0.)
static func flat_tile(
	fill: Color, border: Color = Color(0, 0, 0, 0), pad_x: int = 8, pad_y: int = 4
) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	# Explicitly square. This is the whole point of the style.
	sb.set_corner_radius_all(0)
	sb.anti_aliasing = false
	if border.a > 0.0:
		sb.set_border_width_all(1)
		sb.border_color = border
	sb.content_margin_left = float(pad_x)
	sb.content_margin_right = float(pad_x)
	sb.content_margin_top = float(pad_y)
	sb.content_margin_bottom = float(pad_y)
	return sb


## Tab-rail button: transparent at rest, a filled square on hover, and an accent
## underline when active. The underline carries the state rather than a frame, so
## a rail of eight tabs stays legible instead of becoming eight carved boxes.
static func tab_button(button: Button, accent: Color) -> void:
	var rest: StyleBoxFlat = flat_tile(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 7, 3)
	var hover: StyleBoxFlat = flat_tile(Color(0.18, 0.20, 0.27, 0.9), Color(0, 0, 0, 0), 7, 3)
	var active: StyleBoxFlat = flat_tile(Color(0.19, 0.21, 0.28, 1.0), Color(0, 0, 0, 0), 7, 3)
	# Underline only — a bottom border on a square box is a 1px run of pixels.
	active.border_width_bottom = 2
	active.border_color = accent
	button.add_theme_stylebox_override(&"normal", rest)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", active)
	button.add_theme_stylebox_override(&"focus", rest)
	button.add_theme_font_override(&"font", font())
	button.add_theme_font_size_override(&"font_size", SIZE_CAPTION)
	button.add_theme_color_override(&"font_color", INK_DIM)
	button.add_theme_color_override(&"font_hover_color", INK)
	button.add_theme_color_override(&"font_pressed_color", accent)
	button.add_theme_color_override(&"font_hover_pressed_color", accent)


## A recessed item slot, the same one the inventory grid uses.
static func slot_style() -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(FRAMES + "slot.png") as Texture2D
	for side: StringName in [&"left", &"right", &"top", &"bottom"]:
		sb.set(&"texture_margin_" + side, 6.0)
	return sb


## Chest sprite for a difficulty tier (0/1/2 = T1/T2/T3).
static func chest_texture(tier_index: int) -> Texture2D:
	var i: int = clampi(tier_index, 0, CHEST_ICON.size() - 1)
	return load(CHESTS + CHEST_ICON[i] + ".png") as Texture2D


## The shimmer material for a rare slot background. A FRESH material per call:
## they carry per-instance colours, and sharing one would make every rare row
## shimmer in the same colour as the last one created.
static func shimmer_material(shine: Color, base: Color = Color(0.09, 0.10, 0.13)) -> ShaderMaterial:
	if _shader_cache == null:
		_shader_cache = load(SHIMMER_SHADER) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = _shader_cache
	mat.set_shader_parameter(&"shine_color", shine)
	mat.set_shader_parameter(&"base_color", base)
	return mat


# --- HUD overlay cards -------------------------------------------------------

## THE HUD OVERLAY STANDARD — one look for every transient card that floats over
## the WORLD rather than sitting inside a menu: toasts, the loot feed, the quest
## tracker, the party roster.
##
## WHY THESE ARE NOT [method frame] OR [method flat_tile]
## Both of those are chrome for things the player is LOOKING AT. An overlay card
## is something the player is looking THROUGH — it has to stay legible over a
## bright grass tile without reading as a menu that stole focus. So it is a third
## weight: translucent near-black, a hairline accent border at low alpha, and a
## small radius so it never squares up into a panel.
##
## The values are the ones the toast rework landed on and shipped; they live here
## so the other three surfaces cannot drift a near-black or a padding away from
## them. Change them HERE, never per-widget.
const HUD_CARD_BG: Color = Color(0.102, 0.102, 0.102, 0.8) # #1a1a1acc
const HUD_CARD_BORDER: Color = Color(0.58, 0.82, 0.98, 0.22)
const HUD_CARD_RADIUS: int = 4
const HUD_CARD_PAD_X: int = 7
const HUD_CARD_PAD_Y: int = 4

## The overlay card background. Padding rides on the STYLEBOX, not an inner
## MarginContainer — one node fewer per card, and it is what makes the panel wrap
## its content tightly instead of inheriting a container's idea of roomy.
static func hud_card(pad_x: int = HUD_CARD_PAD_X, pad_y: int = HUD_CARD_PAD_Y) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = HUD_CARD_BG
	style.border_color = HUD_CARD_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(HUD_CARD_RADIUS)
	style.content_margin_left = float(pad_x)
	style.content_margin_right = float(pad_x)
	style.content_margin_top = float(pad_y)
	style.content_margin_bottom = float(pad_y)
	return style


## A label for an overlay card: pixel font, left-aligned, click-through, and the
## theme's 2px drop shadow pulled in to 1px.
##
## THE SHADOW IS THE LOAD-BEARING PART. theme_horizon sets
## Label/constants/shadow_offset_y = 2, which is tuned for 16px menu text. At the
## 10-12px an overlay card uses, a 2px offset is a fifth of the glyph height — it
## reads as a grey smear under every letter and is exactly what makes small HUD
## text look blurry over the world. 1px is one pixel of separation, which is all
## a pixel font needs.
static func hud_label(target: Label, size: int = SIZE_CAPTION, color: Color = INK) -> Label:
	label(target, size, color)
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_theme_constant_override(&"shadow_offset_y", 1)
	return target


## The overlay-card treatment for a bare icon BUTTON — the chat bubble and the
## kebab on the top-left rail.
##
## WHY THIS EXISTS AT ALL
## theme_horizon styles every Button with the carved frame_iron 9-slice
## (Button/styles/normal = SBT_btn_normal). On a 40x40 icon button that frame's
## 8px texture margin plus its 10/6 content margin leaves a 20x28 hole for the
## glyph — the border IS the button, visually, and three of them stacked read as
## a row of heavy carved boxes rather than as controls. Overriding the four
## states here puts the rail in the same visual language as the cards it sits
## next to: flat dark ground, hairline edge, state carried by VALUE only.
##
## [param pad] is the breathing room around the glyph. Pair it with the matching
## `inset` on [method PixelIcon.from_button] so the art is fitted to the interior
## rather than to the button's full rect.
static func hud_icon_button(button: Button, pad: int = 6) -> void:
	var rest: StyleBoxFlat = hud_card(pad, pad)
	var hover: StyleBoxFlat = hud_card(pad, pad)
	hover.bg_color = Color(0.17, 0.19, 0.24, 0.88)
	hover.border_color = Color(HUD_CARD_BORDER, 0.55)
	var pressed: StyleBoxFlat = hud_card(pad, pad)
	pressed.bg_color = Color(0.07, 0.08, 0.10, 0.92)
	pressed.border_color = Color(HUD_CARD_BORDER, 0.70)
	button.add_theme_stylebox_override(&"normal", rest)
	button.add_theme_stylebox_override(&"hover", hover)
	button.add_theme_stylebox_override(&"pressed", pressed)
	# Focus and disabled would otherwise fall back to the carved theme frame and
	# the button would visibly change WEIGHT the moment it is tabbed to.
	button.add_theme_stylebox_override(&"focus", rest)
	button.add_theme_stylebox_override(&"disabled", hud_card(pad, pad))


## Build an overlay-card label in one call. The HUD counterpart of [method text].
static func hud_text(value: String, size: int = SIZE_CAPTION, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = value
	return hud_label(l, size, color)


# --- Discipline --------------------------------------------------------------

## Call once on a window's root. texture_filter inherits down the tree, so this
## covers every child built afterwards and is the single thing standing between
## this art and a bilinear smear.
static func make_pixel_perfect(root: Control) -> void:
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
