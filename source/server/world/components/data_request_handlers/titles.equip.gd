extends DataRequestHandler
## Equip (or clear) a premium Vault title. Unlocks it on this character and
## sets display_title so you can /vault out and wear it in the live world.
## Staff-only. Cosmetics wardrobe is untouched.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if not player:
		return {"ok": false}
	var pr: PlayerResource = player.player_resource
	var title: String = str(args.get("title", "")).strip_edges()

	if not title.is_empty():
		if not TitleCatalog.has_vfx(title):
			return {"ok": false, "reason": "unknown_title"}
		# Canonicalised BEFORE the gate: grant tokens are stored canonical, so
		# checking a raw client string against them would miss every real grant.
		title = TitleCatalog.canonical_name(title)
		# Staff OR bought. Without the second half a paying player owns a title
		# they can never wear.
		var staff: bool = CommandPermissions.effective_priority(pr, instance) >= CommandPermissions.STAFF_PROTECT_PRIORITY
		if not staff and not VaultGrants.has_title(pr, title):
			return {"ok": false, "reason": "not_allowed"}
		var unlocked: PackedStringArray = pr.titles_unlocked.duplicate()
		if not unlocked.has(title):
			unlocked.append(title)
			pr.titles_unlocked = unlocked
		pr.display_title = title
	else:
		pr.display_title = ""

	player.display_title = pr.display_title
	player.state_synchronizer.set_by_path(^":display_title", pr.display_title)
	instance.world_server.database.save_player(pr)
	return {"ok": true, "title": pr.display_title}
