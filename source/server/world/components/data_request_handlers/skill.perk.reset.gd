extends DataRequestHandler
## Re-spec skill perks: clears every job's spent perk ranks for a gold fee.
## Cost is SkillPerkResetInteraction.COST (shared with Horizon's dialogue).


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var pr: PlayerResource = player.player_resource
	var refunded_ranks: int = 0
	for skill_name: Variant in pr.skills:
		var skill: Dictionary = pr.skills[skill_name]
		var perks: Dictionary = skill.get("perks", {})
		for perk_id: Variant in perks:
			refunded_ranks += int(perks[perk_id])

	if refunded_ranks <= 0:
		return {"ok": false, "reason": "nothing"}

	var gold_id: int = Economy.gold_id()
	if gold_id <= 0 or not Inventory.remove_amount_by_id(
		pr.inventory, gold_id, SkillPerkResetInteraction.COST
	):
		return {"ok": false, "reason": "gold"}

	for skill_name: Variant in pr.skills:
		var skill: Dictionary = pr.skills[skill_name]
		var perks: Dictionary = skill.get("perks", {})
		if perks.is_empty():
			continue
		perks.clear()
		skill["perks"] = perks
		pr.skills[skill_name] = skill

	return {"ok": true, "refunded": refunded_ranks}
