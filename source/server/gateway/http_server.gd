extends "res://addons/httpserver/http_server.gd"


const CredentialsUtils: GDScript = preload("res://source/common/utils/credentials_utils.gd")

var next_request_id: int
var sessions: Dictionary[String, Dictionary]
var pending_requests: Dictionary[int, NetRequest]
## Last successful public leaderboard payload. Gateway-side so a busy website
## does not RPC the master on every refresh; the world's heartbeat is already
## the source of truth (~10s).
var _lb_cache: Dictionary = {}
var _lb_cache_ms: int = 0
const LB_CACHE_TTL_MS: int = 8000

## Last peddler snapshot the world server pushed, and when it arrived.
##
## The website's tracker reads this. Held in MEMORY rather than written to disk
## for the same reason the leaderboard cache is: it is a few hundred bytes that
## the world re-sends on its next event, so a restart losing it costs one cycle
## of accuracy and buys no file handling, no permissions and no partial writes.
## A GET is answered straight out of this dict — no RPC, no database, no work.
var _peddler_cache: Dictionary = {}
var _peddler_cache_ms: int = 0
## Env var holding the shared server-to-server secret. Never in the repo.
const PEDDLER_KEY_ENV: String = "ARKENELLE_PEDDLER_WEBHOOK_KEY"
## Shared server-to-server secret for the premium currency routes. The WORLD
## sends it as `Authorization: Bearer`, this gateway compares. Same file, same
## single-source-of-truth shape as the peddler key above.
const PREMIUM_KEY_ENV: String = "ARKENELLE_PREMIUM_API_KEY"
## A snapshot older than this is served with stale=true so the page can say the
## world has gone quiet instead of counting down a cart that is long gone.
const PEDDLER_STALE_MS: int = 15 * 60 * 1000

@onready var gateway_manager_client: GatewayManagerClient = $"../GatewayManagerClient"


func _ready() -> void:
	super._ready()
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/login",
		handle_login
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/guest",
		handle_guest
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/world/character/create",
		handle_character_create
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/world/enter",
		handle_world_enter
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/world/characters",
		handle_world_characters
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/account/create",
		handle_account_creation
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/worlds",
		handle_worlds
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/handshake",
		handle_handshake
	)
	router.register_route(
		HTTPClient.Method.METHOD_GET,
		&"/v1/leaderboards",
		handle_leaderboards
	)
	# The world server POSTs its peddler snapshot here; the website GETs it.
	# Two routes rather than one so the write is authenticated and the read is
	# public — the only asymmetry that matters for a widget nobody logs in to see.
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/peddler/update",
		handle_peddler_update
	)
	router.register_route(
		HTTPClient.Method.METHOD_GET,
		&"/v1/peddler",
		handle_peddler
	)
	# Premium currency. Both are server-to-server (the WORLD calls them over
	# loopback) and both are blocked at Caddy as well as bearer-checked here.
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/premium/balance",
		handle_premium_balance
	)
	router.register_route(
		HTTPClient.Method.METHOD_POST,
		&"/v1/premium/purchase",
		handle_premium_purchase
	)
	# The manager connection remains loopback-only in its own section, while the
	# public HTTP listener can be bound to a private VPN address for closed tests.
	var config_path: String = CmdlineUtils.get_parsed_args().get(
		"config", "res://data/config/gateway_config.cfg"
	)
	var configuration: Dictionary = ConfigFileUtils.load_section("gateway-server", config_path)
	if configuration.has("error"):
		push_error("Gateway HTTP listener could not load %s." % config_path)
		return
	server.listen(
		int(configuration.get("port", 8088)),
		str(configuration.get("bind_address", "127.0.0.1"))
	)
	
	gateway_manager_client.response_received.connect(
		_on_gateway_manager_client_response_received
	)


func create_session(account: Dictionary) -> String:
	var crypto := Crypto.new()
	var bytes: PackedByteArray = crypto.generate_random_bytes(32)
	var session_id: String = Marshalls.raw_to_base64(bytes)
	#session_id
	#account_id
	#created_at
	#last_seen_at
	#expires_at
	sessions[session_id] = account
	return session_id


