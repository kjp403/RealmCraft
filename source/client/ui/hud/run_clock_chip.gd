extends RefCounted
## Shared chrome for the two run clocks — DungeonHud's count-up and BossHuntHud's
## contract countdown. Preloaded as a const rather than registered with a
## class_name: it is pure styling with no scene presence, same call as
## HudSlotStyle.
##
## Both clocks used to be the same ~300x60 slab pinned at offset_top = 44 with a
## 26px timer over a 14px detail line — which is exactly where boss_bar.tscn
## draws (y 14..82), so in the fights these clocks exist for, the panel printed
## through the boss's health bar and its HP readout. See the enrage screenshot
## from 2026-09-07.
##
## The replacement is one thin pill in the same language as the loot pills and
## toast cards (translucent near-black, pixel font, no chrome), parked in the
## upper-RIGHT rail under the minimap with the XP orb and the quest tracker —
## see Hud._place_right_rail. Nothing about a run clock needs the middle of the
## screen: it is glanced at, not read, and the centre column is the fight.

## Card look, matching Toaster.CARD_BG / LootFeed's pills / CombatAlert.
const BG: Color = Color(0.08, 0.09, 0.12, 0.86)
const RADIUS: int = 4
const PAD_X: int = 10
const PAD_Y: int = 3

## Clock ink, and the red both clocks turn when the run is one mistake from over
## (last minute of a contract / last revive of a hard dungeon).
const INK: Color = Color(0.93, 0.90, 0.82)
const URGENT: Color = Color(1.0, 0.42, 0.38)
## Detail ink — the kill tally / revive count riding beside the clock.
const DETAIL: Color = Color(1.0, 0.86, 0.5)


## Anchor [param chip] to the top-right rail, dress it, and return the row its
## labels go in. The vertical offset is NOT set here: Hud._place_right_rail owns
## it, so the clock slots in under the minimap and the XP orb like every other
## rail widget. RIGHT-aligned and content-sized, so the pill grows leftward into
## the rail's own lane and never toward the middle of the screen.
static func dress(chip: PanelContainer) -> HBoxContainer:
	chip.anchor_left = 1.0
	chip.anchor_right = 1.0
	chip.anchor_top = 0.0
	chip.anchor_bottom = 0.0
	chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chip.grow_vertical = Control.GROW_DIRECTION_END
	return style_only(chip)


## The pill's LOOK, with no opinion about where it goes. Split out of
## [method dress] for [FishingComboHud], which wears the same chrome but lives
## bottom-centre above the ability bar rather than in the upper-right rail —
## the rail has exactly one slot clear of the minimap and the open bag, and the
## XP orb is already in it.
##
## The two run clocks keep calling [method dress] and are untouched.
static func style_only(chip: PanelContainer) -> HBoxContainer:
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = BG
	style.set_corner_radius_all(RADIUS)
	style.content_margin_left = PAD_X
	style.content_margin_right = PAD_X
	style.content_margin_top = PAD_Y
	style.content_margin_bottom = PAD_Y
	chip.add_theme_stylebox_override(&"panel", style)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 9)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	return row


## The MM:SS readout — the one thing on the chip that has to be legible at a
## glance, so it keeps the largest size on it.
static func timer_label() -> Label:
	return _label(PixelUI.SIZE_BODY, INK)


## Everything else on the chip (boss, tally, lives, revives) on one small line.
static func detail_label() -> Label:
	return _label(PixelUI.SIZE_TINY, DETAIL)


static func _label(size: int, color: Color) -> Label:
	var label: Label = PixelUI.text("", size, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Pull the theme's 2px label shadow in — at 10-14px it is otherwise a smear.
	label.add_theme_constant_override(&"shadow_offset_y", 1)
	return label
