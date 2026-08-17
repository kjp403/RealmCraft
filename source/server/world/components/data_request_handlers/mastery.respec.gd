extends DataRequestHandler
## Re-spec weapon mastery. Scope is the optional "category" arg: one weapon
## category clears just that tree's spent nodes + loadout pick, omitted (or
## empty) clears every category — the original behaviour, kept so old clients
## keep working.
##
## Cost is MasteryResetInteraction.COST either way (shared with Horizon). It's
## the price of the service, not a per-tree tally; what a single-tree respec
## buys you is keeping the trees you're happy with.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var pr: PlayerResource = player.player_resource

	# Empty = every tree. A named category must have a tree, or a typo would
	# charge the fee and clear nothing.
	var only: StringName = StringName(str(args.get("category", "")))
	if not only.is_empty() and MasteryService.tree_for(only) == null:
		return {"ok": false, "reason": "no_tree"}

	var spent_nodes: int = 0
	for category: Variant in pr.masteries.keys():
		if not only.is_empty() and String(category) != String(only):
			continue
		var entry: Dictionary = pr.masteries[category]
		spent_nodes += (entry.get("spent", {}) as Dictionary).size()

	# Scoped to a tree the player never spent in, this reads "nothing" rather
	# than silently taking the gold.
	if spent_nodes <= 0:
		return {"ok": false, "reason": "nothing"}

	var gold_id: int = Economy.gold_id()
	if gold_id <= 0 or not Inventory.remove_amount_by_id(
		pr.inventory, gold_id, MasteryResetInteraction.COST
	):
		return {"ok": false, "reason": "gold"}

	var categories_cleared: int = 0
	if only.is_empty():
		for category: StringName in MasteryService.trees():
			var result: Dictionary = MasteryService.reset(pr, category)
			if result.get("ok", false):
				categories_cleared += 1
		# Also wipe loadout / spent stubs for any legacy keys not in the tree
		# registry. Only meaningful for the sweep-everything scope — a scoped
		# respec must not touch a category the player didn't name.
		for category: Variant in pr.masteries.keys():
			var entry: Dictionary = pr.masteries[category]
			var spent: Dictionary = entry.get("spent", {})
			if not spent.is_empty():
				spent.clear()
			pr.ability_loadout.erase(String(category))
	elif MasteryService.reset(pr, only).get("ok", false):
		categories_cleared = 1

	MasteryService.refresh(player)
	return {
		"ok": true,
		"categories": categories_cleared,
		"refunded_nodes": spent_nodes,
		"category": String(only),
	}
