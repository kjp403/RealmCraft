extends DataRequestHandler
## Roster for the Vault Skins tab. Staff-only; empty roster for everyone else
## so prestige recolors never leak. vault_skins.equip re-checks independently.


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
			"skins": [],
			"archives": [],
			"equipped": 0,
		}
	return {
		"ok": true,
		"allowed": true,
		"skins": VaultSkins.roster(VaultSkins.GROUP_WARDROBE),
		"archives": VaultSkins.roster(VaultSkins.GROUP_ARCHIVES),
		"equipped": pr.vault_skin_id,
	}
