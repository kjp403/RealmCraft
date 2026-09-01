extends DataRequestHandler
## Book one Wayfarer ride. Args: {npc: node_name, index: int}.
##
## Authoritative for BOTH the gates and the price — [code]travel.quote[/code] is
## display only, and nothing it returned is trusted here. The client sends a
## ticket index; everything else is re-derived.
##
## ORDER MATTERS. Every gate (alive, jailed, in range, real destination, not
## already there, wardstone) is cleared BEFORE a coin is touched, and the ride is
## only recorded against the surge window after the transfer is committed. So a
## refused ride is always free, and a refused ride never pushes the player into a
## higher fare tier.
##
## The transfer itself reuses InstanceManagerServer.player_switch_instance — the
## same call warpers and npc.warp make — rather than moving the player by
## coordinates. That is what keeps the spawn point valid, the camera limits
## re-derived and the instance bookkeeping (dungeon/spar/hunt cleanup) correct;
## a hand-written position set would silently skip all of it.


func data_request_handler(peer_id: int, instance: ServerInstance, args: Dictionary) -> Dictionary:
	var desk_ctx: Dictionary = QuickTravelDesk.resolve(peer_id, instance, args)
	if desk_ctx.has("reason"):
		var why: String = desk_ctx["reason"]
		if why == "jailed":
			_tell(instance, desk_ctx, "You are jailed and cannot leave this area.")
		return {"ok": false, "reason": why}

	var player: Player = desk_ctx["player"]
	var desk: QuickTravelInteraction = desk_ctx["desk"]
	var pr: PlayerResource = player.player_resource

	var dest: QuickTravelDestination = desk.destination_at(int(args.get("index", -1)))
	if dest == null or dest.target_instance == null:
		return {"ok": false, "reason": "bad_destination"}

	var lock: String = QuickTravelDesk.lock_reason(player, instance, dest)
	if not lock.is_empty():
		_system(instance, pr, lock)
		return {"ok": false, "reason": "locked", "lock": lock}

	var manager: InstanceManagerServer = WorldServer.curr.instance_manager
	if manager == null:
		return {"ok": false, "reason": "no_manager"}

	# --- Fare. Priced now, at the moment of purchase, from live surge state. ---
	var player_id: int = pr.player_id
	var fee: int = QuickTravelService.fee_for(player_id, dest.fee)
	var gold_id: int = Economy.gold_id()
	if gold_id <= 0:
		return {"ok": false, "reason": "no_currency"}
	if fee > 0 and not Inventory.remove_amount_by_id(pr.inventory, gold_id, fee):
		# Insufficient funds: nothing has been spent and nothing has moved.
		return {
			"ok": false,
			"reason": "gold",
			"cost": fee,
			"gold": Inventory.count(pr.inventory, gold_id),
		}

	if fee > 0:
		instance.world_server.database.save_player(pr)
	QuickTravelService.record_ride(player_id)

	var target_res: InstanceResource = dest.target_instance
	var target: ServerInstance = target_res.get_instance()
	if target != null:
		manager.player_switch_instance(target, dest.target_id, player, instance)
	else:
		# Cold map: it has to be charged first, then the same switch runs on ready.
		manager.queue_charge_instance(
			target_res,
			manager.player_switch_instance.bind(dest.target_id, player, instance)
		)

	return {
		"ok": true,
		"paid": fee,
		"gold": Inventory.count(pr.inventory, gold_id),
		"inventory": pr.inventory,
		"destination": dest.display_label(),
		"surge": QuickTravelService.multiplier(player_id),
	}


func _system(instance: ServerInstance, pr: PlayerResource, text: String) -> void:
	WorldServer.curr.chat_service.push_system_to_player(instance, pr.player_id, text)


func _tell(instance: ServerInstance, ctx: Dictionary, text: String) -> void:
	var player: Player = ctx.get("player", null)
	if player != null and player.player_resource != null:
		_system(instance, player.player_resource, text)
