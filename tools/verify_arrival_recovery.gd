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
