extends DataRequestHandler
## Click-open for a LootChest prop. Grants rolled loot to the opener's bag.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.is_dead:
		return {"ok": false, "reason": "missing"}

	var prop_id: int = int(args.get("prop_id", -1))
	if prop_id < 0:
		return {"ok": false, "reason": "missing"}

	var map: Map = instance.instance_map
	if map == null or map.replicated_props_container == null:
		return {"ok": false, "reason": "no_map"}

	var container: ReplicatedPropsContainer = map.replicated_props_container
	var node: Node = container.dynamic_nodes.get(prop_id, null)
	if node == null or not node.has_method(&"try_open"):
		return {"ok": false, "reason": "missing"}

	return node.try_open(player)