func send_request(action: String, data: Dictionary, timeout_sec: float = 5.0) -> Dictionary:
	# The link up to the master may not be established yet at cold start. Bail with
	# a connection error rather than firing an RPC at an absent peer (which throws
	# ERR_CONNECTION_ERROR); the client treats this as retryable.
	if not gateway_manager_client.master_connected:
		return {"error": Error.ERR_TIMEOUT, "msg": "gateway not ready"}

	var request_id: int = next_request_id
	next_request_id += 1

	var request: NetRequest = NetRequest.new()
	request.token_id = data.get(GatewayAPI.KEY_TOKEN_ID, 0)
	pending_requests[request_id] = request
	
	data.merge({GatewayAPI.KEY_REQUEST_ID: request_id, "action": action}, true)
	
	gateway_manager_client.gateway_request.rpc_id(1, request_id, data)
	
	get_tree().create_timer(timeout_sec).timeout.connect(
		_on_request_timeout.bind(request_id)
	)
	
	return await request.completed


func _on_request_timeout(request_id: int) -> void:
	var request: NetRequest = pending_requests.get(request_id, null)
	if not request:
		return
	request.resolve({"error": Error.ERR_TIMEOUT, "msg": "request timeout"})


func _on_gateway_manager_client_response_received(request_id: int, response: Dictionary) -> void:
	var request: NetRequest = pending_requests.get(request_id, null)
	if not request:
		return
	request.resolve(response)


# Per-IP throttle for the brute-forceable / spammable auth endpoints. __ip__ is the
# real client even behind Caddy — the HTTP addon reads the X-Real-IP header Caddy
# stamps (header_up X-Real-IP {remote_host}), falling back to the socket host. So
# loopback stays exempt only for local multi-instance testing (no proxy header).
func _rate_ok(payload: Dictionary, endpoint: StringName, max_calls: int, window_ms: int) -> bool:
	var ip: String = str(payload.get("__ip__", ""))
	if ip.is_empty() or ip == "127.0.0.1" or ip == "::1":
		return true
	return AuthRateLimiter.allow(ip, endpoint, max_calls, window_ms)


## Version gate: accept clients in [min_client_version, server_version].
## Exact match still preferred; the min floor stops Deploy-before-Release from
## locking every published client out. Returns {} when OK, else ERR_OUTDATED_VERSION.
## Shared by login + the boot handshake so the two never drift.
func _check_version(payload: Dictionary) -> Dictionary:
	var server_version: String = GatewayAPI.game_version()
	var min_client: String = GatewayAPI.min_client_version()
	var client_version: String = str(payload.get(GatewayAPI.KEY_CLIENT_VERSION, "")).strip_edges()
	var have: String = client_version if not client_version.is_empty() else "unknown"
	if client_version.is_empty():
		return {
			"error": GatewayAPI.ERR_OUTDATED_VERSION,
			"msg": "Outdated game version. Please update. (server %s, you have %s)" % [server_version, have],
		}
	if GatewayAPI.compare_versions(client_version, min_client) < 0:
		return {
			"error": GatewayAPI.ERR_OUTDATED_VERSION,
			"msg": "Outdated game version. Please update. (need %s+, you have %s)" % [min_client, have],
		}
	if GatewayAPI.compare_versions(client_version, server_version) > 0:
		return {
			"error": GatewayAPI.ERR_OUTDATED_VERSION,
			"msg": "Outdated game version. Please update. (server %s, you have %s)" % [server_version, have],
		}
	return {}


## Boot healthcheck (no auth): the gateway client calls this before showing any menu.
## OK only when the build matches AND the master link is up (so a login would land).
func handle_handshake(payload: Dictionary) -> Dictionary:
	var version_check: Dictionary = _check_version(payload)
	if not version_check.is_empty():
		return version_check
	if not gateway_manager_client.master_connected:
		return {"error": Error.ERR_TIMEOUT, "msg": "gateway not ready"}
	return {"ok": true}


