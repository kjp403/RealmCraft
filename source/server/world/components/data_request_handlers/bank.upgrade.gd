extends DataRequestHandler
## Buy +50 personal bank slots for [constant BankInteraction.UPGRADE_COST] gold.
## No purchase cap — players can expand forever.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var pr: PlayerResource = player.player_resource
	var gold_id: int = Economy.gold_id()
	var cost: int = BankInteraction.UPGRADE_COST
	if gold_id <= 0 or cost <= 0 or not Inventory.remove_amount_by_id(pr.inventory, gold_id, cost):
		return {"ok": false, "reason": "gold", "cost": cost}

	pr.bank_slots = maxi(BankInteraction.STARTING_SLOTS, pr.bank_slots) + BankInteraction.UPGRADE_SLOTS
	instance.world_server.database.save_player(pr)
	return {
		"ok": true,
		"bank_slots": pr.bank_slots,
		"inventory": pr.inventory,
		"bank": pr.bank,
		"gold": Inventory.count(pr.inventory, gold_id),
	}
