class_name EquipmentComponent
extends Node


## Pseudo-slots carrying the mastery-chosen special abilities ("abilities"
## registry ids, 0 = none). Synced exactly like gear slots so every machine —
## server, owner, remote clients replaying action echoes — mounts the SAME
## specials on the weapon. Only the server writes them (MasteryService.refresh).
const SPECIAL_SLOT: StringName = &"special_ability"
const SPECIAL_SLOT_2: StringName = &"special_ability_2"
const SPECIAL_SLOT_3: StringName = &"special_ability_3"

## Loadout position -> pseudo-slot, in input order (Q / E / R). Index IS the
## position, so adding a fourth key is one entry here plus one input action.
const SPECIAL_SLOTS: Array[StringName] = [SPECIAL_SLOT, SPECIAL_SLOT_2, SPECIAL_SLOT_3]


signal equipment_changed(
	slot: StringName,
	item_id: int
)


@export var character: Character

@export var synchronizer: StateSynchronizer


var slots: EquipmentSlots = EquipmentSlots.new()

var equipped_items: Dictionary[StringName, Item]

#Note to myself because a weapon may spawn main weapon, offhand, trail vfx, aura mount etc.
# This format may be more scalable
#Later mounted_nodes: Dictionary[StringName, Array[Node]]
var mounted_nodes: Dictionary[StringName, Node]

## Last synced special-ability ids, kept so a weapon mounted AFTER the special
## pairs applied (baseline ordering isn't guaranteed) still picks them up.
var _special_ability_ids: Array[int] = [0, 0, 0]

## Server-side ledger of gear modifiers currently applied to stats_component.
## Blind +/- on GearItem.equip/unequip could desync when a clear was skipped or
## LevelSync restored an old snapshot; the ledger makes strip/reapply idempotent.
var _applied_gear_mods: Array[Dictionary] = []


const EMPTY_HAND_SCENE: PackedScene = preload(
	"res://source/common/gameplay/items/weapons/empty_hand/empty_hand.tscn"
)


func _ready() -> void:
	slots.slot_changed.connect(_on_slot_changed)
	# Players with an empty weapon slot still need a punch so they can fight
	# before buying/equipping a weapon. Deferred: right_hand_spot must exist.
	call_deferred(&"_ensure_unarmed_if_empty")


func equip_item(item_id: int) -> bool:
	var item: GearItem = ContentRegistryHub.load_by_id(&"items", item_id) as GearItem
	if item and item.can_equip(character):
		synchronizer.set_by_path(slot_path(item.slot.key), item_id)
		return true
	return false


## Put ANY item in the HAND (the &"weapon" slot) — weapon, potion, material. Synced
## like every slot, so all clients mount it; the item's own equip() does the mounting.
## Validation (ownership, can_equip for gear) is the handler's job before this.
func set_hand(item_id: int) -> void:
	synchronizer.set_by_path(slot_path(&"weapon"), item_id)


func unequip(slot: StringName) -> void:
	synchronizer.set_by_path(slot_path(slot), 0)


## Server-side: publish the mastery special-ability ids; clients receive them
## through the regular state sync and remount via _on_slot_changed.
func set_special_abilities(ability_ids: Array[int]) -> void:
	for i: int in SPECIAL_SLOTS.size():
		var ability_id: int = ability_ids[i] if i < ability_ids.size() else 0
		if _special_ability_ids[i] != ability_id:
			synchronizer.set_by_path(slot_path(SPECIAL_SLOTS[i]), ability_id)


func can_use(slot: StringName, index: int, released: bool = false) -> bool:
	var mounted: Weapon = mounted_nodes.get(slot, null)

	if mounted and mounted.has_method("can_use_weapon"):
		return mounted.can_use_weapon(index, released)
	return false


func process_input(local_player: LocalPlayer) -> void:
	var mounted: Weapon = mounted_nodes.get(&"weapon", null)

	if mounted and mounted.has_method("process_input"):
		mounted.process_input(local_player)


func _on_slot_changed(slot: StringName, item_id: int) -> void:
	# Not gear: the value is an ability id for one of the weapon's special slots.
	if SPECIAL_SLOTS.has(slot):
		_special_ability_ids[SPECIAL_SLOTS.find(slot)] = item_id
		_apply_special_to_mounted()
		# Emitted AFTER the remount so listeners (the HUD ability bar) read the
		# weapon's final abilities. Server-side listeners filter on &"weapon".
		equipment_changed.emit(slot, item_id)
		return

	_clear_slot(slot)

	if slot == &"weapon" and character != null:
		# An armed shot override (Multishot/Deadeye/...) belongs to the BOW's
		# ChargeAbility — no other weapon can ever consume it. Left uncleared,
		# swapping off the bow mid-arm silently locked the new weapon's Q/E
		# slots (has_armed_shot() doesn't know which weapon armed it) for up
		# to ShotOverrideAbility.EXPIRY_S with no UI feedback why.
		ShotOverrideAbility.clear_armed(character)
		# Sword Berserk's lifesteal is a timed Stat buff, not weapon-gated, so it
		# kept healing off ANY damage for its duration — cast it on sword, swap
		# to Book, and Lightning Lash's sustained multi-target beam turned it
		# into a no-food heal-through-hardmode button. Lifesteal is Berserk-only
		# (grep confirms no other source), so dropping it on every weapon swap
		# is safe and keeps the buff scoped to the weapon that earned it.
		if GameMode.is_world_server() and character is Player:
			BuffService.clear_stat(character as Player, Stat.LIFESTEAL)

	if item_id == 0:
		if slot == &"weapon":
			_mount_unarmed()
		_clamp_vitals_to_max()
		equipment_changed.emit(slot, 0)
		return
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id)
	if not item:
		if slot == &"weapon":
			_mount_unarmed()
		return

	equipped_items[slot] = item
	item.equip(character)
	_apply_gear_stats(slot, item)
	if slot == &"weapon":
		_apply_special_to_mounted()
	equipment_changed.emit(slot,  item_id)


