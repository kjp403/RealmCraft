extends DataRequestHandler
## Roster for the Vault Titles shelf. Staff-only; empty roster for everyone else
## so the unreleased shop set does not leak. titles.equip re-checks independently.


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
		return {"ok": true, "allowed": false, "titles": [], "equipped": ""}
	return {
		"ok": true,
		"allowed": true,
		"titles": TitleCatalog.premium_roster(),
		"equipped": pr.display_title,
	}
