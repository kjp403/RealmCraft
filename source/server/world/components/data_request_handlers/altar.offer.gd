extends DataRequestHandler
## Burn bones on the church altar for Prayer xp.
##
## Range-checked against the altar NODE the same way craft.item checks a
## crafting station, so "offer from anywhere" is not a thing a hand-rolled
## client can do.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}
	if not Altar.player_in_range(player):
		return {"ok": false, "reason": "too_far"}

	var resource: PlayerResource = player.player_resource
	var inventory: Dictionary = resource.inventory
	var slot_uid: int = int(args.get("uid", -1))
	if slot_uid < 0 or not inventory.has(slot_uid):
		return {"ok": false, "reason": "missing"}

	var slot: Dictionary = inventory[slot_uid]
	var item_id: int = int(slot.get("id", 0))
	var have: int = int(slot.get("a", 0))
	if item_id <= 0 or have <= 0:
		return {"ok": false, "reason": "missing"}
	# Favourited stacks are protected here for the same reason they are in
	# item.salvage: burning bones is not recoverable.
	if bool(slot.get("p", false)):
		return {"ok": false, "reason": "pinned"}

	var table: AltarOfferingTable = AltarOfferingTable.shared()
	if table == null:
		return {"ok": false, "reason": "missing"}
	var offering: AltarOffering = table.offering_for(item_id)
	if offering == null or offering.xp <= 0:
		return {"ok": false, "reason": "not_an_offering"}

	var level: int = int(resource.get_skill(table.profession).get("level", 1))
	if level < offering.required_level:
		return {
			"ok": false,
			"reason": "prayer_level",
			"required_level": offering.required_level,
		}

	# Offer the whole stack by default — burying bones one at a time is the
	# single most tedious thing about this skill elsewhere.
	var amount: int = int(args.get("amount", have))
	if amount <= 0:
		amount = have
	amount = mini(amount, have)

	var burned: int = Inventory.remove_from_slot(inventory, slot_uid, amount)
	if burned <= 0:
		return {"ok": false, "reason": "missing"}

	var xp_gain: int = offering.xp * burned
	var perks: JobPerks = JobRegistry.perks_for(table.profession)
	if perks != null:
		var player_perks: Dictionary = resource.get_skill(table.profession).get("perks", {})
		xp_gain = maxi(1, roundi(float(xp_gain) * perks.xp_multiplier(player_perks)))
	var progress: Dictionary = resource.add_skill_xp(table.profession, xp_gain)

	# A Prayer level-up grows the pool immediately, so the orb does not lag a
	# relog behind the level.
	PrayerService.refresh_max(player)

	return {
		"ok": true,
		"id": item_id,
		"amount": burned,
		"xp": xp_gain,
		"profession": String(table.profession),
		"level": int(progress.get("level", level)),
		"leveled_up": progress.get("leveled_up", false),
		"prayer": PrayerService.status(player),
	}
