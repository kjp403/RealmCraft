class_name CosmeticThemes
## ONE COLOUR, THREE PRODUCTS. A theme ties a title, an aura and a body dye to
## the same base hex, so "Frost" bought in the Titles tab, "Frost" bought in the
## Cosmetics tab and the Frost dye bought in the Skins tab are visibly the same
## colour rather than three people's idea of what frost looks like.
##
## THE DYE IS THE SOURCE. [member VaultSkins.STYLE_META] already holds a tint per
## dye and those tints are what a player sees painted on their own body, so a
## theme NAMES A DYE STYLE rather than carrying a hex of its own. There is no
## second palette to drift: change the dye, and the title text, the title's
## particles and the matching aura all move with it.
##
## WHAT A THEME CARRIES:
##   core    the dye's own tint. The colour the product IS.
##   accent  a SECOND dye, for the looks that need two hues to read - ember over
##           crimson, cyan over frost. Also a dye tint, never a free hex.
##   pale    core lightened. Highlights, glint cores, the hot middle of a spark.
##   deep    core darkened. Shadow, ash, the outer edge of a bloom.
##
## pale and deep are DERIVED rather than authored for the same reason core is not:
## a third and fourth hand-picked hex per theme is three more numbers that can
## disagree with the dye, and a lightened/darkened pair is what every one of these
## looks actually wanted anyway.
##
## THE MULTI-COLOUR THEME IS THE ONE EXCEPTION, and it is still not a free hex:
## [constant PRISM] names the whole dye set and walks it. Its `core` is a real dye
## like everyone else's - the pale cyan the prism splits - so the places that can
## only show ONE colour (a chat bracket, a roster row) still have one to show.

const CORE_LIGHTEN: float = 0.55
const CORE_DARKEN: float = 0.58

## Theme keys. Used as StringNames everywhere; spelled once here so a typo in a
## catalog entry is a missing constant rather than a silently themeless title.
const CRIMSON: StringName = &"crimson"
const ARCANE: StringName = &"arcane"
const GLACIAL: StringName = &"glacial"
const VERDANT: StringName = &"verdant"
const STORM: StringName = &"storm"
const LOTUS: StringName = &"lotus"
const SOLAR: StringName = &"solar"
const PRISM: StringName = &"prism"

## Display order. Titles, auras and the verifier all iterate this, so the shop
## shelves list the set in one order rather than three.
const ORDER: Array[StringName] = [
	CRIMSON, ARCANE, GLACIAL, VERDANT, STORM, LOTUS, SOLAR, PRISM,
]

## THE TABLE.
##
##   dye / accent_dye  a [VaultSkins] STYLE_* constant. The colour lives THERE.
##   title             the [TitleCatalog] PREMIUM slug wearing this theme.
##   aura              the [Cosmetics] slug of the matching aura.
##   fx                the branch index in theme_title.gdshader. One per theme;
##                     the shader has no other way to tell them apart.
const THEMES: Dictionary = {
	CRIMSON: {
		"label": "Crimson",
		"dye": VaultSkins.STYLE_CRIMSON,
		"accent_dye": VaultSkins.STYLE_EMBER,
		"title": "crimson-warlord",
		"aura": &"aura_crimson_embers",
		"fx": 0,
	},
	ARCANE: {
		"label": "Arcane",
		"dye": VaultSkins.STYLE_VOID,
		# Gold sigils over violet. The alchemical read is the contrast between the
		# two, so the accent here is doing real work rather than tinting a highlight.
		"accent_dye": VaultSkins.STYLE_AMBER,
		"title": "arcane-magus",
		"aura": &"aura_arcane_sigils",
		"fx": 1,
	},
	GLACIAL: {
		"label": "Glacial",
		"dye": VaultSkins.STYLE_FROST,
		"accent_dye": VaultSkins.STYLE_AETHER,
		"title": "glacial-sovereign",
		"aura": &"aura_glacial_veil",
		"fx": 2,
	},
	VERDANT: {
		"label": "Verdant",
		"dye": VaultSkins.STYLE_VERDANT,
		"accent_dye": VaultSkins.STYLE_TOXIC,
		"title": "verdant-warden",
		"aura": &"aura_verdant_bloom",
		"fx": 3,
	},
	STORM: {
		"label": "Storm",
		"dye": VaultSkins.STYLE_SAPPHIRE,
		"accent_dye": VaultSkins.STYLE_AETHER,
		"title": "aether-storm",
		"aura": &"aura_aether_arcs",
		"fx": 4,
	},
	LOTUS: {
		"label": "Lotus",
		"dye": VaultSkins.STYLE_ROSE,
		"accent_dye": VaultSkins.STYLE_FROST,
		"title": "lotus-weaver",
		"aura": &"aura_lotus_petals",
		"fx": 5,
	},
	SOLAR: {
		"label": "Solar",
		"dye": VaultSkins.STYLE_GOLD,
		"accent_dye": VaultSkins.STYLE_AMBER,
		"title": "alchemical-exarch",
		"aura": &"aura_alchemical_sun",
		"fx": 6,
	},
	PRISM: {
		"label": "Prism",
		# Pale cyan: the white light, not one of the colours it splits into. Same
		# argument the Diamond rung makes - a prismatic thing reads as near-white
		# with colour thrown off it, never as a rainbow smear.
		"dye": VaultSkins.STYLE_AETHER,
		"accent_dye": VaultSkins.STYLE_ROSE,
		"title": "iridescent-aspect",
		"aura": &"aura_prismatic_shimmer",
		"fx": 7,
	},
}

