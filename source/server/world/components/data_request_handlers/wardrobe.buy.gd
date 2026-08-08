extends DataRequestHandler
## Buy a skin for its Horizon catalogue price, adding it to the player's owned set.
## Equipping is a separate step (wardrobe.equip). Server-authoritative: validates it's a
## real for-sale player skin, isn't already owned, and that the player can pay. Persists
## on the world's periodic player save (same as shop purchases — no explicit save here).


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var pr: PlayerResource = player.player_resource

	var skin_id: int = int(args.get("skin_id", 0))
	if not PlayerSkins.is_valid(skin_id):
		return {"ok": false, "reason": "invalid"}
	if not PlayerSkins.is_for_sale(skin_id):
		return {"ok": false, "reason": "not_for_sale"}
	if pr.owned_skins.has(skin_id):
		return {"ok": false, "reason": "owned"}

	var cost: int = PlayerSkins.price(skin_id)
	var gold_id: int = Economy.gold_id()
	# remove_amount_by_id is all-or-nothing: it removes nothing and returns false if too poor.
	if gold_id <= 0 or cost <= 0 or not Inventory.remove_amount_by_id(pr.inventory, gold_id, cost):
		return {"ok": false, "reason": "no_gold", "cost": cost}

	pr.owned_skins.append(skin_id)
	return {
		"ok": true,
		"skin_id": skin_id,
		"owned": Array(pr.owned_skins),
		"gold": Inventory.count(pr.inventory, Economy.gold_id()),
		"cost": cost,
	}
