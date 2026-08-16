class_name PlayerSkins
## Thin facade over the `sprites` ContentRegistry: every sprite is a wearable player skin.
## Character creation (gateway), the wardrobe, and the server's buy/equip validation all go
## through here so they agree on the roster + display names WITHOUT a hardcoded list — drop a
## SpriteFrames into the sprite_frames folder, reindex, and it's offered everywhere at once.
##
## Horizon's wardrobe charges gold for cosmetics; [method price] is the single source of
## truth for those fees. Knight is the free starter and is never sold.


const STARTER_SKIN_SLUG: StringName = &"knight"

## Horizon wardrobe prices (gold). Slugs absent here (or priced 0) are not for sale —
## the free starter Knight, and any future exclusive-only skins.
const PRICES_BY_SLUG: Dictionary[StringName, int] = {
	&"rogue": 2500,
	&"wizard": 2500,
	&"goblin": 5000,
	&"skeleton": 5000,
	&"bandit_fighter": 7500,
	&"bandit_scout": 7500,
	&"bandit_sorcerer": 7500,
	&"bandit_tracker": 7500,
	&"orc": 15000,
	&"orc_rogue": 15000,
	&"orc_shaman": 15000,
	&"orc_warrior": 15000,
	&"skeleton_mage": 25000,
	&"skeleton_rogue": 25000,
	&"skeleton_warrior": 25000,
	&"stone_base": 30000,
	&"stone_broken": 30000,
	&"stone_golem": 50000,
	&"stone_lava": 50000,
	&"royal_archer": 100000,
	&"royal_knight": 100000,
	&"royal_priest": 100000,
	&"royal_soldier": 100000,
	&"rat_base": 200000,
	&"rat_mage": 200000,
	&"rat_rogue": 200000,
	&"rat_warrior": 200000,
	&"scholar_cataloguer": 250000,
	&"scholar_censor": 250000,
	&"scholar_director": 250000,
	&"scholar_researcher": 250000,
	&"fungus_heavy": 350000,
	&"fungus_immature": 350000,
	&"fungus_long": 350000,
	&"fungus_old": 350000,
}


## All skin ids, sorted ascending (so the original starters lead) — every entry in the
## `sprites` registry. Used by the wardrobe + character creation to list buyable skins.
static func ids() -> Array[int]:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"sprites")
	if registry == null:
		return []
	var out: Array[int] = registry.all_ids()
	out.sort()
	return out


## True when [param skin_id] resolves to a real sprite. Server-side anti-cheat: stops a
## client buying/equipping an id that doesn't exist in the registry.
static func is_valid(skin_id: int) -> bool:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"sprites")
	return registry != null and registry.has_id(skin_id)


## Readable display name for a skin id, from its file slug ("royal_guard" -> "Royal Guard");
## empty string if the id isn't in the registry.
static func display_name(skin_id: int) -> String:
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"sprites")
	if registry == null:
		return ""
	return String(registry.slug_from_id(skin_id)).capitalize()


## Registry id for the free starter skin (Knight). Falls back to 1 if the slug is missing.
static func starter_skin_id() -> int:
	var id: int = ContentRegistryHub.id_from_slug(&"sprites", STARTER_SKIN_SLUG)
	return id if id > 0 else 1


## Gold cost to unlock [param skin_id] at Horizon. 0 = not for sale (starter / exclusive).
static func price(skin_id: int) -> int:
	if not is_valid(skin_id):
		return 0
	var registry: ContentRegistry = ContentRegistryHub.registry_of(&"sprites")
	if registry == null:
		return 0
	var slug: StringName = registry.slug_from_id(skin_id)
	if slug == STARTER_SKIN_SLUG:
		return 0
	return int(PRICES_BY_SLUG.get(slug, 0))


## True when Horizon will sell this skin for gold.
static func is_for_sale(skin_id: int) -> bool:
	return price(skin_id) > 0


## True when Horizon's wardrobe should list this skin (starter or priced).
## Prestige recolors are the same ids with a vault shader — they are NOT extra
## roster entries, and trpg archives stay in the Vault Skins tab only.
static func is_horizon_listed(skin_id: int) -> bool:
	return skin_id == starter_skin_id() or is_for_sale(skin_id)
