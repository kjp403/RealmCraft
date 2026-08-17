extends DataRequestHandler
## Re-spec skill perks. Scope is the optional "skill" arg: one job slug refunds
## just that job's ranks, omitted (or empty) refunds every job — the original
## all-or-nothing behaviour, kept so old clients keep working.
##
## Cost is SkillPerkResetInteraction.COST either way. It's the price of the
## service, not a per-job tally; what a single-job respec buys you is keeping
## the perks you're happy with instead of rebuilding all of them.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}

	var pr: PlayerResource = player.player_resource

	# Empty = every job. A named job must actually exist, or a typo would charge
	# the fee and refund nothing.
	var only: StringName = StringName(str(args.get("skill", "")))
	if not only.is_empty() and JobRegistry.perks_for(only) == null:
		return {"ok": false, "reason": "unknown_skill"}

	var targets: Array[StringName] = []
	if only.is_empty():
		for skill_name: Variant in pr.skills:
			targets.append(StringName(str(skill_name)))
	else:
		targets.append(only)

	var refunded_ranks: int = 0
	for skill_name: StringName in targets:
		refunded_ranks += _spent_ranks(pr, skill_name)

	# Scoped to a job the player never spent in, this reads "nothing" rather
	# than silently taking the gold.
	if refunded_ranks <= 0:
		return {"ok": false, "reason": "nothing"}

	var gold_id: int = Economy.gold_id()
	if gold_id <= 0 or not Inventory.remove_amount_by_id(
		pr.inventory, gold_id, SkillPerkResetInteraction.COST
	):
		return {"ok": false, "reason": "gold"}

	for skill_name: StringName in targets:
		_clear_perks(pr, skill_name)

	return {"ok": true, "refunded": refunded_ranks, "skill": String(only)}


## Total perk ranks the player has bought in [param skill_name].
##
## Saved skill keys are String or StringName depending on when the entry was
## written, so match on the string form — the same care MasteryService takes
## with its mastery keys. A plain `pr.skills.get(skill_name)` misses half of them.
static func _spent_ranks(pr: PlayerResource, skill_name: StringName) -> int:
	var total: int = 0
	for existing: Variant in pr.skills:
		if String(existing) != String(skill_name):
			continue
		var perks: Dictionary = (pr.skills[existing] as Dictionary).get("perks", {})
		for perk_id: Variant in perks:
			total += int(perks[perk_id])
	return total


static func _clear_perks(pr: PlayerResource, skill_name: StringName) -> void:
	for existing: Variant in pr.skills:
		if String(existing) != String(skill_name):
			continue
		var skill: Dictionary = pr.skills[existing]
		var perks: Dictionary = skill.get("perks", {})
		if perks.is_empty():
			continue
		perks.clear()
		skill["perks"] = perks
		pr.skills[existing] = skill
