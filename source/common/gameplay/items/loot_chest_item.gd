class_name LootChestItem
extends Item
## Tradeable bag chest. Use/Open rolls the linked [ChestResource] loot table into
## the bag (same payout as a world [LootChest]). Spawn with /give using the
## chest slug (e.g. gold_pink_large).


## Filename slug under combat/chests/ (e.g. &"gold_pink_large").
@export var chest_slug: StringName = &""


func _init() -> void:
	holdable = false
	can_trade = true
	stack_limit = 0


func inventory_tab() -> InventoryTab:
	return InventoryTab.CONSUMABLE


func group_key() -> StringName:
	return &"chests"


func can_use(_character: Character) -> bool:
	return ChestResource.load_by_slug(chest_slug) != null


func sort_key() -> Array:
	var table: ChestResource = ChestResource.load_by_slug(chest_slug)
	var tier: int = table.tier if table != null else 99
	return [tier, String(item_name)]


func resolve_table() -> ChestResource:
	return ChestResource.load_by_slug(chest_slug)
