extends SceneTree
## Headless probe: login → enter world → multiplayer auth against LIVE.
## Usage:
##   godot --headless --path . -s tools/probe_live_enter.gd
## Optional: --api=https://api.arkenelle.com --user=... --pass=...

const API_DEFAULT := "https://api.arkenelle.com"

var _http: HTTPRequest
var _api: String
var _user: String
var _pass: String
var _session: String = ""
var _world_id: int = -1
var _char_id: int = -1
var _done: bool = false


func _initialize() -> void:
	var args: Dictionary = CmdlineUtils.get_parsed_args()
	_api = str(args.get("api", API_DEFAULT)).rstrip("/")
	var stamp: int = int(Time.get_unix_time_from_system())
	_user = str(args.get("user", "probe_%d" % stamp))
	_pass = str(args.get("pass", "probe-pass-%d" % stamp))
	print("PROBE api=%s user=%s" % [_api, _user])
	_http = HTTPRequest.new()
	root.add_child(_http)
	call_deferred("_run")


func _run() -> void:
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	print("PROBE client_version=%s" % version)

	var hs: Dictionary = await _post("/v1/handshake", {GatewayAPI.KEY_CLIENT_VERSION: version})
	print("PROBE handshake=%s" % JSON.stringify(hs))
	if hs.get("error") != null and str(hs.get("error")) != "0" and hs.get("ok") != true:
		return _fail_done("handshake failed")

	# Try create; ignore already-exists then login.
	var created: Dictionary = await _post("/v1/account/create", {
		GatewayAPI.KEY_ACCOUNT_USERNAME: _user,
		GatewayAPI.KEY_ACCOUNT_PASSWORD: _pass,
	})
	print("PROBE create=%s" % JSON.stringify(created))

	var login: Dictionary = await _post("/v1/login", {
		GatewayAPI.KEY_ACCOUNT_USERNAME: _user,
		GatewayAPI.KEY_ACCOUNT_PASSWORD: _pass,
		GatewayAPI.KEY_CLIENT_VERSION: version,
	})
	print("PROBE login=%s" % JSON.stringify(login))
	if login.has("error") and int(login.get("error", 0)) != 0:
		return _fail_done("login failed")
	_session = str(login.get("session_id", login.get(GatewayAPI.KEY_TOKEN_ID, "")))
	if _session.is_empty():
		return _fail_done("no session token in login")

	var worlds: Dictionary = login.get("w", {})
	if worlds.is_empty():
		worlds = await _post("/v1/worlds", {})
		worlds = worlds.get("w", worlds)
	print("PROBE worlds=%s" % JSON.stringify(worlds))
	if typeof(worlds) != TYPE_DICTIONARY or worlds.is_empty():
		return _fail_done("no worlds")
	_world_id = int(worlds.keys()[0])

	var chars: Dictionary = await _post("/v1/world/characters", {
		GatewayAPI.KEY_TOKEN_ID: _session,
		GatewayAPI.KEY_ACCOUNT_USERNAME: _user,
		GatewayAPI.KEY_WORLD_ID: _world_id,
	})
	print("PROBE characters=%s" % JSON.stringify(chars))

	# Find or create a character.
	var enter: Dictionary = {}
	_char_id = _first_char_id(chars)
	if _char_id < 0:
		var created_char: Dictionary = await _post("/v1/world/character/create", {
			GatewayAPI.KEY_TOKEN_ID: _session,
			GatewayAPI.KEY_ACCOUNT_USERNAME: _user,
			GatewayAPI.KEY_WORLD_ID: _world_id,
			"data": {
				"name": "P%d" % (int(Time.get_unix_time_from_system()) % 100000),
				"skin": 1,
			},
		})
		print("PROBE char_create=%s" % JSON.stringify(created_char))
		# Create-character success returns enter payload (auth-token/address).
		if created_char.has("auth-token"):
			enter = created_char
		else:
			chars = await _post("/v1/world/characters", {
				GatewayAPI.KEY_TOKEN_ID: _session,
				GatewayAPI.KEY_ACCOUNT_USERNAME: _user,
				GatewayAPI.KEY_WORLD_ID: _world_id,
			})
			print("PROBE characters2=%s" % JSON.stringify(chars))
			_char_id = _first_char_id(chars)
	if enter.is_empty():
		if _char_id < 0:
			return _fail_done("no character id")
		enter = await _post("/v1/world/enter", {
			GatewayAPI.KEY_TOKEN_ID: _session,
			GatewayAPI.KEY_ACCOUNT_USERNAME: _user,
			GatewayAPI.KEY_WORLD_ID: _world_id,
			GatewayAPI.KEY_CHAR_ID: _char_id,
		})
	print("PROBE enter=%s" % JSON.stringify(enter))
	if enter.has("error") and str(enter.get("error")) != "0" and int(enter.get("error", 0)) != 0:
		return _fail_done("enter failed")

	var address: String = str(enter.get("address", ""))
	var port: int = int(enter.get("port", 0))
	var token: String = str(enter.get("auth-token", ""))
	print("PROBE connect address=%s port=%d token_len=%d" % [address, port, token.length()])
	if address.is_empty() or token.is_empty():
		return _fail_done("missing address/token")

	await _connect_world(address, port, token)


