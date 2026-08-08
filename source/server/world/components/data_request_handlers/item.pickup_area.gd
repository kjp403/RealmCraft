extends DataRequestHandler
## Area-loot: pick up every GroundItem in range that is free OR reserved to this
## peer. Bound to player_interact (F) on the client.


const AREA_RANGE: float = 96.0


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.is_dead:
		return {"ok": false, "reason": "missing", "picked": 0}

	var map: Map = instance.instance_map
	if map == null or map.replicated_props_container == null:
		return {"ok": false, "reason": "no_map", "picked": 0}

	var container: ReplicatedPropsContainer = map.replicated_props_container
	var picked: int = 0
	var names: PackedStringArray = PackedStringArray()
	# Snapshot keys — try_pickup despawns and mutates dynamic_nodes.
	var prop_ids: Array = container.dynamic_nodes.keys()
	for prop_id: Variant in prop_ids:
		var node: Node = container.dynamic_nodes.get(prop_id, null)
		# Prefer duck-typing so a missing class_name never breaks F-loot parse.
		if node == null or not node.has_method(&"try_pickup"):
			continue
		if player.global_position.distance_to(node.global_position) > AREA_RANGE:
			continue
		var result: Dictionary = node.call(&"try_pickup", player)
		if bool(result.get("ok", false)):
			picked += 1
			var display: String = str(result.get("name", "item"))
			if not names.has(display):
				names.append(display)

	return {
		"ok": picked > 0,
		"picked": picked,
		"names": names,
		"reason": "" if picked > 0 else "none",
	}
