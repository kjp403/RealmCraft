extends DataRequestHandler
## Price the Wayfarer's board for ONE player. Args: {npc: node_name}.
##
## The client never computes a fare. Surge depends on server-held ride history,
## and the gates depend on wardstones the client only mirrors, so the window is
## drawn entirely from this reply — which also means the prices a player sees are
## by construction the prices [code]travel.quick[/code] will charge.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var desk_ctx: Dictionary = QuickTravelDesk.resolve(peer_id, instance, args)
	if desk_ctx.has("reason"):
		return {"ok": false, "reason": desk_ctx["reason"]}

	var player: Player = desk_ctx["player"]
	var desk: QuickTravelInteraction = desk_ctx["desk"]
	var pr: PlayerResource = player.player_resource
	var player_id: int = pr.player_id
	# A scroll ride is free and does not touch the surge window, so every fare on
	# this board is zero and every row is affordable. Priced here rather than in
	# the window: the client has never computed a fare and must not start now.
	var scroll: bool = bool(desk_ctx.get("scroll", false))
	var gold_id: int = Economy.gold_id()
	var gold: int = Inventory.count(pr.inventory, gold_id) if gold_id > 0 else 0

	var rows: Array = []
	for i: int in desk.destinations.size():
		var dest: QuickTravelDestination = desk.destinations[i]
		if dest == null or dest.target_instance == null:
			continue # empty array slot authored by mistake — don't sell a ticket to nowhere
		var fee: int = 0 if scroll else QuickTravelService.fee_for(player_id, dest.fee)
		rows.append({
			"index": i,
			"label": dest.display_label(),
			"blurb": dest.blurb,
			"base_fee": dest.fee,
			"fee": fee,
			# True when the surge pushed this fare into the price ceiling, so the
			# board can say "fare cap" instead of showing a rise that isn't there.
			"capped": (not scroll) and QuickTravelService.uncapped_fee_for(player_id, dest.fee) > fee,
			"lock": QuickTravelDesk.lock_reason(player, instance, dest),
			"affordable": scroll or gold >= fee,
		})

	return {
		"ok": true,
		"gold": gold,
		"destinations": rows,
		# The window labels itself off this rather than off the arg it sent, so a
		# board that opened as a scroll but resolved as a desk cannot draw "free".
		"scroll": scroll,
		# Surge readout for the window's header.
		"surge": QuickTravelService.multiplier(player_id),
		"rides": QuickTravelService.rides_in_window(player_id),
		"free_rides": QuickTravelService.SURGE_AFTER_TRIPS,
		"fare_cap": QuickTravelService.FARE_CAP,
		"window_s": int(QuickTravelService.WINDOW_S),
		"cools_in_s": QuickTravelService.seconds_until_step_down(player_id),
	}
