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


@export_group("Proc")
## Chance per landed ranged hit that [member effect_type] fires, 0-1. 0 = an
## ordinary arrow with no proc, which is every tier up to Runite.
##
## Rolled on the SERVER inside [AmmoProcService], never on the client and never
## from a value the client sent. The client is told a proc happened only by the
## hit payload that comes back, so a hand-rolled client can spoof neither the
## roll nor the rate.
@export_range(0.0, 1.0, 0.01) var proc_chance: float = 0.0
## Which effect fires. See [AmmoProcService] for the authored set; an unknown
## value is ignored rather than guessed at.
@export var effect_type: StringName = &""
## Effect strength. Its meaning is per-effect and documented on the handler —
## damage per second for a burn, a fraction of the hit for a siphon, splash
## damage for a burst, a 0-1 slow fraction for gravity.
@export var proc_magnitude: float = 0.0
## How long the effect lasts on the victim. Ignored by instant effects.
@export var proc_duration_s: float = 0.0


## True when this ammunition has a complete, firing proc. A half-authored proc
## (a chance with no effect, or an effect with no chance) is an authoring slip,
## not a weak arrow, so it counts as no proc at all and `verify_high_tier_arrows`
## fails the build on it.
func has_proc() -> bool:
	return proc_chance > 0.0 and not effect_type.is_empty() and proc_magnitude > 0.0


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
