class_name PeddlerHttp
## The one place the Peddler talks to the outside world.
##
## Both outbound calls — the website snapshot and the Discord announcement — are
## the same shape: fire a JSON POST, do not wait for it, never let it matter.
## Sharing the plumbing means the rules below are written once and cannot drift
## between them.
##
## THREE RULES, and every caller inherits them:
##
##   1. NEVER BLOCK. [member HTTPRequest.use_threads] keeps the socket and the
##      TLS handshake off the main loop. That loop ticks combat; a slow webhook
##      must not be able to stutter a fight.
##   2. NEVER THROW. Every failure is a warn-and-return. A Discord outage cannot
##      be allowed to break a spawn.
##   3. NEVER LEAK. One request node per call, freed in the completion signal —
##      and freed by hand on the paths where that signal will never arrive,
##      because a node leaked per event grows the tree for the life of the
##      process.
##
## Fire-and-forget with no retry queue is deliberate. Every message this sends is
## a snapshot of a state that is re-sent on the next event, so a dropped POST
## self-heals within a cycle. A queue would be more machinery guarding less.

## Seconds before a request is abandoned. Short: this is telemetry and chat, and
## a call still in flight when the next event fires is worth less than the new one.
const TIMEOUT_S: float = 8.0


## POST [param body] as JSON to [param url], parented under [param host].
## [param label] names the caller in any warning, so one log line says which of
## the two integrations failed.
##
## Returns false when the call could not be STARTED. A true return means the
## request is in flight, not that it succeeded — nothing here waits to find out.
static func post_json(
	host: Node,
	url: String,
	body: Dictionary,
	label: String,
	extra_headers: PackedStringArray = PackedStringArray()
) -> bool:
	if host == null or not host.is_inside_tree() or url.is_empty():
		return false

	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = TIMEOUT_S
	request.use_threads = true
	host.add_child(request)
	request.request_completed.connect(
		func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
			# Log the failure WITHOUT the body or the URL: a Discord webhook URL
			# is itself a credential, and the payload can carry anything.
			if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
				ServerLog.warn("%s failed (result %d, HTTP %d)." % [label, result, code])
			request.queue_free()
	)

	var headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"])
	headers.append_array(extra_headers)
	var error: Error = request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		# A malformed URL or an exhausted socket pool. The completion signal will
		# never fire, so this node has to be freed here or it is a permanent leak.
		ServerLog.warn("%s could not start (error %d)." % [label, error])
		request.queue_free()
		return false
	return true
