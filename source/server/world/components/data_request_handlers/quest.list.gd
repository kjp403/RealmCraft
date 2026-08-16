extends DataRequestHandler
## Returns quest views. With {"giver": id} -> the quests that giver offers (with the
## player's state on each). Without it -> the player's own quests (for a quest log),
## or with {"all": true} the WHOLE catalog, so the log can also show the quests the
## player hasn't started yet.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {}

	var resource: PlayerResource = player.player_resource
	var inventory: Dictionary = resource.inventory

	# Build {quest_id -> QuestResource} from the giver directly. This bypasses
	# the content registry, so newly-authored quests render correctly at their
	# giver even before the TinyMMO plugin's content index has been
	# regenerated. (Regeneration is still needed for the player's quest log
	# view, which only has IDs to work with.)
	var quest_ids: Array = []
	var resources_by_id: Dictionary = {}
	var giver_key: StringName = StringName(str(args.get("giver", "")))
	var giver_name: String = ""
	if not giver_key.is_empty():
		# Opening the menu at a giver is "visiting" them — advance any matching
		# VISIT objectives BEFORE building the view so the player sees the
		# just-advanced count in the same response. Also push quest.update so
		# the HUD tracker refreshes immediately (same pattern as kill/craft).
		var visit_updates: Array = QuestService.on_visit(
			resource,
			giver_key,
			peer_id,
			instance
		)
		if not visit_updates.is_empty():
			WorldServer.curr.data_push.rpc_id(
				peer_id,
				&"quest.update",
				{"messages": visit_updates}
			)
		var giver: Object = instance.instance_map.get_quest_giver(giver_key)
		if giver:
			giver_name = str(giver.get(&"giver_name"))
			for quest: QuestResource in giver.get(&"quests"):
				if quest:
					var qid: int = int(quest.get_meta(&"id", 0))
					# Prereq-locked quests are INCLUDED and render locked with
					# their unlock conditions. Accepting stays hard-gated
					# server-side in quest.accept.
					resources_by_id[qid] = quest
					quest_ids.append(qid)
			# Pending turn-ins: active quests whose turn_in_giver_id points at
			# this giver (delivery quests).
			for active_quest_id: int in resource.quests.keys():
				if quest_ids.has(active_quest_id):
					continue
				if resource.quest_state(active_quest_id) != &"active":
					continue
				var quest: QuestResource = QuestResource.load_quest(
					active_quest_id
				)
				if quest and quest.turn_in_giver_key() == giver_key:
					resources_by_id[active_quest_id] = quest
					quest_ids.append(active_quest_id)
	elif bool(args.get("all", false)):
		# Whole catalog, for the log's "Not Started" browse. Registry-backed, so
		# it only lists quests whose content index has been generated — a
		# freshly-authored quest shows at its giver before it shows here.
		var registry: ContentRegistry = ContentRegistryHub.registry_of(&"quests")
		if registry != null:
			quest_ids = registry.all_ids()
		# Anything the player holds that the index doesn't know about (stale
		# index) still belongs in their own log.
		for owned_id: Variant in resource.quests.keys():
			if not quest_ids.has(int(owned_id)):
				quest_ids.append(int(owned_id))
	else:
		quest_ids = resource.quests.keys()

	var out: Array = []
	for quest_id: int in quest_ids:
		out.append(
			_quest_view(
				resource,
				int(quest_id),
				resources_by_id.get(quest_id),
				inventory
			)
		)

	# Unique Heart-drop recovery, then toast any quest that just became
	# turn-in-able via a passive COLLECT/CRAFT fill (inventory changes fire no
	# advance event). Latches so it only toasts once.
	QuestService.replenish_seep_root_if_needed(resource, peer_id)
	QuestService.purge_orphaned_quest_items(resource, peer_id)
	QuestService.notify_passive_ready(resource, peer_id)
	return {
		"giver": String(giver_key),
		"giver_name": giver_name,
		"quests": out,
	}