func _apply_special_to_mounted() -> void:
	var mounted: Weapon = mounted_nodes.get(&"weapon", null) as Weapon
	if mounted != null:
		mounted.mount_specials(_special_ability_ids)


## Bare-hands punch mount for players with nothing in the weapon slot.
func _mount_unarmed() -> void:
	if character == null or not (character is Player):
		return
	if character.right_hand_spot == null:
		return
	_free_mounted(&"weapon")
	var hand: Weapon = EMPTY_HAND_SCENE.instantiate() as Weapon
	if hand == null:
		return
	hand.character = character
	mounted_nodes[&"weapon"] = hand
	character.right_hand_spot.add_child(hand)


func _ensure_unarmed_if_empty() -> void:
	if character == null or not (character is Player):
		return
	var weapon_id: int = int(slots.values.get(&"weapon", 0))
	if weapon_id == 0 and not mounted_nodes.has(&"weapon"):
		_mount_unarmed()


func _free_mounted(slot: StringName) -> void:
	var node: Node = mounted_nodes.get(slot, null)
	if node != null:
		node.queue_free()
	mounted_nodes.erase(slot)


func _clear_slot(slot: StringName) -> void:
	var item: Item = equipped_items.get(slot, null)

	if item:
		item.unequip(character)
	else:
		# Empty-hand punch (and any other non-Item mount) still occupies the node.
		_free_mounted(slot)
	equipped_items.erase(slot)
	_remove_gear_stats(slot)


## Apply GearItem base_modifiers for [param slot], tracking them in the ledger.
## Safe to call after item.equip(); no-ops on clients and non-gear.
func _apply_gear_stats(slot: StringName, item: Item) -> void:
	if item == null or not (item is GearItem):
		return
	if character == null or character.multiplayer == null or not character.multiplayer.is_server():
		return
	var gear: GearItem = item as GearItem
	for modifier: StatModifier in gear.base_modifiers:
		if modifier == null or is_zero_approx(modifier.value):
			continue
		var stat: StringName = StringName(modifier.stat_name)
		character.stats_component.modify_stat(stat, modifier.value)
		_applied_gear_mods.append({
			"slot": slot,
			"stat": stat,
			"value": float(modifier.value),
		})


## Strip every ledger entry for [param slot] (or all slots when empty).
func _remove_gear_stats(slot: StringName = &"") -> void:
	if character == null or character.multiplayer == null or not character.multiplayer.is_server():
		_applied_gear_mods.clear()
		return
	for i: int in range(_applied_gear_mods.size() - 1, -1, -1):
		var entry: Dictionary = _applied_gear_mods[i]
		if slot != &"" and entry.get("slot", &"") != slot:
			continue
		character.stats_component.modify_stat(
			StringName(entry["stat"]),
			-float(entry["value"])
		)
		_applied_gear_mods.remove_at(i)


## Rebuild gear bonuses from currently equipped items. Use after LevelSync.restore
## or any path that rewrote live stats without going through slot_changed.
func reapply_all_gear_stats() -> void:
	_remove_gear_stats(&"")
	for slot: StringName in equipped_items:
		_apply_gear_stats(slot, equipped_items[slot])
	_clamp_vitals_to_max()


func _clamp_vitals_to_max() -> void:
	if character == null or character.stats_component == null:
		return
	if character.multiplayer == null or not character.multiplayer.is_server():
		return
	var comps: StatsComponent = character.stats_component
	var hmax: float = comps.get_stat(Stat.HEALTH_MAX)
	var mmax: float = comps.get_stat(Stat.MANA_MAX)
	if comps.get_stat(Stat.HEALTH) > hmax:
		comps.set_stat(Stat.HEALTH, hmax)
	if comps.get_stat(Stat.MANA) > mmax:
		comps.set_stat(Stat.MANA, mmax)


static func slot_path(slot: StringName) -> String:
	return "EquipmentComponent:slots:%s" % slot


class EquipmentSlots extends RefCounted:
	signal slot_changed(slot: StringName, item_id: int)

	var values: Dictionary[StringName, int]


	func _get(property: StringName) -> Variant:
		return values.get(property, 0)


	func _set(property: StringName, value: Variant) -> bool:
		# Wire / JSON paths sometimes deliver floats (0.0); coerce so unequip
		# can't silently no-op and leave gear stats applied.
		var item_id: int = 0
		match typeof(value):
			TYPE_INT:
				item_id = value
			TYPE_FLOAT:
				item_id = int(value)
			_:
				return false

		values[property] = item_id
		slot_changed.emit(property, item_id)
		return true
