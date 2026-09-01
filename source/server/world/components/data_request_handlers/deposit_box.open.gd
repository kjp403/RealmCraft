extends DataRequestHandler
## Open a Portable Deposit Box the caller set down. Args: {prop_id: int}.
##
## Resolved off the map's replicated-props container by prop id, the way
## [code]chest.open[/code] and [code]peddler.vault[/code] are — the prop owns the
## ownership and range gates, this handler is the routing and the payload.
##
## The payload is deliberately the SAME shape [code]bank.get[/code] returns, so
## the client opens the bank window it already has rather than a second vault UI
## that would drift from it. Everything after opening (deposit / withdraw /
## upgrade) goes through the existing bank handlers, which read the caller's own
## PlayerResource and never the box — so the box cannot become a way to reach
## somebody else's vault even if this gate were wrong.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}

	var prop_id: int = int(args.get("prop_id", -1))
	if prop_id < 0:
		return {"ok": false, "reason": "missing"}

	var map: Map = instance.instance_map
	if map == null or map.replicated_props_container == null:
		return {"ok": false, "reason": "no_map"}

	var node: Node = map.replicated_props_container.dynamic_nodes.get(prop_id, null)
	if node == null or not (node is PortableDepositBox):
		# The box packs itself up after two minutes, so a stale click is the
		# ordinary case rather than an error.
		return {"ok": false, "reason": "expired"}

	var refusal: Dictionary = (node as PortableDepositBox).refusal_for(player)
	if not refusal.is_empty():
		return refusal

	var pr: PlayerResource = player.player_resource
	return {
		"ok": true,
		"inventory": pr.inventory,
		"inventory_bags": pr.inventory_bags,
		"active_bag": pr.active_inventory_bag,
		"bank": pr.bank,
		"bank_slots": maxi(BankInteraction.STARTING_SLOTS, pr.bank_slots),
	}
