extends DataRequestHandler
## Claim the reward for one complete daily. Validates server-side that the
## entry actually exists in the player's current set + isn't already claimed
## + objective is met. On success, grants adventure XP, weapon-mastery XP and
## gold, and marks claimed.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var resource: PlayerResource = player.player_resource

	var template_id: int = int(args.get("template_id", 0))
	if template_id <= 0:
		return {"ok": false, "reason": "bad_args"}

	var result: Dictionary = DailyQuestService.claim(resource, template_id)
	if not bool(result.get("ok", false)):
		return result

	# Grant the reward through the standard combat.reward channel so the client
	# gets the same XP bar / level-up handling as kills and mainline quests. The
	# claim that completes the whole set folds in a one-off completion bonus.
	var bonus_xp: int = int(result.get("bonus_xp", 0))
	var bonus_gold: int = int(result.get("bonus_gold", 0))
	var xp: int = int(result.get("xp", 0)) + bonus_xp
	var gold: int = int(result.get("gold", 0)) + bonus_gold
	var mastery_xp: int = (
		int(result.get("mastery_xp", 0)) + int(result.get("bonus_mastery_xp", 0))
	)
	var inventory: Dictionary = resource.inventory
	var loot: Array = []
	if gold > 0:
		Inventory.add_item(inventory, Economy.gold_id(), gold)
		loot.append({"id": Economy.gold_id(), "amount": gold, "name": "Gold"})

	var level_before: int = resource.level
	var progress: Dictionary = resource.add_experience(xp)
	# Weapon-mastery XP is the half of the reward that actually progresses a
	# character — see DailyQuestTemplate.reward_mastery_xp. Riding it out on the
	# same combat.reward key a kill uses gives the claim the same bar and level-up
	# ceremony, so the player can see where the XP went.
	var mastery: Dictionary = RewardService.grant_mastery_reward(peer_id, mastery_xp)

	WorldServer.curr.data_push.rpc_id(peer_id, &"combat.reward", {
		"xp": xp,
		"level": int(progress.get("level", 1)),
		"levels_gained": int(progress.get("levels_gained", 0)),
		"points_gained": int(progress.get("points_gained", 0)),
		"experience": resource.experience,
		"xp_to_next": resource.level_xp_to_next(),
		"loot": loot,
		"mastery": mastery,
	})
	var claim_msg: String = "All dailies complete! Bonus reward earned." if (bonus_xp > 0 or bonus_gold > 0) else "Daily reward claimed."
	WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": [claim_msg]})

	if int(progress.get("levels_gained", 0)) > 0:
		LevelMilestoneService.on_levels_gained(resource, level_before, int(progress.get("level", 1)), instance)

	return {"ok": true}
