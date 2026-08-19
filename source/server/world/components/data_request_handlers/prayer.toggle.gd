extends DataRequestHandler
## Switch one prayer on or off. The client sends the SLUG, never an index, so a
## stale client cannot toggle a different prayer than the one it drew.


func data_request_handler(
	peer_id: int,
	instance: ServerInstance,
	args: Dictionary
) -> Dictionary:
	var player: Player = instance.players_by_peer_id.get(peer_id, null)
	if player == null or player.player_resource == null:
		return {"ok": false, "reason": "missing"}
	if player.is_dead:
		return {"ok": false, "reason": "dead"}

	var slug: StringName = StringName(str(args.get("prayer", "")))
	if slug.is_empty():
		return {"ok": false, "reason": "unknown_prayer"}

	# `on` absent means "flip it" — the button does not have to track state.
	var want_on: bool = bool(args.get("on", not PrayerService.is_active(player, slug)))
	var result: Dictionary = (
		PrayerService.activate(player, slug) if want_on
		else PrayerService.deactivate(player, slug)
	)
	# Always return the fresh snapshot, even on refusal: the client redraws from
	# it, so a rejected toggle self-corrects instead of showing a stuck button.
	result.merge(PrayerService.status(player), true)
	return result
