extends DataRequestHandler
## Buy +50 personal bank slots for [constant BankInteraction.UPGRADE_COST] gold
## each. [code]count[/code] (default 1, max [constant BankInteraction.MAX_UPGRADE_COUNT])
## buys several expansions in one request, capped overall at
## [constant BankInteraction.MAX_BANK_SLOTS].


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

	var pr: PlayerResource = player.player_resource
	var current_slots: int = maxi(BankInteraction.STARTING_SLOTS, pr.bank_slots)
	if current_slots >= BankInteraction.MAX_BANK_SLOTS:
		return {"ok": false, "reason": "max_slots", "bank_slots": current_slots}

	var requested_count: int = clampi(int(args.get("count", 1)), 1, BankInteraction.MAX_UPGRADE_COUNT)
	var affordable_count: int = (BankInteraction.MAX_BANK_SLOTS - current_slots) / BankInteraction.UPGRADE_SLOTS
	# Purchases beyond the cap are trimmed to what still fits rather than rejected
	# outright, so "buy 99" near the cap just buys as many as it can.
	var count: int = mini(requested_count, affordable_count)
	var gold_id: int = Economy.gold_id()
	var cost: int = BankInteraction.UPGRADE_COST * count
	if gold_id <= 0 or cost <= 0 or not Inventory.remove_amount_by_id(pr.inventory, gold_id, cost):
		return {"ok": false, "reason": "gold", "cost": cost, "count": count}

	pr.bank_slots = current_slots + BankInteraction.UPGRADE_SLOTS * count
	instance.world_server.database.save_player(pr)
	return {
		"ok": true,
		"bank_slots": pr.bank_slots,
		"inventory": pr.inventory,
		"bank": pr.bank,
		"gold": Inventory.count(pr.inventory, gold_id),
		"count": count,
	}
