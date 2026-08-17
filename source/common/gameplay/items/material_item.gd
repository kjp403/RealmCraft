class_name MaterialItem
extends Item
# Pure data item for crafting; no runtime hooks needed (not yet?).
# Keep recipes & crafting logic elsewhere.


func _init() -> void:
	# Resources are bag cargo — never drawn into the hand. Right-click is Drop.
	holdable = false
	# Gathered / crafted mats (ores, logs, raw fish, cloth, herbs, gems) are
	# player-tradeable. Item.can_trade defaults false; .tres files that omit
	# the field inherit this. QuestItem still forces false.
	can_trade = true


func inventory_tab() -> InventoryTab:
	return InventoryTab.MATERIAL


func group_key() -> StringName:
	return &"materials"


func can_drop() -> bool:
	return true
