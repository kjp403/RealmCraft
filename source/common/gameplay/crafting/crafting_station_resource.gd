class_name CraftingStationResource
extends Resource
## Editor-authored crafting station. Assign one to a CraftingStation node's `station`
## field (inline, or a shared .tres dragged in). The server resolves the station from
## the player's map by the CraftingStation node's name, and the client renders the
## recipe list from the resource carried in the menu arg — no registry id needed.

@export var station_name: String = "Workbench"
## Which profession this station trains/uses — a skills key, e.g. &"smithing", &"cooking".
@export var profession: StringName = &"smithing"
## Flat gold fee charged per craft (0 = free). A small per-craft gold sink so
## crafted goods carry a natural price floor in player trade.
@export var craft_fee: int = 0
## True for a station that SMELTS BARS (the furnace). Smelting is the one craft
## with a run cap — [constant AnvilBoost.BASE_MAX_BARS] in a sitting, lifted to
## [constant AnvilBoost.BOOSTED_MAX_BARS] by an Anvil Stabilizer.
##
## Authored rather than sniffed from the profession or the output slug: the anvil
## is also &"smithing" and must NOT be capped, and matching output names against
## "_bar" would make the cap depend on how somebody names a future item.
@export var smelts_bars: bool = false
@export var recipes: Array[CraftingRecipe]
