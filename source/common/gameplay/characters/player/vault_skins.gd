class_name VaultSkins
## Prestige recolors of every wearable sprite. These are NOT in Horizon and are
## NOT new `sprites` registry ids — each entry reuses a real skin_id and applies
## a client shader (hue / tint / pulse). Staff equip them from the VFX Vault
## Skins tab; everyone else cannot buy, browse, or keep one.

## style: 1 gold, 2 ember, 3 void, 4 star, 5 moon, 6 aether, 7 toxic
const STYLE_GOLD := 1
const STYLE_EMBER := 2
const STYLE_VOID := 3
const STYLE_STAR := 4
const STYLE_MOON := 5
const STYLE_AETHER := 6
const STYLE_TOXIC := 7

const STYLE_META: Dictionary = {
	STYLE_GOLD: {"label": "Gilded", "tint": "#e8c050"},
	STYLE_EMBER: {"label": "Ember", "tint": "#e07040"},
	STYLE_VOID: {"label": "Void", "tint": "#8a78b0"},
	STYLE_STAR: {"label": "Starforged", "tint": "#e8d090"},
	STYLE_MOON: {"label": "Moonlit", "tint": "#c8d4e8"},
	STYLE_AETHER: {"label": "Aether", "tint": "#88d0d8"},
	STYLE_TOXIC: {"label": "Toxic", "tint": "#7ed080"},
}

const GROUP_WARDROBE := &"wardrobe"
const GROUP_ARCHIVES := &"archives"


static func is_valid(skin_id: int) -> bool:
	return skin_id > 0 and PlayerSkins.is_valid(skin_id)


static func group_of(skin_id: int) -> StringName:
	var slug: String = _slug(skin_id)
	if slug.begins_with("trpg_"):
		return GROUP_ARCHIVES
	return GROUP_WARDROBE


static func style_of(skin_id: int) -> int:
	var slug: String = _slug(skin_id)
	if slug.begins_with("royal") or slug == "knight" or slug.begins_with("scholar"):
		return STYLE_GOLD
	if slug.begins_with("stone"):
		return STYLE_EMBER if slug.contains("lava") else STYLE_STAR
	if slug.begins_with("fungus"):
		return STYLE_TOXIC
	if slug.begins_with("skeleton") or slug.begins_with("rat"):
		return STYLE_VOID
	if slug.begins_with("orc") or slug == "goblin":
		return STYLE_EMBER
	if slug.begins_with("bandit") or slug == "rogue":
		return STYLE_MOON
	if slug == "wizard":
		return STYLE_AETHER
	if slug.contains("demon") or slug.contains("blood") or slug.contains("fire"):
		return STYLE_EMBER
	if slug.contains("were") or slug.contains("bat") or slug.contains("night"):
		return STYLE_MOON
	if slug.contains("slime") or slug.contains("ooze") or slug.contains("poison"):
		return STYLE_TOXIC
	if slug.contains("wizard") or slug.contains("mage") or slug.contains("priest"):
		return STYLE_AETHER
	if slug.contains("skeleton") or slug.contains("void") or slug.contains("necro"):
		return STYLE_VOID
	if slug.contains("knight") or slug.contains("gold"):
		return STYLE_GOLD
	return (absi(skin_id) % 7) + 1


static func tint_hex(skin_id: int) -> String:
	var meta: Dictionary = STYLE_META.get(style_of(skin_id), {})
	return str(meta.get("tint", "#e8c050"))


static func display_name(skin_id: int) -> String:
	var meta: Dictionary = STYLE_META.get(style_of(skin_id), {})
	var palette: String = str(meta.get("label", "Prestige"))
	var base: String = PlayerSkins.display_name(skin_id)
	if base.is_empty():
		return palette
	return "%s %s" % [palette, base]


static func blurb(skin_id: int) -> String:
	match style_of(skin_id):
		STYLE_GOLD:
			return "Warm gold wash and a slow shine through the pixels."
		STYLE_EMBER:
			return "Copper-ember recolor. Looks like it walked out of a forge."
		STYLE_VOID:
			return "Violet shadow. The silhouette reads first, then the color."
		STYLE_STAR:
			return "Pale gold sparkle across the sprite — still the same cut."
		STYLE_MOON:
			return "Cool silver. Quiet on purpose."
		STYLE_AETHER:
			return "Teal arcane shift. Not a gem-supporter clone."
		STYLE_TOXIC:
			return "Sickly green pulse. Fungus and venom wear it well."
		_:
			return "Vault-only prestige recolor. Horizon cannot sell this."


static func roster(group: StringName = &"") -> Array:
	var out: Array = []
	for id: int in PlayerSkins.ids():
		if group != &"" and group_of(id) != group:
			continue
		out.append({
			"id": id,
			"name": display_name(id),
			"style": style_of(id),
			"tint": tint_hex(id),
			"group": String(group_of(id)),
			"blurb": blurb(id),
		})
	return out


static func _slug(skin_id: int) -> String:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"sprites")
	if registry == null:
		return ""
	return String(registry.slug_from_id(skin_id))
