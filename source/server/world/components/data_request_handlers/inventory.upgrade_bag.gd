extends DataRequestHandler
## Buy an additional inventory bag from the banker. Bag 2 costs 500,000 gold;
## bag 3 costs 1,250,000 gold. Players start with 1 bag.

const COST_BAG_2: int = 500000
const COST_BAG_3: int = 1250000


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}

	var pr: PlayerResource = player.player_resource
	var next_bag: int = pr.inventory_bags + 1
	if next_bag > Inventory.MAX_BAGS:
		return {"ok": false, "reason": "max_bags"}

	var cost: int = COST_BAG_2 if next_bag == 2 else COST_BAG_3
	var gold_id: int = Economy.gold_id()
	if gold_id <= 0:
		return {"ok": false, "reason": "no_currency"}
	if not Inventory.remove_amount_by_id(pr.inventory, gold_id, cost):
		return {"ok": false, "reason": "cant_afford"}

	pr.inventory_bags = next_bag
	instance.world_server.database.save_player(pr)
	return {"ok": true, "bags": pr.inventory_bags, "cost": cost}
