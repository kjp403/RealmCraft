extends DataRequestHandler
## Click-open for the Peddler's Vault Chest. Args: {prop_id: int}.
##
## Resolved off the map's replicated-props container by prop id, exactly the way
## [code]chest.open[/code] resolves a LootChest — the node itself owns the key
## check, the payout and the range gate, so this handler is only the routing.


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

	var node: Node = map.replicated_props_container.dynamic_nodes.get(prop_id, null)
	if node == null or not (node is PeddlerVaultChest):
		# The vault despawns with the cart, so a stale click is the ordinary case.
		return {"ok": false, "reason": "closed"}

	return (node as PeddlerVaultChest).try_open(player)
