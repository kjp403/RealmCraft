class_name AmmoItem
extends GearItem
## Arrows and any future ammunition. A [GearItem] so the tier stat bonus rides
## the existing equip pipeline (`EquipmentComponent._applied_gear_mods`) with no
## combat-side code — [member GearItem.base_modifiers] is applied and stripped
## exactly like a helmet's.
##
## Ammo is equipped BY REFERENCE: the stack stays in the bag and
## `PlayerResource.equipment[&"ammo"]` holds only the item id. That's forced by
## the storage shape — `equipment` is `slot -> id` with nowhere to put a
## quantity — and it matches the precedent `item.equip.gd` already set for
## holdables ("STAYS in the bag (referenced)"). Consumption is a plain
## [method Inventory.remove_one_by_id] on the bag; when the stack empties the
## slot clears itself (see [method ChargeAbility._consume_ammo]).
##
## Because the stack is bag-resident it can be traded, banked or dropped while
## slotted, so every reader must tolerate "slot points at an id you no longer
## own" rather than trusting the slot.


func _init() -> void:
	# GearItem._init caps gear at 5; ammo is a bulk stack like any material.
	stack_limit = 0
	# Never drawn into the hand — the bow does the shooting.
	holdable = false


func inventory_tab() -> InventoryTab:
	return InventoryTab.CONSUMABLE


func group_key() -> StringName:
	return &"ammo"


func can_drop() -> bool:
	return true
