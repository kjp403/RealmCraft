class_name QuestService
## Server-side quest logic shared by the kill/craft hooks and the quest handlers.
## Pure functions over a PlayerResource — no per-instance state.


## A player killed an enemy of [param enemy_type]: advance matching KILL objectives.
## Returns human-readable progress lines for client feedback. peer_id + instance
## are needed for the auto_complete path (turn-in pushes / milestones) and can be
## omitted in tests or contexts that don't care.
static func on_kill(
	resource: PlayerResource, enemy_type: StringName,
	peer_id: int = 0, instance: Node = null
) -> Array:
	return _advance_matching(resource, QuestObjective.Type.KILL, enemy_type, peer_id, instance)


## A player crafted [param item_id]: advance matching CRAFT objectives.
static func on_craft(
	resource: PlayerResource, item_id: int,
	peer_id: int = 0, instance: Node = null
) -> Array:
	return _advance_matching(resource, QuestObjective.Type.CRAFT, item_id, peer_id, instance)


## A player opened the quest menu at [param giver_id]: advance matching VISIT
## objectives. VISIT objectives are single-fire (required_amount typically 1),
## so re-visiting after completion is a no-op.
static func on_visit(
	resource: PlayerResource, giver_key: StringName,
	peer_id: int = 0, instance: Node = null
) -> Array:
	return _advance_matching(resource, QuestObjective.Type.VISIT, giver_key, peer_id, instance)


static func _advance_matching(
	resource: PlayerResource, objective_type: int, key: Variant,
	peer_id: int = 0, instance: Node = null
) -> Array:
	var updates: Array = []
	# Auto-complete fires can't happen mid-iteration of resource.quests because
	# apply_turn_in mutates it (set_quest_turned_in). Defer the fires to after
	# the iteration to keep the dict stable.
	var pending_auto_complete: Array[QuestResource] = []
	for quest_id: int in resource.quests:
		if resource.quest_state(quest_id) != &"active":
			continue
		var quest: QuestResource = QuestResource.load_quest(quest_id)
		if quest == null:
			continue
		# Snapshot completion state so we can detect the moment a quest crosses
		# from incomplete -> ready and append the right end-of-quest toast.
		var was_complete: bool = is_complete(resource, quest_id, resource.inventory)
		for i: int in quest.objectives.size():
			var objective: QuestObjective = quest.objectives[i]
			if objective.type != objective_type or objective.target_key() != key:
				continue
			if resource.quest_progress(quest_id, i) >= objective.required_amount:
				continue # already done
			resource.advance_quest(quest_id, i, 1)
			_grant_objective_item(resource, objective, peer_id)
			# Progress ticks are STRUCTURED entries (events stay plain strings):
			# the client routes them tracker-first (docs/notifications.md) —
			# tracked quest = tracker pulse, no card; untracked = one
			# self-replacing card per quest. Callers just forward the array.
			updates.append({"q": quest_id, "t": "%s: %s (%d/%d)" % [
				quest.quest_name, objective.describe(),
				resource.quest_progress(quest_id, i), objective.required_amount
			]})
		if not was_complete and is_complete(resource, quest_id, resource.inventory):
			# Wardstone lands ON the triumph (the objective crossing), not at
			# the turn-in walk-back — docs/wardstones.md.
			grant_wardstone_if_due(resource, quest, peer_id)
			if quest.auto_complete:
				# apply_turn_in pushes its own quest.update toast — don't append
				# the "ready — return" line that'd confuse the player.
				pending_auto_complete.append(quest)
			else:
				# Latch so notify_passive_ready (the COLLECT path) doesn't re-toast this.
				resource.set_quest_ready_notified(quest_id, true)
				# Structured like progress ticks: the tracked quest's tracker already
				# shows the ready state (green + "Return to..."), so the client only
				# cards this for UNTRACKED quests.
				updates.append({"q": quest_id, "ready": true,
					"t": "✓ %s ready to turn in. Return to the quest giver." % quest.quest_name})
	for quest: QuestResource in pending_auto_complete:
		apply_turn_in(resource, quest, peer_id, instance)
	return updates


## Current progress for one objective: stored counter for KILL/CRAFT, live inventory
## count for COLLECT (capped at required for display sanity). CRAFT also credits
## the bag: brewing a unique quest output before the CRAFT step is accepted
## (True Seep Root → Seepbreaker's Draught) must not soft-lock the chain.
static func objective_count(
	resource: PlayerResource, quest_id: int, objective_index: int,
	objective: QuestObjective, inventory: Dictionary
) -> int:
	if objective.type == QuestObjective.Type.COLLECT:
		var collect_id: int = int(objective.item.get_meta(&"id", 0)) if objective.item else 0
		return mini(Inventory.count(inventory, collect_id), objective.required_amount)
	if objective.type == QuestObjective.Type.CRAFT and objective.item:
		var craft_id: int = int(objective.item.get_meta(&"id", 0))
		var held: int = Inventory.count(inventory, craft_id) if craft_id > 0 else 0
		var crafted: int = resource.quest_progress(quest_id, objective_index)
		return mini(maxi(held, crafted), objective.required_amount)
	return mini(resource.quest_progress(quest_id, objective_index), objective.required_amount)


