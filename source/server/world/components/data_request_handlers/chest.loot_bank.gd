extends DataRequestHandler
## Move staged chest loot into the personal bank.
## Args: { "id": item_id, "amount": optional } — omit id to Bank All.
##
## A full vault no longer ends the hand-off: whatever the bank cannot hold falls
## through to the bag, and then to the ground at the player's feet (see
## [ItemDelivery]), so "send to bank" can never swallow a chest. Anything that
## fits nowhere at all stays staged and is reported as "full".


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

	var resource: PlayerResource = player.player_resource
	var capacity: int = maxi(BankInteraction.STARTING_SLOTS, resource.bank_slots)
	var item_id: int = int(args.get("id", 0))

	var ids: Array[int] = []
	if item_id > 0:
		ids.append(item_id)
	else:
		# Snapshot ids up front — delivering mutates the staging array.
		for entry: Variant in resource.pending_chest_loot:
			if entry is Dictionary:
				var staged_id: int = int((entry as Dictionary).get("id", 0))
				if staged_id > 0 and not ids.has(staged_id):
					ids.append(staged_id)

	# An explicit amount only applies to a single-item request; Bank All takes each
	# staged stack whole.
	var wanted: int = int(args.get("amount", -1)) if item_id > 0 else -1
	var totals: Dictionary = {"bank": 0, "bag": 0, "ground": 0, "stuck": 0}
	var had: int = 0
	for staged_id: int in ids:
		var have: int = PendingChestLoot.count(resource.pending_chest_loot, staged_id)
		if have <= 0:
			continue
		had += have
		var take: int = have if wanted < 0 else mini(wanted, have)
		var result: Dictionary = ItemDelivery.deliver_to_bank(instance, player, staged_id, take)
		var delivered: int = int(result["bank"]) + int(result["bag"]) + int(result["ground"])
		if delivered > 0:
			PendingChestLoot.take(resource.pending_chest_loot, staged_id, delivered)
		for key: Variant in totals:
			totals[key] = int(totals[key]) + int(result[key])

	var moved: int = int(totals["bank"]) + int(totals["bag"]) + int(totals["ground"])
	if moved <= 0 and had > 0:
		return {
			"ok": false,
			"reason": "full",
			"moved": 0,
			"pending": PendingChestLoot.to_payload(resource.pending_chest_loot),
			"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
			"bank": resource.bank,
			"bank_slots": capacity,
		}

	instance.world_server.database.save_player(resource)
	return {
		"ok": true,
		"moved": moved,
		"banked": int(totals["bank"]),
		"bagged": int(totals["bag"]),
		"dropped": int(totals["ground"]),
		"overflow_note": ItemDelivery.describe(totals),
		"pending": PendingChestLoot.to_payload(resource.pending_chest_loot),
		"free_slots": Inventory.total_free_slots(resource.inventory, resource.inventory_bags),
		"bank": resource.bank,
		"bank_slots": capacity,
	}