## Public, unauthenticated. Served from the world's heartbeat cache on the master
## (names + scores only). Rate-limited; gateway-cached a few seconds so a busy
## website does not RPC the master on every browser refresh.
func handle_leaderboards(payload: Dictionary) -> Dictionary:
	if not _rate_ok(payload, &"leaderboards", 60, 60000):
		return {"ok": false, "error": "rate_limited"}
	var now: int = Time.get_ticks_msec()
	if not _lb_cache.is_empty() and now - _lb_cache_ms < LB_CACHE_TTL_MS:
		return _lb_cache
	var result: Dictionary = await send_request("public_leaderboards", {}, 4.0)
	if result.get("ok", false):
		_lb_cache = result
		_lb_cache_ms = now
		return result
	if int(result.get("error", 0)) == Error.ERR_TIMEOUT:
		return {"ok": false, "error": "unavailable", "msg": "Leaderboards are temporarily unavailable."}
	if result.get("ok") == false:
		return result
	return {"ok": false, "error": "unavailable", "msg": "Leaderboards are temporarily unavailable."}


## Server-to-server. The world server posts its peddler snapshot here.
##
## FAILS CLOSED. With no secret configured on this gateway the route rejects
## everything — an unconfigured endpoint that accepted writes would let anyone
## who found the URL publish whatever they liked to the front page. It also means
## an operator who sets the key on the world but forgets the gateway gets a clean
## 401 in the world's log rather than a silently ignored POST.
##
## Comparison is constant-time-ish and length-checked before the compare so a
## short key cannot be probed a character at a time.
func handle_peddler_update(payload: Dictionary) -> Dictionary:
	var expected: String = OS.get_environment(PEDDLER_KEY_ENV)
	if expected.is_empty():
		return {"ok": false, "error": "not_configured"}
	# Rate-limited even though it is authenticated: a leaked key should cost the
	# gateway nothing, and the world only posts a handful of times an hour.
	if not _rate_ok(payload, &"peddler_update", 60, 60000):
		return {"ok": false, "error": "rate_limited"}
	var offered: String = str(payload.get("__auth__", ""))
	const PREFIX: String = "Bearer "
	if not offered.begins_with(PREFIX):
		return {"ok": false, "error": "unauthorized"}
	if not _secret_equals(offered.substr(PREFIX.length()), expected):
		return {"ok": false, "error": "unauthorized"}

	# Store only the fields the site renders. Copying field-by-field rather than
	# caching the raw body is what stops the transport keys (__auth__, __ip__)
	# and anything a future world version adds from being echoed to the public.
	_peddler_cache = {
		"schema": int(payload.get("schema", 0)),
		"is_active": bool(payload.get("is_active", false)),
		"current_zone": str(payload.get("current_zone", "")),
		# Schema 2. Absent from an older world server's snapshot, in which case
		# this stays "" and the site simply does not draw the hint.
		"next_zone": str(payload.get("next_zone", "")),
		"time_remaining_seconds": maxi(0, int(payload.get("time_remaining_seconds", 0))),
		"next_spawn_utc_timestamp": maxi(0, int(payload.get("next_spawn_utc_timestamp", 0))),
		"generated_utc_timestamp": maxi(0, int(payload.get("generated_utc_timestamp", 0))),
		"daily_stock": _clean_stock(payload.get("daily_stock", [])),
	}
	_peddler_cache_ms = Time.get_ticks_msec()
	return {"ok": true}


## Public, unauthenticated, and free to serve — it is a dict lookup. Mirrors the
## leaderboards route's contract so the site's two live widgets fail the same way.
func handle_peddler(payload: Dictionary) -> Dictionary:
	if not _rate_ok(payload, &"peddler", 120, 60000):
		return {"ok": false, "error": "rate_limited"}
	if _peddler_cache.is_empty():
		return {
			"ok": false,
			"error": "unavailable",
			"msg": "The Peddler tracker is waiting on the live world.",
		}
	var out: Dictionary = _peddler_cache.duplicate(true)
	out["ok"] = true
	# Age, not a timestamp, so a browser with a wrong clock still reads it right.
	out["age_seconds"] = int((Time.get_ticks_msec() - _peddler_cache_ms) / 1000.0)
	out["stale"] = Time.get_ticks_msec() - _peddler_cache_ms > PEDDLER_STALE_MS
	return out


