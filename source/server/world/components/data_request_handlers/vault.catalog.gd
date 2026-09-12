extends DataRequestHandler
## What the Vault sells, with this character's ownership stamped on each row.
## Synchronous and cheap - no web call. The UI reads costs from here, so a client
## never sends a price, only a token.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "no_player"}
	var pr: PlayerResource = player.player_resource

	var rows: Array = []
	for entry: Dictionary in PremiumCatalog.roster():
		var row: Dictionary = entry.duplicate()
		row["owned"] = PremiumCatalog.owns(pr, entry)
		rows.append(row)
	return {
		"ok": true,
		# Purchasing needs a linked web account. Saying so up front lets the UI
		# explain itself instead of failing on the first click.
		"purchasable": not pr.account_name.strip_edges().is_empty(),
		"items": rows,
	}
