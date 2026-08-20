extends DataRequestHandler
## Travel via a WarpInteraction NPC. Args: {npc: node_name}. Resolves the NPC
## (including under Hub/NPCs/), range-checks, then switches instance the same way
## a Warper would — including wardstone gating and jail lock.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.is_dead:
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

	var warp: WarpInteraction = _warp_of(npc)
	if warp == null or warp.target_instance == null:
		return {"ok": false, "reason": "no_warp"}

	# Skill gate (Beach Angler -> Deep Shoals needs Fishing 60). Authoritative
	# here; WarpInteraction.menu_entry only greys the option out client-side.
	if not warp.required_skill.is_empty():
		var have: int = int(
			(player.player_resource.skills.get(
				warp.required_skill,
				player.player_resource.skills.get(String(warp.required_skill), {})
			) as Dictionary).get("level", 1)
		)
		if have < warp.required_skill_level:
			WorldServer.curr.chat_service.push_system_to_player(
				instance, player.player_resource.player_id,
				"You need %s %d to go there." % [
					JobRegistry.display_name(warp.required_skill), warp.required_skill_level
				]
			)
			return {"ok": false, "reason": "skill_level"}

	var target_res: InstanceResource = warp.target_instance
	if not target_res.can_join_instance(player):
		var stone: String = String(target_res.required_wardstone)
		WorldServer.curr.chat_service.push_system_to_player(
			instance, player.player_resource.player_id,
			"You need the %s wardstone to travel there." % stone.replace("_", " ")
		)
		return {"ok": false, "reason": "wardstone"}

	var manager: InstanceManagerServer = WorldServer.curr.instance_manager
	if manager == null:
		return {"ok": false, "reason": "no_manager"}

	var target_instance: ServerInstance = target_res.get_instance()
	if target_instance:
		manager.player_switch_instance(target_instance, warp.target_id, player, instance)
	else:
		manager.queue_charge_instance(
			target_res,
			manager.player_switch_instance.bind(warp.target_id, player, instance)
		)
	return {"ok": true}


func _warp_of(npc: NPC) -> WarpInteraction:
	if npc.npc_resource == null:
		return null
	for inter: NPCInteraction in npc.npc_resource.interactions:
		if inter is WarpInteraction:
			return inter as WarpInteraction
	return null