#region Premium currency
## Server-to-server. The world server asks what an account's balance is.
##
## Answers with a REAL HTTP status code, not 200-with-an-error-body: the caller
## (PremiumApi) branches on the status first, and a 200 carrying {"ok": false}
## would be read as a successful call. That needs the router's __raw__ escape
## hatch, because the normal return path hard-codes 200 for every handler.
func handle_premium_balance(payload: Dictionary) -> Dictionary:
	var auth: Dictionary = _premium_auth(payload)
	if not auth.is_empty():
		return auth
	if not _rate_ok(payload, &"premium_balance", 120, 60000):
		return _json_status(429, {"ok": false, "reason": "rate_limited"})

	var user_id: String = str(payload.get("user_id", "")).strip_edges()
	if user_id.is_empty():
		return _json_status(400, {"ok": false, "reason": "bad_args"})

	var result: Dictionary = await send_request("premium_balance", {"user_id": user_id}, 4.0)
	if int(result.get("error", 0)) == Error.ERR_TIMEOUT:
		return _json_status(503, {"ok": false, "reason": "backend_error"})
	if not bool(result.get("ok", false)):
		return _json_status(503, {"ok": false, "reason": str(result.get("reason", "backend_error"))})
	return _json_status(200, {"ok": true, "data": {"balance": int(result.get("balance", 0))}})


## Server-to-server. Settles one Vault purchase.
##
## The master does the money - price re-derivation, the balance check and the
## atomic deduct all live there, next to the database. This function is the HTTP
## skin: authenticate, pull the idempotency key out of wherever it arrived, and
## map the master's reason onto the status code the caller expects.
func handle_premium_purchase(payload: Dictionary) -> Dictionary:
	var auth: Dictionary = _premium_auth(payload)
	if not auth.is_empty():
		return auth
	if not _rate_ok(payload, &"premium_purchase", 60, 60000):
		return _json_status(429, {"ok": false, "reason": "rate_limited"})

	var user_id: String = str(payload.get("user_id", "")).strip_edges()
	var item_id: String = str(payload.get("item_id", "")).strip_edges()
	var cost: int = int(payload.get("cost", 0))
	# Header first, body second. The header is the HTTP-standard channel and the
	# one a proxy or a retrying client will preserve; the body is what the world
	# actually sends today. Accepting either means neither side has to change to
	# add the other.
	var transaction_id: String = str(payload.get("__idempotency_key__", "")).strip_edges()
	if transaction_id.is_empty():
		transaction_id = str(payload.get("transaction_id", "")).strip_edges()

	if user_id.is_empty() or item_id.is_empty() or transaction_id.is_empty() or cost <= 0:
		return _json_status(400, {"ok": false, "reason": "bad_args"})

	var result: Dictionary = await send_request("premium_purchase", {
		"user_id": user_id,
		"item_id": item_id,
		"cost": cost,
		"transaction_id": transaction_id,
	}, 6.0)

	if int(result.get("error", 0)) == Error.ERR_TIMEOUT:
		# Nothing was charged - send_request timed out before the master answered,
		# OR the master answered too late. The world treats this as "check the
		# balance before retrying", which is the honest instruction: the same
		# transaction_id replayed is safe, a new one is not.
		return _json_status(503, {"ok": false, "reason": "timeout"})

	if bool(result.get("ok", false)):
		var balance: int = int(result.get("balance", 0))
		if bool(result.get("duplicate", false)):
			# Already settled. 409 with the ORIGINAL balance - the caller learns
			# nothing new was charged without having to ask again.
			return _json_status(409, {
				"ok": false,
				"reason": "duplicate",
				"data": {"balance": balance},
			})
		return _json_status(200, {"ok": true, "data": {"balance": balance}})

	var reason: String = str(result.get("reason", "rejected"))
	var body: Dictionary = {"ok": false, "reason": reason}
	if result.has("balance"):
		body["data"] = {"balance": int(result.get("balance", 0))}
	if reason == "price_mismatch" and result.has("cost"):
		body["cost"] = int(result.get("cost", 0))
	return _json_status(_premium_status_for(reason), body)


## Reason -> HTTP status. One table so the two handlers cannot drift, and so the
## mapping is reviewable in one place rather than inline at six return sites.
func _premium_status_for(reason: String) -> int:
	match reason:
		"insufficient_funds":
			return 402
		"duplicate":
			return 409
		"price_mismatch":
			return 409
		"unknown_item", "unknown_account":
			return 404
		"bad_args":
			return 400
		"unavailable", "write_failed", "backend_error", "timeout":
			return 503
	return 400