func _connect_world(address: String, port: int, token: String) -> void:
	var peer := WebSocketMultiplayerPeer.new()
	var url: String
	if address.contains("://"):
		url = address
	else:
		url = "ws://%s:%d" % [address, port]
	print("PROBE ws_url=%s" % url)
	var err: Error = peer.create_client(url)
	print("PROBE create_client err=%s" % error_string(err))
	if err != OK:
		return _fail_done("create_client failed")

	var api: MultiplayerAPI = MultiplayerAPI.create_default_interface()
	api.multiplayer_peer = peer
	# SceneTree owns multiplayer APIs — root is a Window and has no set_multiplayer.
	set_multiplayer(api, NodePath("/root"))

	api.connected_to_server.connect(func() -> void:
		print("PROBE connected_to_server peer=%d" % api.get_unique_id())
	)
	api.connection_failed.connect(func() -> void:
		print("PROBE connection_failed")
		_fail_done("connection_failed")
	)
	api.server_disconnected.connect(func() -> void:
		print("PROBE server_disconnected")
	)
	api.peer_authenticating.connect(func(pid: int) -> void:
		print("PROBE peer_authenticating pid=%d" % pid)
	)
	api.peer_authentication_failed.connect(func(pid: int) -> void:
		print("PROBE peer_authentication_failed pid=%d" % pid)
		_fail_done("auth failed")
	)
	api.set_auth_callback(func(pid: int, data: PackedByteArray) -> void:
		print("PROBE auth_callback from server data='%s'" % data.get_string_from_ascii())
		api.send_auth(1, var_to_bytes(token))
		api.complete_auth(1)
		print("PROBE sent auth token + complete_auth")
	)

	# Poll until connected or timeout.
	var start_ms: int = Time.get_ticks_msec()
	while not _done and Time.get_ticks_msec() - start_ms < 25000:
		api.poll()
		peer.poll()
		await create_timer(0.05).timeout
		var st: int = peer.get_connection_status()
		if st == MultiplayerPeer.CONNECTION_CONNECTED and api.has_multiplayer_peer():
			# Stay a bit after connect to see if anything else arrives.
			if Time.get_ticks_msec() - start_ms > 8000:
				print("PROBE still connected after wait — auth OK, no further client RPCs in this probe")
				_ok_done("connected")
				return
		elif st == MultiplayerPeer.CONNECTION_DISCONNECTED and Time.get_ticks_msec() - start_ms > 2000:
			print("PROBE peer disconnected early")
			return _fail_done("disconnected")

	if not _done:
		_fail_done("timeout waiting for world connect/auth")


func _first_char_id(chars: Dictionary) -> int:
	for key: Variant in chars.keys():
		var ks: String = str(key)
		if ks.is_valid_int() and typeof(chars[key]) == TYPE_DICTIONARY:
			return int(ks)
	for nest_key: String in ["c", "characters", "chars"]:
		if chars.has(nest_key) and typeof(chars[nest_key]) == TYPE_DICTIONARY:
			return _first_char_id(chars[nest_key])
	return -1


func _post(path: String, body: Dictionary) -> Dictionary:
	var payload: String = JSON.stringify(body)
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err: Error = _http.request(_api + path, headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		print("PROBE http request err=%s path=%s" % [error_string(err), path])
		return {"error": "request_error", "msg": error_string(err)}
	var result: Array = await _http.request_completed
	var response_code: int = int(result[1])
	var raw: String = (result[3] as PackedByteArray).get_string_from_utf8()
	print("PROBE HTTP %s -> %d (%d bytes)" % [path, response_code, raw.length()])
	if raw.is_empty():
		return {"error": "empty", "code": response_code}
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"error": "bad_json", "raw": raw.substr(0, 200), "code": response_code}
	return parsed


func _fail_done(msg: String) -> void:
	print("PROBE_FAIL %s" % msg)
	_done = true
	quit(1)


func _ok_done(msg: String) -> void:
	print("PROBE_PASS %s" % msg)
	_done = true
	quit(0)
