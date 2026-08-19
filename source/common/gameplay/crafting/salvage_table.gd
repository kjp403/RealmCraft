class_name SalvageTable
extends Resource
## The single authored list of what breaking an item down yields. ONE table for
## the whole game (not per-station) — breaking down is a bag action the player
## can do anywhere, so there is no station to hang recipes off.
##
## Both sides load it: the server to run the conversion authoritatively, the
## client only to decide whether to offer the "Break Down" button. Keep it in
## `common/` for exactly that reason.

const TABLE_PATH: String = "res://source/common/gameplay/crafting/resources/salvage_table.tres"

## Skill that gates and is paid by breaking down. Salvage feeds the same job
## that consumes the yield, so the whole loop levels one skill.
@export var profession: StringName = &"herblore"
@export var recipes: Array[SalvageRecipe]

static var _shared: SalvageTable

## Lazily built item_id -> recipe map. Item ids are only stamped onto the
## resources by the content index, so this cannot be built at load time.
var _by_id: Dictionary[int, SalvageRecipe] = {}
var _indexed: bool = false


## The one shared table instance. Cached — the bag re-asks on every selection.
static func shared() -> SalvageTable:
	if _shared == null:
		_shared = load(TABLE_PATH) as SalvageTable
	return _shared


## The recipe for [param item_id], or null when that item cannot be broken down.
func recipe_for(item_id: int) -> SalvageRecipe:
	if not _indexed:
		_index()
	return _by_id.get(item_id, null)


func _index() -> void:
	_indexed = true
	for recipe: SalvageRecipe in recipes:
		if recipe == null or recipe.source_item == null:
			continue
		var id: int = int(recipe.source_item.get_meta(&"id", 0))
		if id > 0:
			_by_id[id] = recipe
