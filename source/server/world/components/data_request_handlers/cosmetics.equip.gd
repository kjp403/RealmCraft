extends DataRequestHandler
## Equip (or clear) a cosmetic VFX. Sets the persisted cosmetic_id and pushes the synced
## :cosmetic_id path so every client spawns the effect live (Character._set_cosmetic_id),
## mirroring wardrobe.equip.
##
## THE GATE LIVES HERE. Cosmetics are unreleased and have no purchase path, so the only
## thing standing between a player and the whole set is this check — it must stay on the
## server and must re-run on EVERY call (rank can be revoked mid-session). Requirements:
##   - caller is admin+ (CommandPermissions, which already ignores DB-held owner /
##     senior_admin on live and honours AdminConfig), and
##   - the id exists in the `cosmetics` registry (0 = unequip, always allowed).
## When the Horizon Collection ships, add an ownership check alongside the rank check
## rather than replacing it — staff still want the whole roster for testing.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var pr: PlayerResource = player.player_resource

	var cosmetic_id: int = int(args.get("cosmetic_id", 0))

	# Unequipping is always permitted — a demoted admin must be able to take theirs off,
	# and it can never grant anything.
	if cosmetic_id != 0:
		if CommandPermissions.effective_priority(pr, instance) \
				< CommandPermissions.STAFF_PROTECT_PRIORITY:
			return {"ok": false, "reason": "not_allowed"}
		if not Cosmetics.is_valid(cosmetic_id):
			return {"ok": false, "reason": "unknown_cosmetic"}

	pr.cosmetic_id = cosmetic_id
	# Propagate to all clients (including others) so the effect appears live.
	player.state_synchronizer.set_by_path(^":cosmetic_id", cosmetic_id)
	return {"ok": true, "cosmetic_id": cosmetic_id}
