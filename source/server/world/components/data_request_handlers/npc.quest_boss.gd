extends DataRequestHandler
## Quest giver sends the caller into a private story-boss room.
## Args: {npc: node_name}.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.is_dead or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}

	if JailList.is_jailed(player.player_resource.account_name):
		WorldServer.curr.chat_service.push_system_to_player(
			instance, player.player_resource.player_id,
			"You are jailed and cannot leave this area."
		)
		return {"ok": false, "reason": "jailed"}

	var station: String = str(args.get("npc", ""))
	if station.is_empty() or instance.instance_map == null:
		return {"ok": false, "reason": "bad_npc"}

	var npc_node: Node = instance.instance_map.get_node_or_null(NodePath(station))
	if npc_node == null:
		npc_node = instance.instance_map.find_child(station, true, false)
	if npc_node == null or not (npc_node is NPC):
		return {"ok": false, "reason": "npc_missing"}

	var npc: NPC = npc_node as NPC
	if player.global_position.distance_to(npc.global_position) > NPC.INTERACT_RANGE:
		return {"ok": false, "reason": "too_far"}

	var inter: QuestBossInteraction = _interaction_of(npc)
	if inter == null or inter.enemy_type == &"":
		return {"ok": false, "reason": "no_fight"}

	if GroupService.group_of(peer_id) != 0:
		WorldServer.curr.chat_service.push_system_to_player(
			instance, player.player_resource.player_id,
			"Finish your current run first."
		)
		return {"ok": false, "reason": "in_run"}

	if QuestBossService.is_quest_boss_instance(instance):
		return {"ok": false, "reason": "already_in"}

	var gate: StringName = QuestService.kill_gate(player.player_resource, inter.enemy_type)
	if gate == &"already_done":
		return {"ok": false, "reason": "already_done"}
	if gate != &"ok":
		WorldServer.curr.chat_service.push_system_to_player(
			instance, player.player_resource.player_id,
			"Accept the quest first — I will send you when you are ready."
		)
		return {"ok": false, "reason": "no_quest"}

	var origin: Vector2 = npc.global_position
	if not QuestBossService.start_fight(player, instance, origin, inter.enemy_type):
		return {"ok": false, "reason": "busy"}
	return {"ok": true}


func _interaction_of(npc: NPC) -> QuestBossInteraction:
	if npc.npc_resource == null:
		return null
	for inter: NPCInteraction in npc.npc_resource.interactions:
		if inter is QuestBossInteraction:
			return inter as QuestBossInteraction
	return null