## Applies a turn-in: consumes COLLECT items + the delivery item, grants adventure
## XP / weapon-mastery XP / gold / item rewards, marks the quest turned_in,
## unlocks any title, pushes
## the combat.reward + quest.update feedback, and fires milestone unlocks.
## Shared between the manual turn-in handler and the auto_complete path that
## fires from inside _advance_matching the moment a self-completing quest
## crosses its bar.
static func apply_turn_in(
	resource: PlayerResource,
	quest: QuestResource,
	peer_id: int,
	instance: Node
) -> void:
	var inventory: Dictionary = resource.inventory

	# Consume COLLECT items + grant_on_accept (delivery item served its narrative).
	for objective: QuestObjective in quest.objectives:
		if objective.type == QuestObjective.Type.COLLECT and objective.item:
			Inventory.remove_amount_by_id(
				inventory, int(objective.item.get_meta(&"id", 0)), objective.required_amount
			)
	if quest.grant_on_accept:
		var grant_id: int = int(quest.grant_on_accept.get_meta(&"id", 0))
		if grant_id > 0:
			Inventory.remove_amount_by_id(inventory, grant_id, 1)

	# Pay rewards. Loot list is shared with the combat.reward push so the client
	# gets the same toasts + XP-bar handling a kill gives. Mastery XP is applied
	# first so a campaign kit that gates on the new mastery can be equipped
	# immediately after the turn-in.
	var loot: Array = []
	var level_before: int = resource.level
	var progress: Dictionary = resource.add_experience(quest.reward_xp)
	var mastery: Dictionary = RewardService.grant_mastery_reward(peer_id, quest.reward_mastery_xp)
	if quest.reward_gold > 0:
		Inventory.add_item(inventory, Economy.gold_id(), quest.reward_gold)
		loot.append({"id": Economy.gold_id(), "amount": quest.reward_gold, "name": "Gold"})
	for reward: QuestReward in quest.reward_items:
		if reward and reward.item:
			var reward_id: int = int(reward.item.get_meta(&"id", 0))
			Inventory.add_item(inventory, reward_id, reward.amount)
			loot.append({"id": reward_id, "amount": reward.amount, "name": str(reward.item.item_name)})
	var style_weapon: Item = quest.pick_style_weapon_for(resource)
	if style_weapon:
		var style_id: int = int(style_weapon.get_meta(&"id", 0))
		if style_id > 0:
			Inventory.add_item(inventory, style_id, 1)
			loot.append({"id": style_id, "amount": 1, "name": str(style_weapon.item_name)})
	var quest_id: int = int(quest.get_meta(&"id", 0))
	resource.set_quest_turned_in(quest_id)

	if not quest.grants_flag.is_empty():
		grant_flag_if_due(resource, quest, peer_id)

	# Safety net: normally granted at the objective crossing (see
	# _advance_matching); idempotent, so this only catches odd shapes like
	# no-objective quests that never cross.
	grant_wardstone_if_due(resource, quest, peer_id)

	# Vanity title grant — auto-equips only if no title currently displayed.
	var quest_messages: Array = ["Quest complete: %s" % quest.quest_name]
	if not quest.grant_title.is_empty() and not resource.titles_unlocked.has(quest.grant_title):
		resource.titles_unlocked.append(quest.grant_title)
		if resource.display_title.is_empty():
			resource.display_title = quest.grant_title
		quest_messages.append("Title unlocked: %s" % quest.grant_title)

	if peer_id > 0:
		WorldServer.curr.data_push.rpc_id(peer_id, &"combat.reward", {
			"xp": quest.reward_xp,
			"level": int(progress.get("level", 1)),
			"levels_gained": int(progress.get("levels_gained", 0)),
			"points_gained": int(progress.get("points_gained", 0)),
			"experience": resource.experience,
			"xp_to_next": resource.level_xp_to_next(),
			"loot": loot,
			# Rides the same key a kill uses, so the mastery bar, toast and
			# level-up ceremony all fire for a turn-in with no client changes.
			"mastery": mastery,
		})
		WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {"messages": quest_messages})

	if instance != null:
		# Unlock toasts for quests this turn-in was the last gate of. Passes the
		# PRE-turn-in level so quests unlocked by the XP's level-up are left to
		# on_levels_gained below (the two paths partition, never double-toast).
		LevelMilestoneService.on_quest_turned_in(resource, quest_id, level_before, instance)
	if int(progress.get("levels_gained", 0)) > 0 and instance != null:
		LevelMilestoneService.on_levels_gained(
			resource, level_before, int(progress.get("level", 1)), instance
		)


