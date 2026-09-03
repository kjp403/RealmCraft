class_name VipTierProfile
extends Resource
## Everything that makes one VIP donation tier look like itself: the metal the
## letters are cut from, and the particles that hang off them.
##
## FOUR TIERS, ONE LADDER. Diamond, Platinum, Golden and Silver are read against
## each other - a player who upgrades has to SEE the step - so the four .tres
## files next door are meant to be opened side by side and tuned as a set. That
## is the whole argument for a resource rather than a const Dictionary like
## [SupporterTitles]: the ladder is a design surface, and it changes as a unit.
##
## The tier's identity still lives in [SupporterTitles], keyed by slug, because
## that is what /supporter grants and what the database stores. This resource is
## only the LOOK. A profile with no matching supporter entry is dead weight, and
## a supporter entry naming a profile that does not load falls back to the plain
## supporter treatment rather than erroring - see [method for_tier].

const DIR: String = "res://source/common/gameplay/titles/profiles/"

## tier key -> profile, filled on first ask. Static so thirty players wearing the
## same tier in a bank share one load rather than one each.
static var _cache: Dictionary = {}

## Matches the `vip_tier` key in [SupporterTitles.BY_SLUG]. The profile is looked
## up by this, NOT by filename, so a rename cannot silently unhook a tier.
@export var tier: StringName = &""
## For tools and the vault row. The authoritative display name is the supporter
## entry's; this is here so a profile can be identified on its own.
@export var display_name: String = ""
## Chat bracket / list colour. Has to read on its own against a dark chat
## backdrop, not merely as a seed for the gradient below.
@export var accent: Color = Color(1.0, 1.0, 1.0)

@export_group("Metal")
## The vertical gradient the letters are mapped through, top to bottom:
## [member metal_high] at the crown, [member metal_mid] through the body,
## [member metal_low] at the base - then a rim of `high` again at the very
## bottom, which is what makes cast metal read as cast rather than as flat fill.
@export var metal_high: Color = Color(1.0, 1.0, 1.0)
@export var metal_mid: Color = Color(0.8, 0.8, 0.8)
@export var metal_low: Color = Color(0.4, 0.4, 0.4)
## The travelling specular sweep. Near-white for cold metals, warm for gold.
@export var sheen: Color = Color(1.0, 1.0, 1.0)
## Drop shadow behind the glyphs. Separate from the outline: the outline is the
## legibility guarantee and is near-black everywhere, the shadow is depth and is
## allowed to carry tier colour.
@export var shadow: Color = Color(0.0, 0.0, 0.0, 0.55)
@export var shadow_offset: Vector2i = Vector2i(0, 3)
## Per-tier outline override. Left fully transparent, [constant
## TitleVfx.OUTLINE_COLOR] is used - which is what every tier should do unless it
## has a specific reason, because that constant IS the contrast guarantee.
@export var outline_override: Color = Color(0.0, 0.0, 0.0, 0.0)
## Per-tier outline WEIGHT, in the label's own units. 0 = the shared
## [constant TitleVfx.OUTLINE_SIZE_VIP] / [constant TitleVfx.OUTLINE_SIZE].
##
## Diamond is the reason this exists: a heavy black border around white letters
## is the look, not merely legibility insurance, so the border is part of the
## tier's design rather than a constant it inherits. Anything set here must reach
## the pulse node as well as the theme override - that node re-asserts the
## outline EVERY frame, so a size applied only at mount time is silently replaced
## by the shared one a frame later.
@export_range(0, 24, 1) var outline_size: int = 0

@export_group("Animation")
## Sweeps per second across the word. Slow reads as expensive; fast reads cheap.
@export_range(0.02, 1.5, 0.01) var sweep_speed: float = 0.24
## Half-width of the specular band in UV. Wide = a soft polish, narrow = a glint.
@export_range(0.02, 0.4, 0.005) var sweep_width: float = 0.10
@export_range(0.0, 1.2, 0.01) var sheen_amount: float = 0.45
@export_range(0.0, 0.4, 0.005) var pulse_amount: float = 0.08
@export_range(0.2, 6.0, 0.05) var pulse_speed: float = 2.2
## Tarnish. Multiplies a blocky hash into the metal so it reads as aged rather
## than polished. Silver's signature; zero everywhere else.
@export_range(0.0, 1.0, 0.01) var grain: float = 0.0
## Chromatic split on the specular band - the red and blue edges of the sweep
## land slightly apart, which is the only honest way to suggest refraction here.
## A real screen-space refraction is impossible: hint_screen_texture samples
## solid black under the GL Compatibility renderer this project ships.
@export_range(0.0, 1.0, 0.01) var prism: float = 0.0
## Hard steps to quantise the metal ramp into - cut stone rather than poured
## metal. 0 leaves the ramp smooth, which is right for gold and silver.
@export_range(0.0, 12.0, 1.0) var facets: float = 0.0
## Dispersion: how far the polish band's colour is pulled through the spectrum
## instead of staying [member sheen]. This is what makes a gem throw colour it
## does not have; on a poured metal it just looks broken.
@export_range(0.0, 1.0, 0.01) var fire: float = 0.0
## A second polish band at this speed, crossing the first. 0 = off.
@export_range(0.0, 1.5, 0.01) var sweep_speed2: float = 0.0
## Light-ray fan drawn BEHIND the glyphs, the same seven-triangle burst HIGH
## PRIEST uses. Fully transparent = no fan, which is every tier but Diamond; the
## alpha here is the fan's peak opacity, so one field both switches it on and
## sets how loud it is.
##
## Drawn rather than particled because a ray is a long triangle anchored at one
## point, and a particle system can only place sprites - a fan of sprites reads
## as a row of streaks, not as light from a single source.
@export var ray_color: Color = Color(1.0, 1.0, 1.0, 0.0)

@export_group("Emitters")
## Built in order, so a layer meant to sit behind the others goes first.
@export var layers: Array[VipParticleLayer] = []


## Profile for [param tier], or null when the tier has none.
##
## Never pushes an error for a miss: an unknown tier means a supporter entry and
## the profiles directory disagree, and the correct behaviour then is for the
## title to fall back to the plain supporter treatment - a title with no sparkle
## rather than a player with no title. tools/verify_vip_titles.gd is what turns
## that disagreement into a loud failure, where it can be fixed.
static func for_tier(tier_key: StringName) -> VipTierProfile:
	if tier_key == &"":
		return null
	if _cache.has(tier_key):
		return _cache[tier_key]
	var path: String = DIR + String(tier_key) + ".tres"
	var loaded: VipTierProfile = null
	if ResourceLoader.exists(path):
		loaded = ResourceLoader.load(path) as VipTierProfile
	_cache[tier_key] = loaded
	return loaded


## The outline this tier actually uses. Transparent override = [param fallback],
## which every caller passes [constant TitleVfx.OUTLINE_COLOR] for.
##
## The fallback is a PARAMETER rather than read from TitleVfx here on purpose.
## TitleVfx preloads [VipTitleEffect], which types against this resource, so
## naming TitleVfx from inside it closes a load-time cycle between the three
## scripts. Anything opaque passed as an override still has to be dark enough to
## back bright letters over pale ground; the verifier checks its luminance.
func outline_color(fallback: Color) -> Color:
	if outline_override.a <= 0.0:
		return fallback
	return outline_override
