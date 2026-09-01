class_name PeddlerGoodItem
extends Item
## A good bought from the Traveling Peddler, sitting in the bag.
##
## The bag half of a [PeddlerItemData]: that resource is the SHOP row (tier,
## price, blurb), this is the object the purchase actually hands over. They are
## paired by slug — [member Item] metadata/slug here equals
## [member PeddlerItemData.id] there — so there is no mapping table between them
## to drift, which is the same reasoning behind [method NPCResource.giver_key].
##
## NOT TRADEABLE, deliberately. The stock is capped at one of each per account
## per day; a good that could be handed to another character would make that cap
## a cap on ALTS rather than on players, and the whole daily-limit design would
## be doing nothing. Revisit this only alongside the limit itself.

## True when this good DOES something on use ([code]peddler.use[/code] routes it
## to the stock row's action_script). False for goods that are unlocks or
## trophies, which sit in the bag and are refused by name if used.
##
## Authored rather than derived from whether the catalog row has an action_script:
## the bag dock has to decide whether to draw a "Use" row BEFORE any server call,
## and reaching into the peddler catalog from the inventory UI to find out would
## couple the two for one boolean.
@export var usable: bool = false


func _init() -> void:
	# Item defaults can_trade to false already; stated here so the reasoning in
	# the class note is anchored to code that would have to change with it.
	can_trade = false


## Usable goods live with the potions; the rest fall to the materials tab. Bag
## tabs are about "where would I look for this", and a permit is not a drink.
func inventory_tab() -> InventoryTab:
	return InventoryTab.CONSUMABLE if usable else InventoryTab.OTHER


func group_key() -> StringName:
	return &"peddler"


## The catalog row this good came from, or null if it is no longer stocked.
## Retired stock keeps working in the bag — the row is only needed for the
## use action and the shop.
func stock_row() -> PeddlerItemData:
	return PeddlerCatalog.find(String(get_meta(&"slug", &"")))


func stat_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	if usable:
		lines.append({"text": "Right-click to use", "kind": &"charges"})
	return lines
