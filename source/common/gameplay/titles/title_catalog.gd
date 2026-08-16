class_name TitleCatalog
## Every title that carries text VFX. Supporter (donation) titles stay in
## [SupporterTitles]; these PREMIUM names are the shop-candidate set — staff
## test them from the VFX Vault Titles shelf. Players cannot buy them yet.
##
## Lookups are by display name (and slug). Empty = no VFX (quest titles, etc.).

## style: 0 gem, 1 gold, 2 ember, 3 void, 4 star, 5 moon, 6 ink
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


## Donator titles first (the ones that must have VFX), then premium shop candidates.
static func vault_roster() -> Array:
	var out: Array = []
	for slug: String in SupporterTitles.ORDER:
		var entry: Dictionary = SupporterTitles.BY_SLUG[slug]
		var row: Dictionary = entry.duplicate()
		row["slug"] = slug
		out.append(row)
	out.append_array(premium_roster())
	return out


## Supporter first, then premium. Empty = no title VFX.
static func spec(title: String) -> Dictionary:
	var from_supporter: Dictionary = SupporterTitles.spec(title)
	if not from_supporter.is_empty():
		return from_supporter
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
