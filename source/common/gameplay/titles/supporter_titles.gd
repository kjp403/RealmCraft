class_name SupporterTitles
## Canonical donation titles. Grant with /supporter; the player can display one
## under their name and pin extras as profile trophies. Coloring looks up the
## display name, so /title with the same string matches.

const COLOR_SAPPHIRE := "#7ec0ff"
const COLOR_EMERALD := "#5ee0a0"
const COLOR_RUBY := "#f08a8a"
const COLOR_CUSTOM := "#e8c56a"

## slug → { name, color, vip }. Slugs are what /supporter accepts.
## vip = stronger title-text VFX (shine + pulse). Never a character aura/halo.
const BY_SLUG: Dictionary = {
	"sapphire": {"name": "Sapphire Supporter", "color": COLOR_SAPPHIRE, "vip": false},
	"emerald": {"name": "Emerald Supporter", "color": COLOR_EMERALD, "vip": false},
	"ruby": {"name": "Ruby Supporter", "color": COLOR_RUBY, "vip": false},
	"sapphire-vip": {"name": "Sapphire VIP", "color": COLOR_SAPPHIRE, "vip": true},
	"emerald-vip": {"name": "Emerald VIP", "color": COLOR_EMERALD, "vip": true},
	"ruby-vip": {"name": "Ruby VIP", "color": COLOR_RUBY, "vip": true},
	"custom": {"name": "Arkenelle Supporter", "color": COLOR_CUSTOM, "vip": false},
}

const ALIASES: Dictionary = {
	"sap": "sapphire",
	"s": "sapphire",
	"eme": "emerald",
	"e": "emerald",
	"r": "ruby",
	"sapphire_vip": "sapphire-vip",
	"sapphirevip": "sapphire-vip",
	"svip": "sapphire-vip",
	"emerald_vip": "emerald-vip",
	"emeraldvip": "emerald-vip",
	"evip": "emerald-vip",
	"ruby_vip": "ruby-vip",
	"rubyvip": "ruby-vip",
	"rvip": "ruby-vip",
	"any": "custom",
	"supporter": "custom",
	"arkenelle": "custom",
}


const ORDER: PackedStringArray = [
	"sapphire",
	"emerald",
	"ruby",
	"custom",
	"sapphire-vip",
	"emerald-vip",
	"ruby-vip",
]


static func slugs() -> PackedStringArray:
	return ORDER


static func resolve(token: String) -> Dictionary:
	var key: String = token.strip_edges().to_lower().replace(" ", "-")
	if ALIASES.has(key):
		key = str(ALIASES[key])
	if BY_SLUG.has(key):
		return BY_SLUG[key]
	for slug: String in BY_SLUG:
		var entry: Dictionary = BY_SLUG[slug]
		if str(entry.get("name", "")).to_lower() == token.strip_edges().to_lower():
			return entry
	return {}


static func display_name(token: String) -> String:
	return str(resolve(token).get("name", ""))


static func spec(title: String) -> Dictionary:
	return resolve(title)


static func color_hex(title: String) -> String:
	return str(spec(title).get("color", ""))


static func is_vip(title: String) -> bool:
	return bool(spec(title).get("vip", false))


static func has_vfx(title: String) -> bool:
	return not spec(title).is_empty()


static func usage_tiers() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for slug: String in slugs():
		lines.append("%s = %s" % [slug, str(BY_SLUG[slug].get("name", slug))])
	return "\n".join(lines)
