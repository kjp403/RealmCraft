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

## Resolved by [method _resolve], NOT @onready. The desktop path fills the card
## before Godot has put it in the tree (see
## [method XpTrackerHud._make_custom_tooltip]) and @onready only assigns on tree
## entry, so an @onready ref here is null for exactly the one caller that
## matters — every hover wrote to four null references.
var _icon: TextureRect
var _title: Label
var _detail: Label
var _remaining: Label

## Last values [method fill] was handed, replayed once [method _ready] has run.
## A pre-tree fill paints the title in the skill tint and _ready's
## [method PixelUI.label] then writes font_color again, so without the replay
## every card would come up gold whatever skill it described.
var _has_values: bool = false
var _job: StringName = &""
var _level: int = 0
var _xp_into_level: int = 0
var _xp_to_next: int = 0
var _tint: Color = PixelUI.INK_GOLD


func _ready() -> void:
	_resolve()
	PixelUI.make_pixel_perfect(self)
	PixelUI.panel(self, "frame_stone", 8)
	PixelUI.label(_title, PixelUI.SIZE_CAPTION, PixelUI.INK_GOLD)
	PixelUI.label(_detail, PixelUI.SIZE_CAPTION, PixelUI.INK)
	PixelUI.label(_remaining, PixelUI.SIZE_TINY, PixelUI.INK_DIM)
	if _has_values:
		_paint()


## Bind the child labels. Safe before the card is in the tree — the children
## exist from the moment the scene is instantiated — and cheap to call twice.
func _resolve() -> void:
	if _title != null:
		return
	_icon = $Margin/Rows/Head/Icon
	_title = $Margin/Rows/Head/Title
	_detail = $Margin/Rows/Detail
	_remaining = $Margin/Rows/Remaining


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
	_job = job
	_level = level
	_xp_into_level = xp_into_level
	_xp_to_next = xp_to_next
	_tint = tint
	_has_values = true
	_resolve()
	_paint()


## Write the stored values onto the labels. Split out of [method fill] so
## [method _ready] can re-run it after the theme lands.
func _paint() -> void:
	# Always the display name, never the slug: `outfitting` is Crafting and
	# `harvesting` is Farming, and a card that says "Harvesting" beside a Farming
	# skill bar reads as a bug.
	_title.text = "%s · Lv %d" % [JobRegistry.display_name(_job), _level]
	_title.add_theme_color_override(&"font_color", _tint)
	_icon.texture = JobRegistry.icon_for(_job)

	if _xp_to_next <= 0:
		# Level 99. "13,034,431 / 0 XP (100.0%)" is worse than saying so.
		_detail.text = "Maximum level"
		_remaining.text = "Nothing left to train"
		return

	var banked: int = clampi(_xp_into_level, 0, _xp_to_next)
	var percent: float = float(banked) / float(_xp_to_next) * 100.0
	_detail.text = "%s / %s XP (%.1f%%)" % [
		SkillXp.format_xp(banked), SkillXp.format_xp(_xp_to_next), percent,
	]
	_remaining.text = "%s XP to level %d" % [
		SkillXp.format_xp(_xp_to_next - banked), _level + 1,
	]
