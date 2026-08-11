extends DataRequestHandler
## Reassigns the player's current Slayer task at this master (free / point cost).


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

	var result: Dictionary = SlayerTaskService.skip_task(player.player_resource, source.master)
	if bool(result.get("ok", false)):
		var status: Dictionary = SlayerTaskService.status_payload(player.player_resource)
		status["ok"] = true
		status["master_key"] = String(master_key)
		status["master_name"] = str(source.get("master_name"))
		status["greeting"] = source.master.greeting
		status["free_reassign"] = source.master.free_reassign
		status["reassign_point_cost"] = source.master.reassign_point_cost
		status["min_slayer_level"] = source.master.min_slayer_level
		status["base_points_per_task"] = source.master.base_points_per_task
		status["reassigned"] = result
		return status
	return result
