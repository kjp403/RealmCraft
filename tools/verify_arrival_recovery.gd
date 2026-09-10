@tool
extends Node
## Regression gate for the recurring "null spawn, had to relog".
##
## A teleport takes the player OUT of their old instance and leaves them in the
## destination's `awaiting_peers` for the whole span of the client's map load —
## seconds. For that window they are in nobody's `connected_peers`.
## `InstanceManagerServer.unload_unused_instances` reclaims empty instances on a
## 20-second timer and used to count only `connected_peers`, so it routinely
## freed the destination out from under an arriving player. Their
## `ready_to_enter_instance` — and every client-side retry, because those are
## addressed to that same instance — then went to a node the server had deleted.
##
## Asserts the sweeper counts arrivals, and that the client escalates past the
## instance it may no longer be able to reach.
##
## Run: godot --headless --path . tools/verify_arrival_recovery.tscn

var _failures: PackedStringArray = PackedStringArray()


func _ready() -> void:
	_check_sweeper_counts_arrivals()
	_check_client_escalates()
	_check_rescue_handler_exists()
	await _check_sweeper_end_to_end()
	_finish()


## The bug: an instance holding only in-flight arrivals must not be reclaimed.
func _check_sweeper_counts_arrivals() -> void:
	# The regression itself. Nobody is connected yet — one player is walking in.
	_check(
		not InstanceManagerServer.is_reapable(false, 0, 1, false),
		"an instance with a pending ARRIVAL is not reaped (the null-spawn bug)"
	)
	_check(
		InstanceManagerServer.is_reapable(false, 0, 0, false),
		"a genuinely empty instance is still reaped"
	)
	_check(
		not InstanceManagerServer.is_reapable(false, 1, 0, false),
		"an instance with a connected peer is not reaped"
	)
	_check(
		not InstanceManagerServer.is_reapable(true, 0, 0, false),
		"a load_at_startup instance is never reaped"
	)
	_check(
		not InstanceManagerServer.is_reapable(false, 0, 0, true),
		"a pinned instance (quest boss / Peddler) is not reaped"
	)


## Re-asking the instance cannot recover a stranding caused BY that instance
## being gone, so the watcher has to escalate to the world server.
func _check_client_escalates() -> void:
	_check(
		InstanceClient.ENTER_LOCAL_RETRIES < InstanceClient.ENTER_MAX_RETRIES,
		"the arrival watcher escalates before it gives up"
	)
	var source: String = FileAccess.get_file_as_string(
		"res://source/client/network/instance_client.gd"
	)
	_check(
		source.contains("&\"spawn.rescue\""),
		"the arrival watcher escalates to spawn.rescue"
	)


## The dispatcher resolves handlers by FILENAME and loads them lazily, so a
## rename — or a handler that no longer parses — is not an error anywhere. The
## stranded client just gets a polite "unknown_request" and stays stranded.
func _check_rescue_handler_exists() -> void:
	const HANDLER: String = "res://source/server/world/components/data_request_handlers/spawn.rescue.gd"
	if not _check(ResourceLoader.exists(HANDLER), "spawn.rescue is where the dispatcher looks"):
		return
	var script: GDScript = load(HANDLER) as GDScript
	if not _check(script != null, "spawn.rescue parses"):
		return
	var handler: DataRequestHandler = script.new() as DataRequestHandler
	_check(handler != null, "spawn.rescue instantiates as a DataRequestHandler")
	# The recovery itself lives on the manager, reachable without the instance.
	_check(
		InstanceManagerServer.new().has_method(&"rescue_peer"),
		"InstanceManagerServer.rescue_peer exists for it to call"
	)
	_check(
		ServerInstance.new().has_method(&"resend_arrival"),
		"ServerInstance.resend_arrival exists for the re-delivery path"
	)


