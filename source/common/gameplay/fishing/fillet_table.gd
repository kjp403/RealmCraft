class_name FilletTable
extends Resource
## What each raw fish cuts into. ONE table for the whole game, exactly like
## [SalvageTable] and for the same reason: filleting is a bag action the player can
## do anywhere, so there is no station to hang recipes off.
##
## Both sides load it — the server to run the conversion authoritatively, the client
## only to preview yields in the Fillet panel — so it lives in `common/`.
##
## MEMBERSHIP IS A TAG, TUNING IS THIS TABLE
## Whether an item is filletable at all is decided by [constant RAW_FISH_TAG] in
## [member Item.tags], not by having a row here. A new fish added to
## items/materials/fish/ is therefore filletable the day it ships, at
## [member default_yield], instead of being silently un-filletable until someone
## remembers to add a row. Rows here only override the yield.

const TABLE_PATH: String = "res://source/common/gameplay/fishing/resources/fillet_table.tres"

## The [member Item.tags] entry that marks an item as raw fish. This is the
## project's existing free-form tag array — the spec's `is_raw_fish` bool would be a
## second, parallel way to say the same thing, and the two would drift.
const RAW_FISH_TAG: StringName = &"raw_fish"

## Bait per fish for anything without a row of its own — which today is every
## fish, deliberately.
##
## WHY THIS IS FLAT AND NOT A LADDER
## A yield that scales with fish tier looks right and is backwards. Sustaining a
## combo costs one bait per catch, so the share of the catch you must fillet is
## ~1/yield: at yield 1 that is ~96% of everything you pull, at yield 12 it is
## ~8%. The feature would be unusable at Fishing 1 and free by Fishing 90 —
## exactly inverted from "reachable from the get-go". Flat 2 means you fillet
## about half your catch at EVERY tier, which is one rule a player can hold in
## their head, and it keeps the Bottomless Bucket worth carrying forever: bank
## the surplus off small nodes, burn it on a 50-pool.
##
## To make one prized fish worth more, add a [FilletRecipe] row rather than
## re-introducing a curve.
@export var default_yield: int = 2

@export var recipes: Array[FilletRecipe] = []

static var _shared: FilletTable

## Lazily built item_id -> yield map. Item ids are stamped onto resources by the
## content index, not by the .tres, so this cannot be built at load time.
var _by_id: Dictionary[int, int] = {}
var _indexed: bool = false


## The one shared table instance. Cached — the panel re-asks per fish per redraw.
static func shared() -> FilletTable:
	if _shared == null:
		_shared = load(TABLE_PATH) as FilletTable
	return _shared


## Bait produced by filleting one [param item]. Returns 0 for anything not tagged
## raw fish, which is what makes the tag the authority rather than this table.
func yield_for(item: Item) -> int:
	if item == null or not is_raw_fish(item):
		return 0
	if not _indexed:
		_index()
	var id: int = int(item.get_meta(&"id", 0))
	return maxi(0, _by_id.get(id, default_yield))


## True when [param item] is raw fish. The single place that question is answered,
## so the panel, the server conversion and any future cook/bait path cannot disagree
## about what counts.
static func is_raw_fish(item: Item) -> bool:
	return item != null and item.tags.has(String(RAW_FISH_TAG))


func _index() -> void:
	_indexed = true
	for recipe: FilletRecipe in recipes:
		if recipe == null or recipe.source_item == null:
			continue
		var id: int = int(recipe.source_item.get_meta(&"id", 0))
		if id > 0:
			_by_id[id] = maxi(0, recipe.bait_yield)
