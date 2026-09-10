extends DataRequestHandler
## Client → server: "I have a map loaded and I was never spawned into it."
##
## Last-resort recovery for a stranded arrival — the recurring "null spawn, had
## to relog". InstanceClient re-asks its OWN instance first
## (ready_to_enter_instance); this runs when that goes unanswered, and the
## difference that matters is the address: it is handled by the world server, so
## it still lands when the destination ServerInstance no longer exists. That was
## the unrecoverable case, because every retry was addressed to the dead node.
##
## Deliberately not routed through [param instance] — the dispatcher hands us the
## default instance when the client's id doesn't resolve, and "doesn't resolve"
## is one of the states we are here to fix. We read the id the client sent
## instead, and let InstanceManagerServer decide what it means.


func data_request_handler(peer_id: int, _instance: ServerInstance, args: Dictionary) -> Dictionary:
	# Recovery is idempotent but not free (case 3 re-charges a whole map), and a
	# stuck client re-asks on a timer. One rescue per 5s is plenty to unstick a
	# player and slow enough that a modified client gains nothing by spamming it.
	if not RateLimiter.check(peer_id, &"spawn.rescue", 1, 5_000):
		return {"ok": false, "reason": "rate_limited"}
	var world: WorldServer = WorldServer.curr
	if world == null or world.instance_manager == null:
		return {"ok": false}

	var client_instance: String = str(args.get("instance", ""))
	var action: String = world.instance_manager.rescue_peer(peer_id, client_instance)
	ServerLog.warn(
		"spawn.rescue: peer %d was stranded holding instance '%s' — %s."
		% [peer_id, client_instance, action]
	)
	return {"ok": action != "failed", "action": action}
