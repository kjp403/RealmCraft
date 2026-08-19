class_name AltarOfferingTable
extends Resource
## What the church altar accepts and what it pays. One table for the whole game,
## loaded by both sides: the server to run the offering authoritatively, the
## client only to render the altar menu's list.
##
## Same shape as [SalvageTable] on purpose — an offering is "consume one item,
## get skill xp", which is the salvage conversion with xp instead of materials.

const TABLE_PATH: String = "res://source/common/gameplay/prayer/resources/altar_offerings.tres"

## Skill the offerings pay into.
@export var profession: StringName = &"prayer"
@export var offerings: Array[AltarOffering] = []

static var _shared: AltarOfferingTable

var _by_id: Dictionary[int, AltarOffering] = {}
var _indexed: bool = false


static func shared() -> AltarOfferingTable:
	if _shared == null:
		_shared = load(TABLE_PATH) as AltarOfferingTable
	return _shared


## The offering for [param item_id], or null when the altar will not take it.
func offering_for(item_id: int) -> AltarOffering:
	if not _indexed:
		_index()
	return _by_id.get(item_id, null)


func _index() -> void:
	_indexed = true
	for offering: AltarOffering in offerings:
		if offering == null or offering.item == null:
			continue
		var id: int = int(offering.item.get_meta(&"id", 0))
		if id > 0:
			_by_id[id] = offering
