class_name DropRarityIndex
extends Resource
## How hard each item is to actually GET, as a drop chance — the number loot
## beams are tiered on.
##
## Rarity cannot be read off an item: an item has no drop rate, every LootDrop
## that references it does. So this is a generated lookup, built by
## tools/build_drop_rarity_index.gd from every enemy loot table in the game and
## committed alongside the content indexes.
##
## The stored value is the BEST (highest) chance across all sources, because that
## is what decides how hard something is to obtain. A relic that drops at 0.1%
## from one boss is rare; an item that drops at 0.1% from one boss and 40% from a
## rat is not, and only the 40% matters.
##
## Items with no drop source at all are simply absent — they are crafted or
## bought, so "drop rarity" has no meaning for them and they raise no beam.

## item id -> best drop chance (0..1).
@export var best_chance: Dictionary = {}
## Unix time the index was generated, for staleness reporting.
@export var generated_at: int = 0
## How many enemy loot tables were scanned to build it.
@export var sources_scanned: int = 0

## NOT under registry/indexes/ — ContentRegistryHub loads every file in that
## folder as a ContentIndex, and a typed-assignment failure there aborts the
## whole bootstrap loop, taking the item registry down with it.
const PATH: String = "res://source/common/registry/drop_rarity_index.tres"

static var _cached: DropRarityIndex = null


## Loads once and keeps it — every ground drop asks this, so it must not hit disk
## per pile.
static func get_index() -> DropRarityIndex:
	if _cached == null and ResourceLoader.exists(PATH):
		_cached = load(PATH) as DropRarityIndex
	return _cached


## Best drop chance for [param item_id], or 0.0 when nothing drops it.
static func chance_for(item_id: int) -> float:
	var idx: DropRarityIndex = get_index()
	if idx == null:
		return 0.0
	return float(idx.best_chance.get(item_id, 0.0))
