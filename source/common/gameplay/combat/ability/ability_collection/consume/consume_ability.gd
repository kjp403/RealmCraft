class_name ConsumeAbility
extends AbilityResource
## The "main action" of a held CONSUMABLE: consuming it. In the unified-hand model
## a consumable equipped to hand mounts this as its only ability — so the SAME main
## action that swings a weapon drinks a potion, with NO special-case path. The hand
## mounter sets [member consumable] and copies the item's tuning onto this instance:
## the item's shared cooldown -> [member cooldown], and its use_freeze -> [member
## root_s] so the sip roots you in place (reusing the weapon root, which already
## shows the "I stopped to do this" read).
##
## Server-authoritative: the heal + the spend happen on the server; every client
## sees the result through the regular stat sync (their HP/mana bars update).

## The consumable this consumes — set at mount time (NOT @export: it's owned per
## hand instance and must never be shared across players, like every mounted ability).
var consumable: ConsumableItem


## Usable while off cooldown (super) AND you still own at least one of it. Without
## the ownership check a depleted potion left in hand would "drink" nothing.
func can_use(user: Entity = null) -> bool:
	if not super.can_use(user):
		return false
	if consumable == null:
		return true
	# Refuse a NO-OP drink (full HP for a heal, full mana for a refill) so a tap never
	# wastes a potion for nothing; a buff potion always qualifies. ConsumableItem.can_use
	# already encodes exactly this. Runs on client + server (stats synced) so they agree.
	if user is Character and not consumable.can_use(user as Character):
		return false
	# Ownership is SERVER-authoritative: only the server holds player_resource (the
	# client's local player node has none — touching it there crashed), so gate on stock
	# only there. The client optimistically allows; a depleted potion auto-unequips.
	if GameMode.is_world_server() and user is Player:
		var player: Player = user as Player
		return player.player_resource != null and Inventory.has_item(
			player.player_resource.inventory, int(consumable.get_meta(&"id", 0))
		)
	return true


func use_ability(entity: Entity, _direction: Vector2) -> void:
	# Client (owner only): root briefly so the sip reads as a committed action — the
	# same movement lock a heavy weapon swing uses (see HammerWeapon). root_s was copied
	# from the item's use_freeze. FEET ONLY (lock_actions false): a swing commits your
	# whole body, but a drink must never swallow the abilities you're drinking to keep
	# using — it plants you, it doesn't disarm you.
	if GameMode.is_client() and entity == ClientState.local_player and ClientState.local_player != null:
		ClientState.local_player.freeze_movement(root_s, false)
	# The effect + the spend are server-only; clients just replay this as a no-op and
	# pick up the result via stat sync. ConsumableItem.on_use does heal/mana/buff and
	# removes one from the bag.
	if not GameMode.is_world_server() or consumable == null or entity is not Character:
		return
	consumable.on_use(entity as Character)
	# Drank the LAST one of a HELD potion → clear the hand. Never wipe a real weapon:
	# inventory/compact Use and double-click drink via item.consume while a sword/wand
	# stays equipped, and blindly erasing &"weapon" permanently destroyed that gear.
	if entity is Player:
		var player: Player = entity as Player
		var potion_id: int = int(consumable.get_meta(&"id", 0))
		if not Inventory.has_item(player.player_resource.inventory, potion_id):
			var hand_id: int = int(player.equipment_component.slots.values.get(&"weapon", 0))
			if hand_id == potion_id:
				player.equipment_component.set_hand(0)
				player.player_resource.equipment.erase(&"weapon")
