extends DataRequestHandler
## Snapshot of the player's current Slayer task + this master's flavor, for the
## Slayer menu opened from a SlayerInteraction NPC.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}
	if instance == null or instance.instance_map == null:
		return {"ok": false, "reason": "no_map"}

	var master_key: StringName = StringName(str(args.get("master", "")))
	var source: Object = instance.instance_map.get_slayer_master(master_key)
	if source == null or source.get("master") == null:
		return {"ok": false, "reason": "no_master"}

	var owner_npc: Node = source.get("_owner") as Node
	if owner_npc == null or not is_instance_valid(owner_npc):
		return {"ok": false, "reason": "no_master"}
	if player.global_position.distance_to(owner_npc.global_position) > 120.0:
		return {"ok": false, "reason": "too_far"}

	var master: SlayerMasterResource = source.master
	var payload: Dictionary = SlayerTaskService.status_payload(player.player_resource)
	payload["ok"] = true
	payload["master_key"] = String(master_key)
	payload["master_name"] = str(source.get("master_name"))
	payload["greeting"] = master.greeting
	payload["free_reassign"] = master.free_reassign
	payload["reassign_point_cost"] = master.reassign_point_cost
	payload["min_slayer_level"] = master.min_slayer_level
	payload["base_points_per_task"] = master.base_points_per_task
	return payload
