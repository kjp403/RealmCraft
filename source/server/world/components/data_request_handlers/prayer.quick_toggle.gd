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

	# {"slug", "reason"} per skip, not just the slug -- no_points, prayer_level
	# (a starred pick the player has since fallen under, e.g. a respec) and
	# unknown_prayer (a starred slug retired from PrayerBook; QuickPrayers is a
	# client-local preference the server never prunes) are all real, distinct
	# causes, and collapsing them into one generic "not enough points" message
	# blames the pool for something that was never about points.
	var skipped: Array[Dictionary] = []
	if want_on:
		for slug: StringName in slugs:
			var result: Dictionary = PrayerService.activate(player, slug)
			if bool(result.get("ok", false)):
				continue
			skipped.append({"slug": String(slug), "reason": str(result.get("reason", ""))})
			if str(result.get("reason", "")) == "no_points":
				break # pool is dry -- further attempts would just repeat the refusal
	else:
		for slug: StringName in slugs:
			PrayerService.deactivate(player, slug)

	var status: Dictionary = PrayerService.status(player)
	status["ok"] = true
	# Reported against the FINAL snapshot, not "which activate() calls
	# returned ok" -- two starred prayers that conflict with each other (same
	# exclusive_groups entry) each report ok in turn, but activating the
	# second one silently switches the first back off, so trusting the raw
	# per-call results would list both as active when only one really is.
	var active_now: Array = status.get("active", [])
	var activated: Array[String] = []
	for slug: StringName in slugs:
		if active_now.has(String(slug)):
			activated.append(String(slug))
	status["activated"] = activated
	status["skipped"] = skipped
	return status
