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
		if CommandPermissions.effective_priority(pr, instance) \
				< CommandPermissions.STAFF_PROTECT_PRIORITY:
			return {"ok": false, "reason": "not_allowed"}
		if not TitleCatalog.is_premium_name(title):
			return {"ok": false, "reason": "unknown_title"}
		title = TitleCatalog.canonical_name(title)
		var unlocked: PackedStringArray = pr.titles_unlocked.duplicate()
		if not unlocked.has(title):
			unlocked.append(title)
			pr.titles_unlocked = unlocked
		pr.display_title = title
	else:
		pr.display_title = ""

	instance.world_server.database.save_player(pr)
	return {"ok": true, "title": pr.display_title}
