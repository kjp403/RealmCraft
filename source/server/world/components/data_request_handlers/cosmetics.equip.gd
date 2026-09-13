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
		# Staff OR bought. Without the second half a paying player owns a
		# cosmetic they can never wear.
		var staff: bool = CommandPermissions.effective_priority(pr, instance) >= CommandPermissions.STAFF_PROTECT_PRIORITY
		if not staff and not VaultGrants.has_cosmetic(pr, cosmetic_id):
			return {"ok": false, "reason": "not_allowed"}
		if not Cosmetics.is_valid(cosmetic_id):
			return {"ok": false, "reason": "unknown_cosmetic"}

	# EVERY SLOT IS INDEPENDENT. An aura, a halo and a trail render together, and
	# the two event slots are not worn at all - so equipping any one of them must
	# never evict another. Clearing (id 0) needs the caller to say WHICH slot,
	# since 0 has no slot of its own.
	var slot: StringName = Cosmetics.slot_of(cosmetic_id)
	if cosmetic_id == 0:
		slot = StringName(str(args.get("slot", "")))
	if not Cosmetics.SLOTS.has(slot):
		return {"ok": false, "reason": "unknown_slot"}

	if cosmetic_id == 0:
		pr.cosmetic_slots.erase(slot)
	else:
		pr.cosmetic_slots[slot] = cosmetic_id

	# The worn channels are mirrored onto synced properties so every client
	# in the zone renders them. Flourish and departure have no channel: nothing
	# wears them, they are looked up at the moment they fire.
	match slot:
		&"weapon":
			pr.weapon_cosmetic_id = cosmetic_id
			player.state_synchronizer.set_by_path(^":weapon_cosmetic_id", cosmetic_id)
		&"aura":
			# Still a real column, because the profile row reads it.
			pr.cosmetic_id = cosmetic_id
			player.state_synchronizer.set_by_path(^":cosmetic_id", cosmetic_id)
		&"halo":
			player.state_synchronizer.set_by_path(^":halo_cosmetic_id", cosmetic_id)
		&"trail":
			player.state_synchronizer.set_by_path(^":trail_cosmetic_id", cosmetic_id)
		&"pet":
			player.state_synchronizer.set_by_path(^":pet_cosmetic_id", cosmetic_id)
	# Persisted now that cosmetics can be BOUGHT. While the only path in was
	# an admin command this could stay transient; a purchase that does not
	# survive logout is a refund request.
	instance.world_server.database.save_player(pr)
	return {"ok": true, "cosmetic_id": cosmetic_id, "slot": slot}
