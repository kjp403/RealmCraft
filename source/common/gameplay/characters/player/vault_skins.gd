class_name VaultSkins
## Prestige palette-swaps of every Horizon wardrobe skin. Packed id is
## `style * STRIDE + skin_id` so every wardrobe body has every dye, and Wear
## can persist which dye you picked. Faces / leather / outlines stay; armor
## and cloth take the ramp. Staff-only Vault Skins tab. Never sold at Horizon.

const STRIDE := 10000

const STYLE_GOLD := 1
const STYLE_EMBER := 2
const STYLE_VOID := 3
const STYLE_STAR := 4
const STYLE_MOON := 5
const STYLE_AETHER := 6
const STYLE_TOXIC := 7
const STYLE_CRIMSON := 8
const STYLE_FROST := 9
const STYLE_VERDANT := 10
const STYLE_SAPPHIRE := 11
const STYLE_ROSE := 12
const STYLE_OBSIDIAN := 13
const STYLE_COPPER := 14
const STYLE_GHOST := 15
const STYLE_AMBER := 16

const STYLE_ORDER: PackedInt32Array = [
	STYLE_GOLD, STYLE_EMBER, STYLE_VOID, STYLE_STAR,
	STYLE_MOON, STYLE_AETHER, STYLE_TOXIC, STYLE_CRIMSON,
	STYLE_FROST, STYLE_VERDANT, STYLE_SAPPHIRE, STYLE_ROSE,
	STYLE_OBSIDIAN, STYLE_COPPER, STYLE_GHOST, STYLE_AMBER,
]

const STYLE_META: Dictionary = {
	STYLE_GOLD: {
		"label": "Gilded", "tint": "#f0c84a",
		"blurb": "Gold plate. Leather, visor, and face stay.",
	},
	STYLE_EMBER: {
		"label": "Ember", "tint": "#ff6a28",
		"blurb": "Ash and coals. Tusks and leather stay put.",
	},
	STYLE_VOID: {
		"label": "Void", "tint": "#9a78ff",
		"blurb": "Night-violet cloth. Bone and eyes don't get painted.",
	},
	STYLE_STAR: {
		"label": "Starforged", "tint": "#ffe89a",
		"blurb": "Navy in the shadows, gold in the lights.",
	},
	STYLE_MOON: {
		"label": "Moonlit", "tint": "#c8dcff",
		"blurb": "Night-blue cloth. Collar and eyes keep their color.",
	},
	STYLE_AETHER: {
		"label": "Aether", "tint": "#5ce8f0",
		"blurb": "Teal robes. Beard and face stay readable.",
	},
	STYLE_TOXIC: {
		"label": "Toxic", "tint": "#6cff6a",
		"blurb": "Sick-green. Cloth and bone keep their own palette.",
	},
	STYLE_CRIMSON: {
		"label": "Crimson", "tint": "#e03040",
		"blurb": "Blood-red cloth. Not lava — a banner dye.",
	},
	STYLE_FROST: {
		"label": "Frost", "tint": "#d8f4ff",
		"blurb": "Ice-white plate. Colder and brighter than Moonlit.",
	},
	STYLE_VERDANT: {
		"label": "Verdant", "tint": "#3cb86a",
		"blurb": "Forest green cloth. Leather stays brown.",
	},
	STYLE_SAPPHIRE: {
		"label": "Sapphire", "tint": "#3a78ff",
		"blurb": "Royal blue. Saturated, not the night-grey Moonlit.",
	},
	STYLE_ROSE: {
		"label": "Rose", "tint": "#ff7ab0",
		"blurb": "Pink silk. Face and leather stay.",
	},
	STYLE_OBSIDIAN: {
		"label": "Obsidian", "tint": "#6a6a78",
		"blurb": "Near-black cloth, silver in the lights.",
	},
	STYLE_COPPER: {
		"label": "Copper", "tint": "#d07838",
		"blurb": "Warm copper plate. Distinct from Gilded gold.",
	},
	STYLE_GHOST: {
		"label": "Ghost", "tint": "#d0d4dc",
		"blurb": "Washed pale grey. Eyes and outlines stay.",
	},
	STYLE_AMBER: {
		"label": "Amber", "tint": "#ffb040",
		"blurb": "Sunset orange. Warmer than Copper, not Ember coals.",
	},
}


static func pack(skin_id: int, style: int) -> int:
	if skin_id <= 0 or not _is_style(style):
		return 0
	return style * STRIDE + skin_id


static func base_skin_id(vault_id: int) -> int:
	if vault_id <= 0:
		return 0
	if vault_id < STRIDE:
		return vault_id
	return vault_id % STRIDE


static func style_of(vault_id: int) -> int:
	if vault_id <= 0:
		return 0
	if vault_id < STRIDE:
		return STYLE_GOLD
	var style: int = vault_id / STRIDE
	return style if _is_style(style) else 0


static func is_valid(vault_id: int) -> bool:
	if vault_id <= 0:
		return false
	var skin_id: int = base_skin_id(vault_id)
	var style: int = style_of(vault_id)
	if not PlayerSkins.is_horizon_listed(skin_id):
		return false
	if vault_id < STRIDE:
		return true
	return _is_style(style)


static func tint_hex(vault_id: int) -> String:
	var meta: Dictionary = STYLE_META.get(style_of(vault_id), {})
	return str(meta.get("tint", "#f0c84a"))


static func display_name(vault_id: int) -> String:
	var meta: Dictionary = STYLE_META.get(style_of(vault_id), {})
	var palette: String = str(meta.get("label", "Prestige"))
	var base: String = PlayerSkins.display_name(base_skin_id(vault_id))
	if base.is_empty():
		return palette
	return "%s %s" % [palette, base]


static func keeps_flesh(vault_id: int) -> bool:
	var slug: String = _slug(base_skin_id(vault_id))
	if slug.begins_with("goblin") or slug.begins_with("orc"):
		return false
	if slug.begins_with("skeleton") or slug.begins_with("rat"):
		return false
	if slug.begins_with("fungus") or slug.begins_with("stone"):
		return false
	return PlayerSkins.is_horizon_listed(base_skin_id(vault_id))


static func blurb(vault_id: int) -> String:
	var meta: Dictionary = STYLE_META.get(style_of(vault_id), {})
	return str(meta.get("blurb", "Vault palette-swap."))


static func dye_roster() -> Array:
	var out: Array = []
	for style: int in STYLE_ORDER:
		var meta: Dictionary = STYLE_META[style]
		out.append({
			"style": style,
			"label": str(meta.get("label", "")),
			"tint": str(meta.get("tint", "")),
			"blurb": str(meta.get("blurb", "")),
		})
	return out


static func base_roster() -> Array:
	var out: Array = []
	for id: int in PlayerSkins.ids():
		if not PlayerSkins.is_horizon_listed(id):
			continue
		out.append({
			"id": id,
			"name": PlayerSkins.display_name(id),
		})
	return out


static func roster(_group: StringName = &"") -> Array:
	var out: Array = []
	for base: Dictionary in base_roster():
		var skin_id: int = int(base.get("id", 0))
		for style: int in STYLE_ORDER:
			var vault_id: int = pack(skin_id, style)
			out.append({
				"id": vault_id,
				"skin_id": skin_id,
				"style": style,
				"name": display_name(vault_id),
				"tint": tint_hex(vault_id),
				"blurb": blurb(vault_id),
			})
	return out


static func _is_style(style: int) -> bool:
	return STYLE_META.has(style)


static func _slug(skin_id: int) -> String:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"sprites")
	if registry == null:
		return ""
	return String(registry.slug_from_id(skin_id))
