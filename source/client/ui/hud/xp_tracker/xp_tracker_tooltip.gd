class_name XpTrackerTooltip
extends PanelContainer
## The XP orb's hover card: which skill, what level, how far into it, and how
## much is left.
##
## Deliberately ONE scene serving two delivery paths, because the game ships to
## two platforms with different tooltip support:
##
##   desktop — returned from [method XpTrackerHud._make_custom_tooltip], which
##             Godot positions, shows and frees for us.
##   web     — instanced once by the orb and positioned by hand, because Godot's
##             tooltip popups do not render in the HTML5 export at all. That is
##             the same limitation [SlayerTracker] documents and works around.
##
## Two paths, one [method fill]: if the copy lived in each path instead, the web
## build would quietly drift into showing something different from the desktop
## build, and nobody would notice until a player mentioned it.

@onready var _icon: TextureRect = $Margin/Rows/Head/Icon
@onready var _title: Label = $Margin/Rows/Head/Title
@onready var _detail: Label = $Margin/Rows/Detail
@onready var _remaining: Label = $Margin/Rows/Remaining


func _ready() -> void:
	PixelUI.make_pixel_perfect(self)
	PixelUI.panel(self, "frame_stone", 8)
	PixelUI.label(_title, PixelUI.SIZE_CAPTION, PixelUI.INK_GOLD)
	PixelUI.label(_detail, PixelUI.SIZE_CAPTION, PixelUI.INK)
	PixelUI.label(_remaining, PixelUI.SIZE_TINY, PixelUI.INK_DIM)


## Dress the card for one skill.
##
## [param xp_into_level] is XP banked toward the next level and [param
## xp_to_next] the size of that level — the same pair the orb's arc divides, so
## the number the player reads here can never disagree with the arc they are
## reading it from. [param xp_to_next] of 0 means the skill is capped.
func fill(
	job: StringName,
	level: int,
	xp_into_level: int,
	xp_to_next: int,
	tint: Color,
) -> void:
	# Always the display name, never the slug: `outfitting` is Crafting and
	# `harvesting` is Farming, and a card that says "Harvesting" beside a Farming
	# skill bar reads as a bug.
	_title.text = "%s · Lv %d" % [JobRegistry.display_name(job), level]
	_title.add_theme_color_override(&"font_color", tint)
	_icon.texture = JobRegistry.icon_for(job)

	if xp_to_next <= 0:
		# Level 99. "13,034,431 / 0 XP (100.0%)" is worse than saying so.
		_detail.text = "Maximum level"
		_remaining.text = "Nothing left to train"
		return

	var banked: int = clampi(xp_into_level, 0, xp_to_next)
	var percent: float = float(banked) / float(xp_to_next) * 100.0
	_detail.text = "%s / %s XP (%.1f%%)" % [
		SkillXp.format_xp(banked), SkillXp.format_xp(xp_to_next), percent,
	]
	_remaining.text = "%s XP to level %d" % [
		SkillXp.format_xp(xp_to_next - banked), level + 1,
	]
