class_name DungeonKeyItem
extends Item
## Restores one daily dungeon reward charge when Used from the bag.
## Dropped rarely by world bosses. Tradeable so players can sell extras.


func _init() -> void:
	holdable = false
	can_trade = true
	stack_limit = 0


func inventory_tab() -> InventoryTab:
	return InventoryTab.CONSUMABLE


func group_key() -> StringName:
	return &"keys"


func can_use(_character: Character) -> bool:
	return true


func sort_key() -> Array:
	return [String(item_name)]
