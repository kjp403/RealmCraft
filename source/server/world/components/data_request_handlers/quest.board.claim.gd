extends DataRequestHandler
## Claim the reward for one COMPLETE board slot. Everything is validated
## server-side in DailyQuestManager.claim (slot exists, was accepted, is
## finished, is not already claimed); this handler only grants what that returns.
##
## Payout is split by what it moves:
##   - gold + adventure XP ride the standard `combat.reward` channel, so the
##     claim gets the same XP bar and level-up ceremony a kill does;
##   - skill XP goes into the assigned job through PlayerResource.add_skill_xp,
##     which is the half that actually progresses a skiller.
## The claim that finishes all three folds in the completion bonus.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var resource: PlayerResource = player.player_resource

	if not args.has("slot"):
		return {"ok": false, "reason": "bad_args"}
	var slot: int = int(args.get("slot", -1))

	var result: Dictionary = DailyQuestManager.claim(resource, slot)
	if not bool(result.get("ok", false)):
		return result

	# --- Skill XP ---
	# Sum per skill first: the all-complete bonus adds a second entry for the
	# skill just claimed, and two add_skill_xp calls would report two separate
	# level-ups for one claim.
	var totals: Dictionary[StringName, int] = {}
	var skill_xp_v: Variant = result.get("skill_xp", [])
	if skill_xp_v is Array:
		for row_v: Variant in (skill_xp_v as Array):
			if row_v is not Dictionary:
				continue
			var row: Dictionary = row_v
			var slug := StringName(str(row.get("skill", "")))
			var xp: int = int(row.get("xp", 0))
			if slug == &"" or xp <= 0:
				continue
			totals[slug] = int(totals.get(slug, 0)) + xp

	var skill_grants: Array = []
	for slug: StringName in totals:
		var progress: Dictionary = resource.add_skill_xp(slug, totals[slug])
		skill_grants.append({
			"skill": String(slug),
			"name": JobRegistry.display_name(slug),
			"xp": totals[slug],
			"level": int(progress.get("level", 1)),
			"leveled_up": bool(progress.get("leveled_up", false)),
		})

	# --- Gold + adventure XP ---
	var gold: int = int(result.get("gold", 0))
	var xp_reward: int = int(result.get("adventure_xp", 0))
	if gold > 0:
		Inventory.add_item(
			resource.inventory, Economy.gold_id(), gold,
			false, resource.active_inventory_bag, resource.inventory_bags
		)

	# --- Daily Skilling Chest ---
	# Tiered off the difficulty the player committed to, with a package matching
	# the skill they just finished. grant() pays its own gold straight to the
	# pouch and STAGES the resources in pending_chest_loot — the same place a
	# world chest puts them — so a full bag defers the haul instead of voiding it.
	var chest: Dictionary = SkillingChestRewarder.grant(
		player, StringName(str(result.get("skill", ""))), int(result.get("difficulty", 0))
	)
	var chest_gold: int = int(chest.get("gold", 0)) if bool(chest.get("ok", false)) else 0

	# One combined gold line, built after the chest so the feed shows what the
	# pouch actually gained. The chest's ITEMS deliberately do not go in here:
	# loot[] is the "picked up" feed, and they are staged for the claim UI, not
	# in the bag — listing them would promise the player something their
	# inventory does not have.
	var loot: Array = []
	if gold + chest_gold > 0:
		loot.append({
			"id": Economy.gold_id(),
			"amount": gold + chest_gold,
			"name": "Gold",
		})

	var level_before: int = resource.level
	var progress_res: Dictionary = resource.add_experience(xp_reward)

	WorldServer.curr.data_push.rpc_id(peer_id, &"combat.reward", {
		"xp": xp_reward,
		"level": int(progress_res.get("level", 1)),
		"levels_gained": int(progress_res.get("levels_gained", 0)),
		"points_gained": int(progress_res.get("points_gained", 0)),
		"experience": resource.experience,
		"xp_to_next": resource.level_xp_to_next(),
		"loot": loot,
		"skills": skill_grants,
	})

	var all_claimed: bool = bool(result.get("all_claimed", false))
	var msg: String = (
		"All three dailies complete! Bonus reward earned."
		if all_claimed
		else "%s daily claimed." % JobRegistry.display_name(StringName(str(result.get("skill", ""))))
	)
	WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": [msg]})

	if int(progress_res.get("levels_gained", 0)) > 0:
		LevelMilestoneService.on_levels_gained(
			resource, level_before, int(progress_res.get("level", 1)), instance
		)

	# Refresh the board so the claimed card flips without a second round trip.
	DailyQuestManager.push_board(resource)
	return {
		"ok": true,
		"slot": slot,
		"skills": skill_grants,
		"all_claimed": all_claimed,
		# The chest rides back on the claim response so the client can open the
		# reward panel straight away. `pending` inside it is the authoritative
		# staged-loot list ChestRewardWindow claims from, and `outfit` is set
		# only on the rare piece drop.
		"chest": chest,
	}
