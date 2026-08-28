extends RefCounted
## Shared HUD keybind skin: the tile used by the ability bar (LMB / Q / E / R / C)
## and the quick-slot rail (1-5). Preloaded as a const rather than registered as
## a class_name — it is pure styling with no scene presence.
##
## Faces are built once and shared by every tile (HudSlotBox is stateless), so
## [method set_live] costs a stylebox swap, not an allocation. Deliberately NOT
## the theme's rounded SlotButton look: at HUD size the bubble corners ate icon
## pixels and read as chat bubbles floating over the fight.
##
## LIVE state: while the slot's input is held the tile switches to a green
## frame + halo, so a press is visible on the bar itself — you can see at a
## glance which key you are leaning on and that the game registered it.

const BOX: GDScript = preload("res://source/client/ui/hud/hud_slot_box.gd")

const LIVE_FRAME: Color = Color(0.38, 1.0, 0.48, 1.0)
const LIVE_HALO: Color = Color(0.38, 1.0, 0.48, 0.28)
const LIVE_PLATE_TOP: Color = Color(0.11, 0.20, 0.13, 0.94)
const LIVE_PLATE_BOTTOM: Color = Color(0.04, 0.08, 0.05, 0.94)

## Set on a button by [method apply]; [method set_live] reads it to skip
## redundant swaps (it is called every frame from the bar's _process).
const LIVE_META: StringName = &"hud_slot_live"

static var _idle: StyleBox
static var _hover: StyleBox
static var _live: StyleBox
static var _disabled: StyleBox
static var _track: StyleBox


## Skins [param button] in every state. The overrides beat whatever theme
## variation is set on it.
static func apply(button: Button) -> void:
	button.add_theme_stylebox_override(&"normal", idle())
	button.add_theme_stylebox_override(&"hover", hover())
	# A real click/tap lights the same green as a key press.
	button.add_theme_stylebox_override(&"pressed", live())
	button.add_theme_stylebox_override(&"focus", hover())
	button.add_theme_stylebox_override(&"disabled", disabled())
	button.set_meta(LIVE_META, false)


## Green "input is down" face. Safe to call every frame — it returns early
## unless the state actually changed.
static func set_live(button: Button, live_now: bool) -> void:
	if button == null or not is_instance_valid(button):
		return
	if bool(button.get_meta(LIVE_META, false)) == live_now:
		return
	button.set_meta(LIVE_META, live_now)
	button.add_theme_stylebox_override(&"normal", live() if live_now else idle())
	button.add_theme_stylebox_override(&"hover", live() if live_now else hover())


static func idle() -> StyleBox:
	if _idle == null:
		_idle = BOX.new()
	return _idle


static func hover() -> StyleBox:
	if _hover == null:
		var box: StyleBox = BOX.new()
		box.plate_top = Color(0.18, 0.19, 0.23, 0.94)
		box.plate_bottom = Color(0.07, 0.07, 0.10, 0.94)
		box.frame = Color(0.85, 0.70, 0.45, 1.0)
		box.bracket = Color(0.98, 0.84, 0.56, 0.95)
		_hover = box
	return _hover


static func live() -> StyleBox:
	if _live == null:
		var box: StyleBox = BOX.new()
		box.plate_top = LIVE_PLATE_TOP
		box.plate_bottom = LIVE_PLATE_BOTTOM
		box.frame = LIVE_FRAME
		box.frame_width = 2.0
		box.bracket = LIVE_FRAME
		box.halo = LIVE_HALO
		_live = box
	return _live


## The empty channel behind a resource bar's ink: the same chamfered plate as
## the keybind tiles, darker, and with the corner brackets off — on a 15px bar
## they read as clutter rather than as framing.
static func track() -> StyleBox:
	if _track == null:
		var box: StyleBox = BOX.new()
		box.plate_top = Color(0.03, 0.03, 0.04, 0.90)
		box.plate_bottom = Color(0.07, 0.07, 0.09, 0.90)
		box.frame = Color(0.52, 0.43, 0.32, 0.95) # same bronze as the keybind tiles
		box.bracket = Color(0.0, 0.0, 0.0, 0.0) # off
		_track = box
	return _track


## Skins [param panel] as a resource-bar channel.
static func apply_track(panel: Panel) -> void:
	panel.add_theme_stylebox_override(&"panel", track())


## Makes [param bar] draw nothing at all. The bars keep their ProgressBars as
## the value holder the existing tweens animate; an InkFill sibling does the
## drawing, so the ProgressBar itself must be invisible.
static func clear_bar(bar: ProgressBar) -> void:
	bar.add_theme_stylebox_override(&"background", StyleBoxEmpty.new())
	bar.add_theme_stylebox_override(&"fill", StyleBoxEmpty.new())


static func disabled() -> StyleBox:
	if _disabled == null:
		var box: StyleBox = BOX.new()
		box.frame = Color(0.34, 0.30, 0.26, 0.7)
		box.bracket = Color(0.45, 0.40, 0.32, 0.5)
		_disabled = box
	return _disabled
