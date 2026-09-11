extends DataRequestHandler
## Cuts raw fish into Fish Bait. `id` names the fish (0 with `all` = every fish),
## `amount` how many (0 = all of that fish).
##
## Nothing here trusts the client's view of the bag: FilletService re-reads the
## inventory, re-checks the knife and re-derives the yield from the FilletTable, so
## a fabricated packet can at most ask for something the player could already do.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}

	var resource: PlayerResource = player.player_resource
	var result: Dictionary
	if bool(args.get("all", false)):
		result = FilletService.fillet_all(resource)
	else:
		result = FilletService.fillet(
			resource, int(args.get("id", 0)), int(args.get("amount", 0))
		)

	# Re-list in the same reply. The panel needs the new rows either way, and a
	# second round trip would let the player click a fish that is already gone.
	if bool(result.get("ok", false)):
		result["rows"] = FilletService.filletable(resource)
	return result