## Wardstone grant (docs/wardstones.md): a biome finale quest carries
## grants_wardstone; the stone lands the MOMENT its objectives complete (boss
## down / dungeon cleared) so the unlock rides the triumph, not the walk back.
## Idempotent — safe to call from every completion path. Pushes the refreshed
## mirror + the ceremony to the earning client. Server-only path.
static func grant_wardstone_if_due(
	resource: PlayerResource, quest: QuestResource, peer_id: int
) -> void:
	var stone: String = String(quest.grants_wardstone)
	if stone.is_empty() or resource.wardstones.has(stone):
		return
	resource.wardstones.append(stone)
	ServerLog.info("Player #%d (%s) reclaimed the %s Wardstone." % [
		resource.player_id, resource.display_name, stone.capitalize()
	])
	if peer_id > 0:
		WorldServer.curr.data_push.rpc_id(peer_id, &"wardstones.set", {"wardstones": resource.wardstones})
		WorldServer.curr.data_push.rpc_id(peer_id, &"wardstone.granted", {"stone": stone})
		# Guild record line (docs/notifications.md): guildmates see the milestone
		# in chat — social proof, scroll-back-able, guild-scoped so it never
		# spams the world. Live grants only (peer_id 0 = silent login backfill).
		_announce_to_guild(resource, "%s reclaimed the %s Wardstone." % [
			resource.display_name, stone.capitalize()
		])


## Persist a story flag on turn-in and mirror it to the earning client so
## flag-gated NPCs (Lira bound/freed) can swap immediately.
static func grant_flag_if_due(
	resource: PlayerResource, quest: QuestResource, peer_id: int
) -> void:
	var flag: StringName = quest.grants_flag
	if flag.is_empty() or resource.has_character_flag(flag):
		return
	resource.set_character_flag(flag)
	push_character_flags(resource, peer_id)


## Mirror the player's story flags to their client (login + live grants).
static func push_character_flags(resource: PlayerResource, peer_id: int) -> void:
	if peer_id <= 0 or WorldServer.curr == null:
		return
	var flags: Array = []
	for key: Variant in resource.character_flags:
		if resource.character_flags[key]:
			flags.append(str(key))
	# Deferred: login runs this in the same frame as complete_auth, and an
	# immediate rpc_id can land before the client is subscribed.
	WorldServer.curr.data_push.rpc_id.call_deferred(peer_id, &"character_flags.set", {"flags": flags})


## Grant [member QuestObjective.grant_item] once, when the objective just
## crossed its required count. Quiet bag update so the tracker still owns
## the moment.
static func _grant_objective_item(
	resource: PlayerResource, objective: QuestObjective, peer_id: int
) -> void:
	if objective.grant_item == null:
		return
	var item_id: int = int(objective.grant_item.get_meta(&"id", 0))
	if item_id <= 0:
		return
	Inventory.add_item(resource.inventory, item_id, 1)
	if peer_id > 0 and WorldServer.curr != null:
		WorldServer.curr.data_push.rpc_id(peer_id, &"item.picked_up", {
			"id": item_id,
			"amount": 1,
			"name": str(objective.grant_item.item_name),
			"quiet": true,
		})


## System chat line to every ONLINE member of the player's active guild
## (including the player — it's their record too). Same pattern as
## GuildTrophies' announce. No-op for guildless players.
static func _announce_to_guild(resource: PlayerResource, message: String) -> void:
	if resource.active_guild_id <= 0:
		return
	var ws: WorldServer = WorldServer.curr
	if ws == null or ws.chat_service == null:
		return
	for other_peer: int in ws.connected_players:
		var member: PlayerResource = ws.connected_players[other_peer]
		if member != null and member.active_guild_id == resource.active_guild_id:
			ws.chat_service.push_system_to_player(null, member.player_id, message)


## Login backfill: finale quests turned in BEFORE the wardstone system shipped
## (or before a stone was added to an existing quest) still owe their stone —
## the objective crossing already happened and will never re-fire. Silent
## (peer_id 0 = no ceremony; the login wardstones.set push carries the mirror).
static func backfill_wardstones(resource: PlayerResource) -> void:
	for quest_id: int in resource.quests:
		if resource.quest_state(quest_id) != &"turned_in":
			continue
		var quest: QuestResource = QuestResource.load_quest(quest_id)
		if quest != null:
			grant_wardstone_if_due(resource, quest, 0)


