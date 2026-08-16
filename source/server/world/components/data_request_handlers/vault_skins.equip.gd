extends DataRequestHandler
## Equip (or clear) a prestige vault skin. Staff-only. Does not change Horizon
## skin_id, so Take-off restores the real wardrobe look. Cosmetics stay separate.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var pr: PlayerResource = player.player_resource
	var vault_id: int = int(args.get("vault_skin_id", args.get("skin_id", 0)))

	if vault_id != 0:
		if CommandPermissions.effective_priority(pr, instance) \
				< CommandPermissions.STAFF_PROTECT_PRIORITY:
			return {"ok": false, "reason": "not_allowed"}
		if not VaultSkins.is_valid(vault_id):
			return {"ok": false, "reason": "unknown_skin"}
		pr.vault_skin_id = vault_id
	else:
		pr.vault_skin_id = 0

	player.vault_skin_id = pr.vault_skin_id
	player.state_synchronizer.set_by_path(^":vault_skin_id", pr.vault_skin_id)
	instance.world_server.database.save_player(pr)
	return {
		"ok": true,
		"skin_id": pr.vault_skin_id,
		"vault_skin_id": pr.vault_skin_id,
	}
