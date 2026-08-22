extends DataRequestHandler
## Batch on/off for a player's "quick prayers" — the prayer bar's Q button. The
## CLIENT decides set MEMBERSHIP (a local preference, like item hotkeys) and
## sends the slugs on every press; the SERVER decides direction: if every slug
## sent is already active, this turns them all off, otherwise it turns on as
## many as points allow (in the order sent) and stops the moment the pool runs
## dry rather than failing the whole click over one prayer that didn't fit.


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

	var raw_slugs: Array = args.get("slugs", [])
	var slugs: Array[StringName] = []
	for entry: Variant in raw_slugs:
		var slug: StringName = StringName(str(entry))
		if not slug.is_empty():
			slugs.append(slug)
	if slugs.is_empty():
		return {"ok": false, "reason": "empty_set"}

	# "on" absent means "flip the set" — on unless every requested prayer is
	# already active, mirroring prayer.toggle's single-prayer flip rule.
	var all_already_on: bool = true
	for slug: StringName in slugs:
		if not PrayerService.is_active(player, slug):
			all_already_on = false
			break
	var want_on: bool = bool(args.get("on", not all_already_on))

	var activated: Array[String] = []
	var skipped: Array[String] = []
	if want_on:
		for slug: StringName in slugs:
			var result: Dictionary = PrayerService.activate(player, slug)
			if bool(result.get("ok", false)):
				activated.append(String(slug))
				continue
			skipped.append(String(slug))
			if str(result.get("reason", "")) == "no_points":
				break # pool is dry -- further attempts would just repeat the refusal
	else:
		for slug: StringName in slugs:
			PrayerService.deactivate(player, slug)

	var status: Dictionary = PrayerService.status(player)
	status["ok"] = true
	status["activated"] = activated
	status["skipped"] = skipped
	return status
