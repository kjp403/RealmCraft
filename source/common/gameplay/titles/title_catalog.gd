class_name TitleCatalog
## Every title that carries text VFX. Supporter (donation) titles stay in
## [SupporterTitles]; these PREMIUM names are the shop-candidate set — staff
## test them from the VFX Vault Titles shelf. Players cannot buy them yet.
##
## Lookups are by display name (and slug). Empty = no VFX (quest titles, etc.).

## style: 0 gem, 1 gold, 2 ember, 3 void, 4 star, 5 moon, 6 ink
##
## A `vip_tier` key marks one of the four DONATION LADDER rungs and switches the
## whole render path: vip_title.gdshader plus a [VipTitleEffect] emitter stack
## loaded from the [VipTierProfile] of that name, instead of the `style` branch in
## title_vfx.gdshader. Those four sit in PREMIUM rather than in [SupporterTitles]
## deliberately, and the difference is not cosmetic:
##
##   * PREMIUM is what [CommandPermissions.strip_unreleased_vfx] deletes from
##     every non-staff player on each instance spawn. That is the GATE. Nothing
##     short of staff rank can wear one for longer than a zone change, however it
##     got onto the account.
##   * /supporter only accepts [SupporterTitles] slugs, so the ladder has no grant
##     path at all - not even a senior_admin one. Staff test from the Vault shelf.
##
## In other words the ladder is built and previewable and NOT sellable yet, which
## is the same footing as every other premium name here. Moving a rung out of this
## table is the deliberate act that puts it on sale; tools/verify_vip_titles.gd
## fails if one drifts out on its own.
const PREMIUM: Dictionary = {
	"gilded": {
		"name": "Gilded",
		"color": "#d4b45a",
		"style": 1,
		"vip": false,
		"blurb": "Quiet gold. The first thing people notice is that they noticed.",
	},
	"moonlit": {
		"name": "Moonlit",
		"color": "#c8d4e8",
		"style": 5,
		"vip": false,
		"blurb": "Cool silver. Barely a glow — it reads as taste, not a purchase.",
	},
	"oathbound": {
		"name": "Oathbound",
		"color": "#b8c0c8",
		"style": 5,
		"vip": false,
		"blurb": "Steel-grey. A vow, not a costume.",
	},
	"first-light": {
		"name": "First Light",
		"color": "#efe6c8",
		"style": 1,
		"vip": false,
		"blurb": "Dawn cream. Almost no shine. The expensive kind of quiet.",
	},
	"nightbloom": {
		"name": "Nightbloom",
		"color": "#b090d0",
		"style": 3,
		"vip": false,
		"blurb": "Deep violet. A slow bloom, not a neon sign.",
	},
	"ashen-crown": {
		"name": "Ashen Crown",
		"color": "#d09060",
		"style": 2,
		"vip": false,
		"blurb": "Copper smolder. Looks like it survived a fire.",
	},
	"starforged": {
		"name": "Starforged",
		"color": "#e8d090",
		"style": 4,
		"vip": true,
		"blurb": "Pale gold with a star-glint through the letters.",
	},
	"cinderborn": {
		"name": "Cinderborn",
		"color": "#e07040",
		"style": 2,
		"vip": false,
		"blurb": "Live ember. Warm, never loud.",
	},
	"aetherbound": {
		"name": "Aetherbound",
		"color": "#88d0d8",
		"style": 6,
		"vip": false,
		"blurb": "Pale teal. Arcane without looking like a gem supporter.",
	},
	"sovereign": {
		"name": "Sovereign",
		"color": "#e8c050",
		"style": 1,
		"vip": true,
		"blurb": "The flex. Rich gold, still a title — never an aura.",
	},
	"voidtouched": {
		"name": "Voidtouched",
		"color": "#8a78b0",
		"style": 3,
		"vip": true,
		"blurb": "Violet on near-black. People lean in to read it.",
	},
	"eclipse": {
		"name": "Eclipse",
		"color": "#9aa4b0",
		"style": 5,
		"vip": true,
		"blurb": "Dark silver. A rare, slow flash — then it's just a name again.",
	},
	"wyrmblood": {
		"name": "Wyrmblood",
		"color": "#c05048",
		"style": 2,
		"vip": true,
		"blurb": "Deep crimson. Not the Ruby donor pink — older, meaner.",
	},
	# THE DONATION LADDER, low rung to high. Read against each other rather than
	# on their own - a donor stepping up has to SEE the step - so these four are
	# meant to be tuned as a set, in source/common/gameplay/titles/profiles/.
	"silver-contributor": {
		"name": "Silver Contributor",
		"color": "#a9a29b",
		"style": 5,
		"vip": false,
		"vip_tier": &"silver",
		"blurb": "Tarnished silver over crimson smoke. Something is standing behind it.",
	},
	"golden-contributor": {
		"name": "Golden Contributor",
		"color": "#f0c65a",
		"style": 1,
		"vip": false,
		"vip_tier": &"golden",
		"blurb": "Warm gold with leaf drifting up off the letters.",
	},
	"platinum-contributor": {
		"name": "Platinum Contributor",
		"color": "#93b8ff",
		"style": 0,
		"vip": true,
		"vip_tier": &"platinum",
		"blurb": "Cold white metal, arcing. You hear it before you read it.",
	},
	"diamond-donator": {
		"name": "Diamond Donator",
		"color": "#bfe9ff",
		"style": 0,
		"vip": true,
		"vip_tier": &"diamond",
		"blurb": "Cut stone in a drifting field of diamond dust. The top of the ladder.",
	},
}

