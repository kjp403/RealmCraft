extends DataRequestHandler
## State for the Vault Dyes shelf. The catalog itself lives on the client
## ([VaultSkins]) because it is pure presentation - 16 bodies x 36 recolours,
## derived, with nothing the server needs to agree about. What the server owns is
## WHO MAY WEAR WHAT, which is this.
##
## No visibility filter, unlike the titles and cosmetics shelves: every packed id
## in the catalog is for sale, so a shopper browsing all of them is the shop
## working rather than a leak. Ownership is what gates Wear.
##
## `allowed` means "may wear anything" - staff. vault_skins.equip re-checks
## independently.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	_args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var pr: PlayerResource = player.player_resource
	var staff: bool = CommandPermissions.effective_priority(pr, instance) \
			>= CommandPermissions.STAFF_PROTECT_PRIORITY

	# Straight off the entitlement list rather than probed id by id: the catalog
	# is 576 pairings and all but a handful will always be unowned.
	var owned: Array[int] = []
	for token: String in pr.granted_vfx:
		if token.begins_with(VaultGrants.SKIN_PREFIX):
			var packed: int = int(token.substr(VaultGrants.SKIN_PREFIX.length()))
			if packed > 0:
				owned.append(packed)

	return {
		"ok": true,
		"allowed": staff,
		"owned": owned,
		"equipped": pr.vault_skin_id,
	}
