extends DataRequestHandler
## Re-spec weapon mastery: clears every category's spent nodes + loadout picks
## for a gold fee. Cost is MasteryResetInteraction.COST (shared with Horizon).


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var pr: PlayerResource = player.player_resource
	var spent_nodes: int = 0
	for category: Variant in pr.masteries.keys():
		var entry: Dictionary = pr.masteries[category]
		spent_nodes += (entry.get("spent", {}) as Dictionary).size()

	if spent_nodes <= 0:
		return {"ok": false, "reason": "nothing"}

	var gold_id: int = Economy.gold_id()
	if gold_id <= 0 or not Inventory.remove_amount_by_id(
		pr.inventory, gold_id, MasteryResetInteraction.COST
	):
		return {"ok": false, "reason": "gold"}

	var categories_cleared: int = 0
	for category: StringName in MasteryService.trees():
		var result: Dictionary = MasteryService.reset(pr, category)
		if result.get("ok", false):
			categories_cleared += 1
	# Also wipe loadout / spent stubs for any legacy keys not in the tree registry.
	for category: Variant in pr.masteries.keys():
		var entry: Dictionary = pr.masteries[category]
		var spent: Dictionary = entry.get("spent", {})
		if not spent.is_empty():
			spent.clear()
		pr.ability_loadout.erase(String(category))

	MasteryService.refresh(player)
	return {"ok": true, "categories": categories_cleared, "refunded_nodes": spent_nodes}