## The predicate test above only proves the RULE. This runs the real sweeper —
## real ServerInstance nodes, a real InstanceResource, real arrival slots — and
## checks which of them are still alive afterwards. It is the difference between
## testing the fix and testing my opinion of the fix.
##
## Four instances, one per outcome, plus the counterfactual assertion that the
## surviving one is exactly the case the old sweeper would have deleted.
func _check_sweeper_end_to_end() -> void:
	var world: WorldServer = WorldServer.new()
	world.name = "VerifyWorldServer"
	world.multiplayer_api = SceneMultiplayer.new()
	add_child(world)
	ServerInstance.world_server = world

	var manager: InstanceManagerServer = InstanceManagerServer.new()
	manager.name = "VerifyInstanceManager"
	manager.world_server = world
	add_child(manager)

	var res: InstanceResource = load(
		"res://source/common/gameplay/maps/instance/instance_collection/biomes/sewers.tres"
	) as InstanceResource
	if not _check(res != null and not res.load_at_startup, "sewers is a sweepable instance"):
		return

	const ARRIVING: int = 1001    # connected, mid-load: MUST survive
	const DEPARTED: int = 1002    # slot held by a peer who quit: must be reclaimed
	const STUCK: int = 1003       # connected but the slot has aged out: reclaimed
	world.connected_players[ARRIVING] = PlayerResource.new()
	world.connected_players[STUCK] = PlayerResource.new()

	var empty: ServerInstance = _test_instance(manager, res, "Empty")
	var arriving: ServerInstance = _test_instance(manager, res, "Arriving")
	var departed: ServerInstance = _test_instance(manager, res, "Departed")
	var stuck: ServerInstance = _test_instance(manager, res, "Stuck")

	arriving.queue_arrival(ARRIVING, {"target_id": 0})

	# The orphan a real despawn leaves behind: removed from its map, parented to
	# nothing. If dropping the slot doesn't free it, it leaks on every stranding.
	var orphan: Node2D = Node2D.new()
	departed.queue_arrival(DEPARTED, {"player": orphan})

	stuck.queue_arrival(STUCK)
	stuck.awaiting_peers[STUCK]["queued_ms"] = (
		Time.get_ticks_msec() - ServerInstance.ARRIVAL_TTL_MS - 1000
	)

	# The counterfactual. The old sweeper skipped on load_at_startup and on a
	# non-empty connected_peers, and looked at nothing else — so this is exactly
	# the instance it deleted out from under a teleporting player.
	_check(
		arriving.connected_peers.is_empty() and not arriving.instance_resource.load_at_startup,
		"the arriving-player instance is one the OLD sweeper would have freed"
	)

	manager.unload_unused_instances()
	await get_tree().process_frame
	await get_tree().process_frame

	_check(not is_instance_valid(empty), "a truly empty instance is reclaimed")
	_check(is_instance_valid(arriving), "the instance a player is walking into SURVIVES")
	_check(not is_instance_valid(departed), "a slot held by a departed peer is reclaimed")
	_check(not is_instance_valid(stuck), "a slot past ARRIVAL_TTL_MS is reclaimed")
	_check(not is_instance_valid(orphan), "the orphaned player node is freed with its slot")

	# And the survivor must not survive forever — age its slot and sweep again.
	if is_instance_valid(arriving):
		arriving.awaiting_peers[ARRIVING]["queued_ms"] = (
			Time.get_ticks_msec() - ServerInstance.ARRIVAL_TTL_MS - 1000
		)
		manager.unload_unused_instances()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(
			not is_instance_valid(arriving),
			"an arrival that never completes cannot pin its map open forever"
		)

	res.charged_instances.clear()
	manager.queue_free()
	world.queue_free()
	ServerInstance.world_server = null


func _test_instance(
	manager: InstanceManagerServer, res: InstanceResource, label: String
) -> ServerInstance:
	var instance: ServerInstance = ServerInstance.new()
	instance.name = label
	instance.instance_resource = res
	var map: Map = Map.new()
	instance.instance_map = map
	manager.add_child(instance)
	instance.add_child(map)
	return instance


func _check(ok: bool, what: String) -> bool:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
	return ok


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY_PASS")
	else:
		for f: String in _failures:
			printerr("FAIL: %s" % f)
		printerr("VERIFY_FAIL (%d)" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
