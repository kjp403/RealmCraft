extends DataRequestHandler
## Charge [constant RemoteBankInteraction.COST] gold so a remote banker/courier
## can open the personal vault. Free bankers use [code]bank.get[/code] directly.


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
	var cost: int = RemoteBankInteraction.COST
	if gold_id <= 0 or cost <= 0 or not Inventory.remove_amount_by_id(pr.inventory, gold_id, cost):
		return {"ok": false, "reason": "gold", "cost": cost}

	instance.world_server.database.save_player(pr)
	return {
		"ok": true,
		"gold": Inventory.count(pr.inventory, gold_id),
		"inventory": pr.inventory,
	}
