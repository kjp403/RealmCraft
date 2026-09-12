class_name PremiumApi
## The only place the world server talks to the Arkenelle premium backend.
##
## Shaped after [PeddlerHttp] and inheriting its three rules - never block, never
## throw, never leak - with one difference that drives the whole design: this one
## needs the RESPONSE. Money moves on the far side, so "fire and forget" is not
## available and every call ends in a callback that says what happened.
##
## WHY THIS IS NOT AWAITED BY ITS CALLER. A data request handler's return value is
## fed straight into `_data_response(... data: Dictionary)` (world_server.gd). A
## handler containing `await` returns a Signal there, not a Dictionary, and the
## response silently breaks. Nothing in the handler tree awaits, and this must not
## be the first. Callers ack synchronously and take the result on a callback.
##
## THE SECRET NEVER APPEARS IN A LOG. Not the key, not the URL, not the body.
## Failures log a result code and an HTTP status and nothing else.

const URL_ENV: String = "ARKENELLE_PREMIUM_API_URL"
const KEY_ENV: String = "ARKENELLE_PREMIUM_API_KEY"

## Longer than the client's 5s request timeout ON PURPOSE. The client is acked
## immediately and told to wait for a push, so this is free to outlive it; the
## alternative - trimming to fit the client - would abandon paid transactions.
const TIMEOUT_S: float = 8.0

const BALANCE_PATH: String = "/v1/premium/balance"
const PURCHASE_PATH: String = "/v1/premium/purchase"


## True when both halves of the config are present. False is the normal state on
## a dev machine and must read as "off", never as "broken".
static func is_configured() -> bool:
	return not OS.get_environment(URL_ENV).strip_edges().is_empty() \
		and not OS.get_environment(KEY_ENV).strip_edges().is_empty()


## Current premium balance for [param user_id] (PlayerResource.account_name).
##
## [param on_done] receives one result Dictionary - see [method _result]. POST
## rather than GET so the account name travels in the body and never in a URL
## that a proxy or an access log would keep.
static func fetch_premium_balance(
	host: Node,
	user_id: String,
	on_done: Callable
) -> bool:
	return _post(
		host,
		BALANCE_PATH,
		{"user_id": user_id},
		"",
		"Premium balance",
		on_done
	)


## Debit [param cost] from [param user_id] for [param item_id].
##
## [param transaction_id] is the idempotency key: it is sent as a header AND in
## the body so a retry - ours or a proxy's - settles once. The backend is the
## authority on price; [param cost] is what the server believes and is expected
## to be re-validated there, not trusted.
static func execute_vault_purchase(
	host: Node,
	user_id: String,
	item_id: String,
	cost: int,
	transaction_id: String,
	on_done: Callable
) -> bool:
	return _post(
		host,
		PURCHASE_PATH,
		{
			"user_id": user_id,
			"item_id": item_id,
			"cost": cost,
			"transaction_id": transaction_id,
		},
		transaction_id,
		"Premium purchase",
		on_done
	)


## Every result is this shape, success or failure, so callers never branch on
## whether a key exists:
##   {"ok": bool, "status": int, "reason": String, "data": Dictionary}
static func _result(ok: bool, status: int, reason: String, data: Dictionary) -> Dictionary:
	return {"ok": ok, "status": status, "reason": reason, "data": data}


static func _post(
	host: Node,
	path: String,
	body: Dictionary,
	idempotency_key: String,
	label: String,
	on_done: Callable
) -> bool:
	var base: String = OS.get_environment(URL_ENV).strip_edges()
	var key: String = OS.get_environment(KEY_ENV).strip_edges()
	if base.is_empty() or key.is_empty():
		_settle(on_done, _result(false, 0, "not_configured", {}))
		return false
	if host == null or not host.is_inside_tree():
		_settle(on_done, _result(false, 0, "no_host", {}))
		return false

	var request: HTTPRequest = HTTPRequest.new()
	request.timeout = TIMEOUT_S
	# Keeps the socket and the TLS handshake off the main loop. That loop ticks
	# combat; a slow payment API must not be able to stutter a fight.
	request.use_threads = true
	host.add_child(request)
	request.request_completed.connect(
		func(
			result: int,
			code: int,
			_headers: PackedStringArray,
			raw: PackedByteArray
		) -> void:
			request.queue_free()
			_settle(on_done, _interpret(result, code, raw, label))
	)

	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		# Server-to-server bearer. This is what tells the backend the request came
		# from the authoritative world server and not from a client.
		"Authorization: Bearer " + key,
	])
	if not idempotency_key.is_empty():
		headers.append("Idempotency-Key: " + idempotency_key)

	var error: Error = request.request(
		base.rstrip("/") + path,
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if error != OK:
		# A malformed URL or an exhausted socket pool. request_completed will
		# never fire, so this node has to be freed here or it leaks for the life
		# of the process.
		request.queue_free()
		ServerLog.warn("%s could not start (error %d)." % [label, error])
		_settle(on_done, _result(false, 0, "start_failed", {}))
		return false
	return true


## Transport result + HTTP status + body -> one typed outcome.
static func _interpret(
	result: int,
	code: int,
	raw: PackedByteArray,
	label: String
) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		var transport: String = "timeout" if result == HTTPRequest.RESULT_TIMEOUT else "network"
		ServerLog.warn("%s transport failure (result %d)." % [label, result])
		return _result(false, 0, transport, {})

	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary):
		# A 200 we cannot read is NOT a success: treating it as one would grant an
		# entitlement on the strength of an error page.
		ServerLog.warn("%s returned unparseable JSON (HTTP %d)." % [label, code])
		return _result(false, code, "bad_json", {})
	var data: Dictionary = parsed as Dictionary

	if code >= 200 and code < 300:
		return _result(true, code, "", data)

	# The backend's own reason wins when it gives one - it knows "insufficient
	# funds" from "already settled" and we do not. Status is the fallback.
	var server_reason: String = str(data.get("reason", "")).strip_edges()
	if server_reason.is_empty():
		server_reason = _reason_for_status(code)
	ServerLog.warn("%s rejected (HTTP %d, %s)." % [label, code, server_reason])
	return _result(false, code, server_reason, data)


static func _reason_for_status(code: int) -> String:
	match code:
		401, 403:
			return "unauthorized"
		402:
			return "insufficient_funds"
		404:
			return "unknown_item"
		409:
			return "duplicate"
		429:
			return "rate_limited"
	if code >= 500:
		return "backend_error"
	return "rejected"


## One exit point, so a freed caller can never turn a payment outcome into a
## crash in the HTTP completion signal.
static func _settle(on_done: Callable, payload: Dictionary) -> void:
	if on_done.is_valid():
		on_done.call(payload)
