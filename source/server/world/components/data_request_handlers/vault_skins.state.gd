extends DataRequestHandler
## Staff-only. Catalog lives on the client (VaultSkins). This just answers
## whether Wear is allowed and which packed id is equipped.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var pr: PlayerResource = player.player_resource
	var allowed: bool = CommandPermissions.effective_priority(pr, instance) \
			>= CommandPermissions.STAFF_PROTECT_PRIORITY
	if not allowed:
		return {
			"ok": true,
			"allowed": false,
			"equipped": 0,
		}
	return {
		"ok": true,
		"allowed": true,
		"equipped": pr.vault_skin_id,
	}