const ORDER: PackedStringArray = [
	"gilded",
	"moonlit",
	"oathbound",
	"first-light",
	"nightbloom",
	"ashen-crown",
	"starforged",
	"cinderborn",
	"aetherbound",
	"sovereign",
	"voidtouched",
	"eclipse",
	"wyrmblood",
	"silver-contributor",
	"golden-contributor",
	"platinum-contributor",
	"diamond-donator",
]


static func premium_slugs() -> PackedStringArray:
	return ORDER


static func premium_entry(slug: String) -> Dictionary:
	return PREMIUM.get(slug, {})


## Display-name list for the Vault UI, in ORDER.
static func premium_roster() -> Array:
	var out: Array = []
	for slug: String in ORDER:
		var entry: Dictionary = PREMIUM[slug]
		var row: Dictionary = entry.duplicate()
		row["slug"] = slug
		out.append(row)
	return out


## Donator titles first (the ones that must have VFX), then the earned level-99
## mastery set, then premium shop candidates.
static func vault_roster() -> Array:
	var out: Array = []
	for slug: String in SupporterTitles.ORDER:
		var entry: Dictionary = SupporterTitles.BY_SLUG[slug]
		var row: Dictionary = entry.duplicate()
		row["slug"] = slug
		out.append(row)
	out.append_array(SkillMasterTitles.roster())
	out.append_array(premium_roster())
	return out


## Supporter, then earned mastery, then premium. Empty = no title VFX.
##
## Mastery titles resolve HERE but are deliberately absent from PREMIUM, so
## is_premium_name() stays false for them and strip_unreleased_vfx never deletes
## a title somebody ground to 99 for. See SkillMasterTitleService.
static func spec(title: String) -> Dictionary:
	var from_supporter: Dictionary = SupporterTitles.spec(title)
	if not from_supporter.is_empty():
		return from_supporter
	var from_mastery: Dictionary = SkillMasterTitles.spec(title)
	if not from_mastery.is_empty():
		return from_mastery
	var needle: String = title.strip_edges()
	if needle.is_empty():
		return {}
	var key: String = needle.to_lower().replace(" ", "-")
	if PREMIUM.has(key):
		return PREMIUM[key]
	for slug: String in PREMIUM:
		var entry: Dictionary = PREMIUM[slug]
		if str(entry.get("name", "")).to_lower() == needle.to_lower():
			return entry
	return {}


static func color_hex(title: String) -> String:
	return str(spec(title).get("color", ""))


static func is_vip(title: String) -> bool:
	return bool(spec(title).get("vip", false))


## The [VipTierProfile] key for a title, or &"" when it is not one of the four
## donation-ladder rungs. The single call the VFX pipeline branches on - see
## [TitleVfx] - so nothing downstream has to know which title family a name came
## from.
static func vip_tier(title: String) -> StringName:
	return StringName(str(spec(title).get("vip_tier", "")))


## The four ladder slugs, low rung to high, in [constant ORDER]. Derived rather
## than typed a second time so the ladder cannot end up listed in two places that
## disagree about its membership or its order.
static func vip_tier_slugs() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for slug: String in ORDER:
		if not str((PREMIUM[slug] as Dictionary).get("vip_tier", "")).is_empty():
			out.append(slug)
	return out


static func has_vfx(title: String) -> bool:
	return not spec(title).is_empty()


static func is_premium_name(title: String) -> bool:
	var needle: String = title.strip_edges().to_lower()
	if needle.is_empty():
		return false
	for slug: String in PREMIUM:
		if slug == needle:
			return true
		if str(PREMIUM[slug].get("name", "")).to_lower() == needle:
			return true
	return false


static func canonical_name(title: String) -> String:
	return str(spec(title).get("name", title.strip_edges()))