## Login backfill: story flags from turned-in quests (e.g. Unrooted → lira_freed).
## Same shape as wardstones — a completion from before grants_flag shipped never
## re-fires apply_turn_in, so the NPC swap would stay stuck without this.
static func backfill_character_flags(resource: PlayerResource) -> void:
	for quest_id: int in resource.quests:
		if resource.quest_state(quest_id) != &"turned_in":
			continue
		var quest: QuestResource = QuestResource.load_quest(quest_id)
		if quest != null:
			grant_flag_if_due(resource, quest, 0)


## True when the quest's completion rule is satisfied. ALL = every objective met
## (classic AND); ANY = at least one objective met (for "pick a path" quests).
static func is_complete(resource: PlayerResource, quest_id: int, inventory: Dictionary) -> bool:
	var quest: QuestResource = QuestResource.load_quest(quest_id)
	if quest == null:
		return false
	if quest.objectives.is_empty():
		# No-objective quest (e.g. visit-then-turn-in) — complete on accept.
		return true
	var any_met: bool = false
	for i: int in quest.objectives.size():
		var objective: QuestObjective = quest.objectives[i]
		var met: bool = objective_count(resource, quest_id, i, objective, inventory) >= objective.required_amount
		if met:
			any_met = true
		elif quest.completion == QuestResource.Completion.ALL:
			return false
	return any_met


## Recover the unique Heart drop / bottle when the player brewed (or poured)
## before the matching quest was accepted. The Real Draught needs the root so
## CRAFT can fire; Unrooted needs the bottle itself (COLLECT), so don't send
## them back to the table.
static func replenish_seep_root_if_needed(resource: PlayerResource, peer_id: int) -> void:
	var draught_id: int = ContentRegistryHub.id_from_slug(&"items", &"seepbreakers_draught")
	var root_id: int = ContentRegistryHub.id_from_slug(&"items", &"true_seep_root")
	if draught_id <= 0 or root_id <= 0:
		return
	if Inventory.count(resource.inventory, draught_id) > 0:
		return
	if Inventory.count(resource.bank, draught_id) > 0:
		return
	var draught_quest_id: int = ContentRegistryHub.id_from_slug(&"quests", &"the_real_draught")
	var unrooted_id: int = ContentRegistryHub.id_from_slug(&"quests", &"unrooted")
	var draught_active: bool = (
		draught_quest_id > 0 and resource.quest_state(draught_quest_id) == &"active"
	)
	var unrooted_active: bool = (
		unrooted_id > 0 and resource.quest_state(unrooted_id) == &"active"
	)
	if draught_active:
		if Inventory.count(resource.inventory, root_id) > 0:
			return
		if Inventory.count(resource.bank, root_id) > 0:
			return
		_grant_seep_recovery_item(resource, peer_id, root_id, "True Seep Root")
		return
	if unrooted_active:
		_grant_seep_recovery_item(
			resource, peer_id, draught_id, "Seepbreaker's Draught"
		)


static func _grant_seep_recovery_item(
	resource: PlayerResource, peer_id: int, item_id: int, fallback_name: String
) -> void:
	Inventory.add_item(resource.inventory, item_id, 1)
	var item: Item = ContentRegistryHub.load_by_id(&"items", item_id) as Item
	if peer_id > 0 and WorldServer.curr != null:
		WorldServer.curr.data_push.rpc_id(peer_id, &"item.picked_up", {
			"id": item_id,
			"amount": 1,
			"name": str(item.item_name) if item else fallback_name,
			"quiet": false,
		})


## Pushes the "ready to turn in" toast for any active quest that became complete
## via a passive path (COLLECT items now in the bag, or a CRAFT output already
## held) that fires no advance event.
## Latches per quest so a tracker refresh doesn't re-toast, and clears the latch
## if the quest drops back below complete (items sold/lost). KILL/CRAFT/VISIT
## event completions are already latched by _advance_matching.
static func notify_passive_ready(resource: PlayerResource, peer_id: int) -> void:
	if peer_id <= 0:
		return
	for quest_id: int in resource.quests:
		if resource.quest_state(quest_id) != &"active":
			continue
		var quest: QuestResource = QuestResource.load_quest(quest_id)
		if quest == null or quest.auto_complete:
			continue
		var complete: bool = is_complete(resource, quest_id, resource.inventory)
		var notified: bool = resource.quest_ready_notified(quest_id)
		if complete and not notified:
			resource.set_quest_ready_notified(quest_id, true)
			grant_wardstone_if_due(resource, quest, peer_id) # COLLECT-path crossing
			WorldServer.curr.data_push.rpc_id(peer_id, &"quest.update", {
				"messages": [{"q": quest_id, "ready": true,
					"t": "✓ %s ready to turn in. Return to the quest giver." % quest.quest_name}]
			})
		elif not complete and notified:
			resource.set_quest_ready_notified(quest_id, false)
