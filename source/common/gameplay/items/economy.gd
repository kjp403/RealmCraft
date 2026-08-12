class_name Economy
## Currency helpers. Gold (and other currencies) are normal items flagged
## `is_currency`; the player's balance is the amount held in inventory. The default
## currency is the item with slug "gold" — create it in the editor and reindex items.
##
## Slayer Points are the exception: the item exists so shops can reference a
## currency_item / icon, but the balance lives on [member PlayerResource.slayer_points]
## (not inventory). Shop buy/open handlers special-case [method is_slayer_points_id].


const GOLD_SLUG: StringName = &"gold"
const SLAYER_POINTS_SLUG: StringName = &"slayer_points"


## Registry id of the default currency (gold), or 0 if it hasn't been authored yet.
static func gold_id() -> int:
	if ContentRegistryHub.registry_of(&"items") == null:
		return 0
	return ContentRegistryHub.id_from_slug(&"items", GOLD_SLUG)


## Registry id of the Slayer Points currency item, or 0 if not indexed yet.
static func slayer_points_id() -> int:
	if ContentRegistryHub.registry_of(&"items") == null:
		return 0
	return ContentRegistryHub.id_from_slug(&"items", SLAYER_POINTS_SLUG)


static func is_slayer_points_id(currency_id: int) -> bool:
	var sid: int = slayer_points_id()
	return sid > 0 and currency_id == sid