func _quest_view(
	resource: PlayerResource,
	quest_id: int,
	quest_ref: QuestResource,
	inventory: Dictionary
) -> Dictionary:
	# Prefer the direct reference (from the giver) over the registry lookup —
	# avoids "?" names when the content index is stale.
	var quest: QuestResource = (
		quest_ref
		if quest_ref != null
		else QuestResource.load_quest(quest_id)
	)
	if quest == null:
		return {"id": quest_id, "name": "?", "objectives": []}

	# A turned-in quest is locked done — for COLLECT, don't recompute the count
	# from live inventory after its items have been consumed.
	var turned_in: bool = resource.quest_state(quest_id) == &"turned_in"

	var objectives: Array = []
	for i: int in quest.objectives.size():
		var objective: QuestObjective = quest.objectives[i]
		if objective == null:
			ServerLog.warn(
				(
					"quest.list: quest %d ('%s') objective %d is null "
					+ "(broken resource ref?) — skipped"
				) % [quest_id, quest.quest_name, i]
			)
			continue

		var count: int = (
			objective.required_amount
			if turned_in
			else QuestService.objective_count(
				resource,
				quest_id,
				i,
				objective,
				inventory
			)
		)
		var visit_target_key: String = ""
		var visit_target_name: String = ""
		if objective.type == QuestObjective.Type.VISIT:
			if objective.target_giver != null:
				visit_target_key = String(objective.target_giver.giver_key())
				visit_target_name = objective.target_giver_name
				if visit_target_name.is_empty():
					visit_target_name = objective.target_giver.npc_name
			else:
				# Slug-only visits (cycle-safe authoring) still need a minimap key.
				visit_target_key = String(objective.target_giver_key)
				visit_target_name = objective.target_giver_name
		var kill_enemy: String = ""
		if objective.type == QuestObjective.Type.KILL:
			kill_enemy = String(objective.enemy_type)
			if visit_target_name.is_empty():
				visit_target_name = objective.kill_label()

		objectives.append({
			"desc": objective.describe(),
			"count": count,
			"required": objective.required_amount,
			# VISIT objectives are single-fire; the client hides (0/1).
			"countable": objective.type != QuestObjective.Type.VISIT,
			# A stable content key, not a coordinate. The client resolves the
			# matching NPC in whichever map is currently active.
			"target_giver": visit_target_key,
			"target_name": visit_target_name,
			"target_enemy": kill_enemy,
			"waypoints": Array(objective.waypoint_labels),
		})

	return {
		"id": quest_id,
		"name": quest.quest_name,
		"description": quest.description,
		"state": String(resource.quest_state(quest_id)),
		"complete": (
			turned_in
			or QuestService.is_complete(resource, quest_id, inventory)
		),
		"objectives": objectives,
		"reward_xp": quest.reward_xp,
		"reward_mastery_xp": quest.reward_mastery_xp,
		"reward_gold": quest.reward_gold,
		"min_level": quest.min_level,
		"meets_level": resource.level >= quest.min_level,
		# Profession-skill gate. skill_req is pre-formatted ("Mining 14") so the
		# client doesn't need JobRegistry display names; "" = no skill gate.
		"skill_req": quest.skill_gate_label(),
		"meets_skill": quest.meets_skill_gate(resource),
		"completion": int(quest.completion),
		"meets_prereq": (
			resource.quest_state(quest_id) != &""
			or quest.prerequisites_met(resource)
		),
		"prereq_names": _unmet_prereq_names(resource, quest),
		"prereq_mode": int(quest.requires_mode),
		"reward_items": _reward_item_views(quest, resource),
		"turn_in_giver": String(quest.turn_in_giver_key()),
		"turn_in_name": quest.turn_in_label(),
	}


func _reward_item_views(quest: QuestResource, resource: PlayerResource) -> Array:
	var out: Array = []
	for reward: QuestReward in quest.reward_items:
		if reward and reward.item:
			out.append({
				"name": str(reward.item.item_name),
				"amount": reward.amount,
			})
	var style_weapon: Item = quest.pick_style_weapon_for(resource)
	if style_weapon:
		out.append({
			"name": str(style_weapon.item_name),
			"amount": 1,
		})
	return out


## Quest-name list of prerequisites the player hasn't turned in yet.
func _unmet_prereq_names(
	resource: PlayerResource,
	quest: QuestResource
) -> Array:
	if resource.quest_state(int(quest.get_meta(&"id", 0))) != &"":
		return []
	var names: Array = []
	for prereq: QuestResource in quest.requires_quests:
		if prereq == null:
			continue
		var prereq_id: int = int(prereq.get_meta(&"id", 0))
		if (
			prereq_id <= 0
			or resource.quest_state(prereq_id) != &"turned_in"
		):
			names.append(str(prereq.quest_name))
	return names