## Bearer check for the premium routes. Returns {} when the caller is allowed,
## or the ready-made error response when it is not.
##
## FAILS CLOSED. With no secret configured the routes reject everything - an
## unconfigured money endpoint that accepted requests would let anyone who found
## the URL spend other people's balances, and an operator who sets the key on the
## world but forgets the gateway gets a clean 401 in the world's log instead of a
## silently ignored POST.
func _premium_auth(payload: Dictionary) -> Dictionary:
	var expected: String = OS.get_environment(PREMIUM_KEY_ENV)
	if expected.is_empty():
		return _json_status(503, {"ok": false, "reason": "not_configured"})
	var offered: String = str(payload.get("__auth__", ""))
	const PREFIX: String = "Bearer "
	if not offered.begins_with(PREFIX):
		return _json_status(401, {"ok": false, "reason": "unauthorized"})
	if not _secret_equals(offered.substr(PREFIX.length()), expected):
		return _json_status(401, {"ok": false, "reason": "unauthorized"})
	return {}


## JSON body with a chosen status code.
##
## The router sends a plain Dictionary return as 200 unconditionally, so every
## non-200 answer on these routes has to go out through __raw__. utf8, not ascii:
## the shared http_send uses to_ascii_buffer and would mangle any non-ASCII that
## ever reached a reason string.
func _json_status(code: int, body: Dictionary) -> Dictionary:
	return {
		"__raw__": true,
		"code": code,
		"content_type": "application/json; charset=utf-8",
		"body": JSON.stringify(body).to_utf8_buffer(),
	}
#endregion


## Length-checked, full-pass comparison. Returns early ONLY on a length
## mismatch (which the attacker already knows from the key they sent); the byte
## loop never short-circuits, so a correct prefix takes the same time as a wrong
## one.
func _secret_equals(offered: String, expected: String) -> bool:
	if offered.length() != expected.length():
		return false
	var diff: int = 0
	for i: int in expected.length():
		diff |= offered.unicode_at(i) ^ expected.unicode_at(i)
	return diff == 0


## Whitelist the stock rows down to the five display fields, with caps, so a
## compromised or buggy world server cannot push unbounded text onto the site.
func _clean_stock(raw: Variant) -> Array:
	var out: Array = []
	if raw is not Array:
		return out
	for entry: Variant in (raw as Array):
		if entry is not Dictionary:
			continue
		var row: Dictionary = entry as Dictionary
		out.append({
			"id": str(row.get("id", "")).substr(0, 64),
			"name": str(row.get("name", "")).substr(0, 96),
			"price": maxi(0, int(row.get("price", 0))),
			"tier": str(row.get("tier", "")).substr(0, 4),
			"description": str(row.get("description", "")).substr(0, 400),
		})
		if out.size() >= 12:
			break
	return out


func handle_login(payload: Dictionary) -> Dictionary:
	if not _rate_ok(payload, &"login", 10, 60000):
		return {"error": GatewayAPI.ERR_RATE_LIMITED}
	if not payload.has_all(
		[
			GatewayAPI.KEY_ACCOUNT_USERNAME,
			GatewayAPI.KEY_ACCOUNT_PASSWORD
		]
	):
		return {"error": "invalid_payload"}
	# Version gate (shared with the boot handshake) — reject a mismatched build.
	var version_check: Dictionary = _check_version(payload)
	if not version_check.is_empty():
		return version_check
	var result: Dictionary = await send_request("login", payload)
	var error: Error = result.get("error", 0)
	if error != OK:
		return result
	
	result["session_id"] = create_session(result)
	return result


func handle_guest(_payload: Dictionary) -> Dictionary:
	# Permanently disabled. Guest accounts used to be named guestN and could
	# match server_admins.cfg entries for free senior_admin.
	return {"error": GatewayAPI.ERR_GUEST_DISABLED}