## The dye styles [constant PRISM] walks, red round to magenta. Every entry is a
## real dye, so the rainbow is built from colours players can actually wear.
##
## Order is the spectrum, NOT [member VaultSkins.STYLE_ORDER] - a hue cycle that
## jumps around reads as a flicker rather than as a sweep.
const PRISM_CYCLE: PackedInt32Array = [
	VaultSkins.STYLE_CRIMSON,
	VaultSkins.STYLE_AMBER,
	VaultSkins.STYLE_GOLD,
	VaultSkins.STYLE_VERDANT,
	VaultSkins.STYLE_AETHER,
	VaultSkins.STYLE_SAPPHIRE,
	VaultSkins.STYLE_VOID,
	VaultSkins.STYLE_ROSE,
]


static func has(theme: StringName) -> bool:
	return THEMES.has(theme)


static func keys() -> Array[StringName]:
	return ORDER


static func label(theme: StringName) -> String:
	return str(_entry(theme).get("label", ""))


## The shader branch for this theme, or -1 when it is not a theme. Callers treat
## -1 the way [TitleVfx] treats a missing `fx`: not this family, fall through.
static func fx(theme: StringName) -> int:
	return int(_entry(theme).get("fx", -1))


## The [VaultSkins] style this theme takes its colour from, or 0.
static func dye_style(theme: StringName) -> int:
	return int(_entry(theme).get("dye", 0))


static func accent_style(theme: StringName) -> int:
	return int(_entry(theme).get("accent_dye", dye_style(theme)))


## THE colour. Read straight out of the dye table, so this and the body paint can
## never disagree.
static func core(theme: StringName) -> Color:
	return _dye_color(dye_style(theme))


static func accent(theme: StringName) -> Color:
	return _dye_color(accent_style(theme))


## Highlight. Bright enough to read as a light source on top of [method core].
static func pale(theme: StringName) -> Color:
	return core(theme).lightened(CORE_LIGHTEN)


## Shadow / ash / the outer edge of a bloom.
##
## NEVER give this to an additive layer. Additive blending of a dark colour adds
## nothing at all, so a smoke layer tinted with it costs frame time and draws
## exactly zero pixels - the same trap tools/verify_vip_titles.gd catches on the
## donation ladder.
static func deep(theme: StringName) -> Color:
	return core(theme).darkened(CORE_DARKEN)


## The one-colour answer, for a chat bracket or a roster row. Hex rather than
## Color because that is what [TitleCatalog] entries and BBCode both speak.
static func hex(theme: StringName) -> String:
	return "#" + core(theme).to_html(false)


## The PREMIUM title slug wearing this theme, or "".
static func title_slug(theme: StringName) -> String:
	return str(_entry(theme).get("title", ""))


## The [Cosmetics] slug of the matching aura, or &"".
static func aura_slug(theme: StringName) -> StringName:
	return StringName(str(_entry(theme).get("aura", "")))


## Reverse lookup: which theme owns this title slug. &"" for the ordinary premium
## titles, which is most of them.
static func for_title_slug(slug: String) -> StringName:
	for key: StringName in ORDER:
		if title_slug(key) == slug:
			return key
	return &""


## Reverse lookup by aura slug, for the shop and for the verifier.
static func for_aura_slug(slug: StringName) -> StringName:
	for key: StringName in ORDER:
		if aura_slug(key) == slug:
			return key
	return &""


## Every aura slug in the set, in [constant ORDER].
static func aura_slugs() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in ORDER:
		out.append(aura_slug(key))
	return out


## The prism's colour at [param k] (0..1 round the wheel), interpolated between
## neighbouring dyes so a sweep is smooth rather than eight hard steps.
static func prism_at(k: float) -> Color:
	var count: int = PRISM_CYCLE.size()
	if count == 0:
		return Color.WHITE
	var pos: float = fposmod(k, 1.0) * float(count)
	var i: int = int(pos) % count
	var j: int = (i + 1) % count
	return _dye_color(PRISM_CYCLE[i]).lerp(_dye_color(PRISM_CYCLE[j]), pos - floorf(pos))


## Every dye tint in [constant PRISM_CYCLE], for a layer that wants to hand one
## colour to each of its particles rather than walk a ramp.
static func prism_colors() -> Array[Color]:
	var out: Array[Color] = []
	for style: int in PRISM_CYCLE:
		out.append(_dye_color(style))
	return out


static func _entry(theme: StringName) -> Dictionary:
	return THEMES.get(theme, {})


## A dye's tint, straight from [VaultSkins]. Falls back to white rather than to
## black: an unknown style is a content bug, and a white effect is visible enough
## that somebody reports it.
static func _dye_color(style: int) -> Color:
	var meta: Dictionary = VaultSkins.STYLE_META.get(style, {})
	var tint: String = str(meta.get("tint", ""))
	return Color(tint) if not tint.is_empty() else Color.WHITE