func handle_character_create(payload: Dictionary) -> Dictionary:
	if not payload.has_all(
		[
			GatewayAPI.KEY_TOKEN_ID,
			GatewayAPI.KEY_ACCOUNT_USERNAME,
			GatewayAPI.KEY_WORLD_ID,
			"data"
		]
	):
		return {"error": "invalid_payload"}

	var character_data: Dictionary = payload.get("data", null) as Dictionary
	if character_data.is_empty():
		return {"error": 1}
	var result: Dictionary = CredentialsUtils.validate_username(character_data.get("name", ""))
	if result.get("code", CredentialsUtils.UsernameError.EMPTY) != CredentialsUtils.UsernameError.OK:
		return {"error": result}

	var response: Dictionary = await send_request("create_character", payload)
	var error: Error = response.get("error", 0)
	if error != OK:
		return response

	return response


func handle_world_characters(payload: Dictionary) -> Dictionary:
	if not payload.has_all(
		[
			GatewayAPI.KEY_TOKEN_ID,
			GatewayAPI.KEY_ACCOUNT_USERNAME,
			GatewayAPI.KEY_WORLD_ID,
		]
	):
		return {"error": "invalid_payload"}

	var response: Dictionary = await send_request("get_characters", payload)
	var error: Error = response.get("error", 0)
	if error != OK:
		return response

	return response



func handle_world_enter(payload: Dictionary) -> Dictionary:
	if not payload.has_all(
		[
			GatewayAPI.KEY_TOKEN_ID,
			GatewayAPI.KEY_ACCOUNT_USERNAME,
			GatewayAPI.KEY_WORLD_ID,
			GatewayAPI.KEY_CHAR_ID
		]
	):
		return {"error": "invalid_payload"}

	var response: Dictionary = await send_request("enter_world", payload)
	var error: Error = response.get("error", 0)
	if error != OK:
		# Keep "msg" — a ban rejection carries its reason there, and stripping it
		# would leave the client with a bare code and nothing to show the player.
		return {"error": error, "msg": str(response.get("msg", ""))}

	return response


## Cheap world-list refresh: served straight from the gateway's cached roster
## (the master broadcasts it on every world connect/disconnect), so no master
## round-trip per refresh. Used by the client's "Update" button and the
## empty-state auto-retry.
func handle_worlds(_payload: Dictionary) -> Dictionary:
	return {"w": _public_worlds(gateway_manager_client.worlds_info)}


## Whitelist only what a world card needs. The cached roster also carries each
## world's address, port and full heartbeat snapshot (player rosters, chat tail,
## server logs) — never ship those to a game client.
func _public_worlds(raw: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for world_id: Variant in raw:
		var info: Dictionary = raw[world_id].get("info", {})
		out[world_id] = {
			"info": {
				"name": info.get("name", ""),
				"motd": info.get("motd", ""),
				"pvp": info.get("pvp", false),
			}
		}
	return out


func handle_account_creation(payload: Dictionary) -> Dictionary:
	if not _rate_ok(payload, &"account_create", 5, 300000):
		return {"error": GatewayAPI.ERR_RATE_LIMITED}
	if not payload.has_all(
		[
			GatewayAPI.KEY_ACCOUNT_USERNAME,
			GatewayAPI.KEY_ACCOUNT_PASSWORD,
		]
	):
		return {"error": "invalid_payload"}

	# Validate server-side too — never trust the client's pre-check (length, chars,
	# reserved names). Same CredentialsUtils the client uses, so messages match.
	var username: String = str(payload.get(GatewayAPI.KEY_ACCOUNT_USERNAME, ""))
	var password: String = str(payload.get(GatewayAPI.KEY_ACCOUNT_PASSWORD, ""))
	var uname_check: Dictionary = CredentialsUtils.validate_username(username)
	if uname_check.get("code", CredentialsUtils.UsernameError.EMPTY) != CredentialsUtils.UsernameError.OK:
		return {"error": str(uname_check.get("message", "Invalid username."))}
	var pass_check: Dictionary = CredentialsUtils.validate_password(password)
	if pass_check.get("code", CredentialsUtils.UsernameError.EMPTY) != CredentialsUtils.UsernameError.OK:
		return {"error": str(pass_check.get("message", "Invalid password."))}

	var response: Dictionary = await send_request("create_account", payload)
	var error: Error = response.get("error", 0)
	if error != OK:
		return {"error": error}

	return response
